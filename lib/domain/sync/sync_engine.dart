import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../core/network/api_client.dart';
import '../../data/local/database.dart';

enum SyncStatusState { idle, syncing, error }

class SyncResult {
  final int pushedCount;
  final int conflictsCount;
  final int pulledCount;
  final String? error;

  const SyncResult({
    this.pushedCount = 0,
    this.conflictsCount = 0,
    this.pulledCount = 0,
    this.error,
  });
}

class SyncEngine {
  final AppDatabase _db;
  final ApiClient _apiClient;
  static const _uuid = Uuid();
  bool _isSyncing = false;

  // Cache for active conflicts to display in UI comparison
  final Map<String, Map<String, dynamic>> _conflictServerRecords = {};

  SyncEngine(this._db, this._apiClient);

  Map<String, dynamic>? getConflictServerRecord(String transactionId) {
    return _conflictServerRecords[transactionId];
  }

  Future<SyncResult> sync() async {
    if (_isSyncing) {
      return const SyncResult();
    }
    _isSyncing = true;

    int pushedCount = 0;
    int conflictsCount = 0;
    int pulledCount = 0;

    try {
      // ---------------------------------------------------------
      // Step 1: Push Outbox
      // ---------------------------------------------------------
      final pendingOutbox = await _db.getPendingOutbox();
      if (pendingOutbox.isNotEmpty) {
        final outboxIds = pendingOutbox.map((e) => e.id).toList();
        await _db.markOutboxInFlight(outboxIds);

        final batchId = _uuid.v4();
        final items = <Map<String, dynamic>>[];

        for (final entry in pendingOutbox) {
          try {
            final payloadMap = jsonDecode(entry.payload) as Map<String, dynamic>;
            items.add(payloadMap);
          } catch (_) {}
        }

        try {
          final pushResponse = await _apiClient.pushBatch(
            batchId: batchId,
            items: items,
          );

          final applied = (pushResponse['applied'] as List? ?? [])
              .map((e) => e as Map<String, dynamic>)
              .toList();
          final conflicts = (pushResponse['conflicts'] as List? ?? [])
              .map((e) => e as Map<String, dynamic>)
              .toList();

          pushedCount = applied.length;
          conflictsCount = conflicts.length;

          // Cache server records for conflict dialog
          for (final c in conflicts) {
            final txId = c['id'] as String;
            final sRecord = c['server_record'] as Map<String, dynamic>?;
            if (sRecord != null) {
              _conflictServerRecords[txId] = sRecord;
            }
          }

          if (applied.isNotEmpty) {
            final appliedIds = applied.map((e) => e['id'] as String).toSet();
            final appliedOutboxIds = pendingOutbox
                .where((e) => appliedIds.contains(e.transactionId))
                .map((e) => e.id)
                .toList();

            await _db.handleAppliedBatch(
              appliedList: applied,
              processedOutboxIds: appliedOutboxIds,
            );
          }

          if (conflicts.isNotEmpty) {
            await _db.handleConflictBatch(
              conflictList: conflicts,
              inFlightOutboxIds: outboxIds,
            );
          }
        } catch (e) {
          // If network failed during push, reset in_flight back to pending
          await _db.markOutboxPending(outboxIds);
          rethrow;
        }
      }

      // ---------------------------------------------------------
      // Step 2: Pull Server Changes
      // ---------------------------------------------------------
      final cursor = await _db.getSyncState('last_pulled_cursor');
      final pullResponse = await _apiClient.pull(cursor: cursor, limit: 100);

      final items = (pullResponse['items'] as List? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      final nextCursor = pullResponse['next_cursor'] as String?;

      pulledCount = items.length;

      if (items.isNotEmpty) {
        await _db.applyPullChanges(
          serverItems: items,
          nextCursor: nextCursor,
        );
      } else if (nextCursor != null) {
        await _db.setSyncState('last_pulled_cursor', nextCursor);
      }

      return SyncResult(
        pushedCount: pushedCount,
        conflictsCount: conflictsCount,
        pulledCount: pulledCount,
      );
    } catch (e) {
      return SyncResult(
        pushedCount: pushedCount,
        conflictsCount: conflictsCount,
        pulledCount: pulledCount,
        error: e.toString(),
      );
    } finally {
      _isSyncing = false;
    }
  }

  // -------------------------------------------------------------
  // Conflict Resolution
  // -------------------------------------------------------------

  Future<void> resolveConflict({
    required String transactionId,
    required String choice, // 'use_server' or 'use_client'
  }) async {
    final serverRecord = _conflictServerRecords[transactionId];
    final localTx = await _db.getTransactionById(transactionId);

    if (serverRecord == null || localTx == null) {
      // If server record not cached, do standard pull
      await sync();
      return;
    }

    final targetVersion = serverRecord['version'] as int;

    if (choice == 'use_server') {
      try {
        await _apiClient.resolveConflict(
          id: transactionId,
          resolution: 'use_server',
          targetVersion: targetVersion,
        );
      } catch (_) {}

      await _db.resolveConflictWithServerRecord(
        transactionId: transactionId,
        serverRecord: serverRecord,
      );
      _conflictServerRecords.remove(transactionId);
    } else {
      // use_client
      final clientData = {
        'amount': localTx.amount,
        'type': localTx.type,
        'category': localTx.category,
        'note': localTx.note,
        'date': localTx.date,
      };

      try {
        final res = await _apiClient.resolveConflict(
          id: transactionId,
          resolution: 'use_client',
          targetVersion: targetVersion,
          clientData: clientData,
        );
        final newVersion = res['version'] as int;

        await _db.handleAppliedBatch(
          appliedList: [
            {'id': transactionId, 'version': newVersion, 'updated_at': res['updated_at']}
          ],
          processedOutboxIds: [],
        );
      } catch (_) {
        // Fallback: mark outbox to retry with updated base_version
        await _db.resolveConflictWithClientRecord(
          transactionId: transactionId,
          serverVersion: targetVersion,
        );
      }
      _conflictServerRecords.remove(transactionId);
    }
  }
}
