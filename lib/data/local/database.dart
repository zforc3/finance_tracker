import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Transactions, SyncOutbox, SyncState])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? driftDatabase(name: 'finance_tracker'));

  @override
  int get schemaVersion => 1;

  static const _uuid = Uuid();

  // -------------------------------------------------------------
  // Transactions Queries & Streams
  // -------------------------------------------------------------

  Stream<List<TransactionEntry>> watchTransactionsForMonth(int year, int month) {
    final prefix = '$year-${month.toString().padLeft(2, '0')}';
    return (select(transactions)
          ..where((tbl) =>
              tbl.deletedAt.isNull() &
              tbl.date.like('$prefix%'))
          ..orderBy([
            (tbl) => OrderingTerm(expression: tbl.date, mode: OrderingMode.desc),
            (tbl) => OrderingTerm(expression: tbl.updatedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<TransactionEntry?> getTransactionById(String id) {
    return (select(transactions)..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> createTransaction({
    required String userId,
    required int amount,
    required String type,
    required String category,
    String? note,
    required String date,
  }) {
    return transaction(() async {
      final txId = _uuid.v4();
      final outboxId = _uuid.v4();
      final now = DateTime.now();

      final payload = jsonEncode({
        'id': txId,
        'action': 'create',
        'base_version': 0,
        'amount': amount,
        'type': type,
        'category': category,
        'note': note,
        'date': date,
        'client_updated_at': now.toUtc().toIso8601String(),
      });

      await into(transactions).insert(TransactionsCompanion.insert(
        id: txId,
        userId: userId,
        amount: amount,
        type: type,
        category: category,
        note: Value(note),
        date: date,
        version: const Value(1),
        syncStatus: const Value('pending'),
        updatedAt: Value(now),
      ));

      await into(syncOutbox).insert(SyncOutboxCompanion.insert(
        id: outboxId,
        transactionId: txId,
        action: 'create',
        baseVersion: const Value(0),
        payload: payload,
        status: const Value('pending'),
        createdAt: Value(now),
      ));
    });
  }

  Future<void> updateTransaction({
    required String id,
    required int amount,
    required String type,
    required String category,
    String? note,
    required String date,
  }) {
    return transaction(() async {
      final existing = await getTransactionById(id);
      if (existing == null) return;

      final now = DateTime.now();
      final outboxId = _uuid.v4();

      final payload = jsonEncode({
        'id': id,
        'action': 'update',
        'base_version': existing.version,
        'amount': amount,
        'type': type,
        'category': category,
        'note': note,
        'date': date,
        'client_updated_at': now.toUtc().toIso8601String(),
      });

      await (update(transactions)..where((tbl) => tbl.id.equals(id))).write(
        TransactionsCompanion(
          amount: Value(amount),
          type: Value(type),
          category: Value(category),
          note: Value(note),
          date: Value(date),
          syncStatus: const Value('pending'),
          updatedAt: Value(now),
        ),
      );

      await into(syncOutbox).insert(SyncOutboxCompanion.insert(
        id: outboxId,
        transactionId: id,
        action: 'update',
        baseVersion: Value(existing.version),
        payload: payload,
        status: const Value('pending'),
        createdAt: Value(now),
      ));
    });
  }

  Future<void> softDeleteTransaction(String id) {
    return transaction(() async {
      final existing = await getTransactionById(id);
      if (existing == null) return;

      final now = DateTime.now();
      final outboxId = _uuid.v4();

      final payload = jsonEncode({
        'id': id,
        'action': 'delete',
        'base_version': existing.version,
        'client_updated_at': now.toUtc().toIso8601String(),
      });

      await (update(transactions)..where((tbl) => tbl.id.equals(id))).write(
        TransactionsCompanion(
          deletedAt: Value(now),
          syncStatus: const Value('pending'),
          updatedAt: Value(now),
        ),
      );

      await into(syncOutbox).insert(SyncOutboxCompanion.insert(
        id: outboxId,
        transactionId: id,
        action: 'delete',
        baseVersion: Value(existing.version),
        payload: payload,
        status: const Value('pending'),
        createdAt: Value(now),
      ));
    });
  }

  // -------------------------------------------------------------
  // Outbox & Sync Queries
  // -------------------------------------------------------------

  Future<List<SyncOutboxEntry>> getPendingOutbox() {
    return (select(syncOutbox)
          ..where((tbl) => tbl.status.equals('pending'))
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.createdAt)]))
        .get();
  }

  Future<void> markOutboxInFlight(List<String> ids) {
    return (update(syncOutbox)..where((tbl) => tbl.id.isIn(ids)))
        .write(const SyncOutboxCompanion(status: Value('in_flight')));
  }

  Future<void> markOutboxPending(List<String> ids) {
    return (update(syncOutbox)..where((tbl) => tbl.id.isIn(ids)))
        .write(const SyncOutboxCompanion(status: Value('pending')));
  }

  Future<void> handleAppliedBatch({
    required List<Map<String, dynamic>> appliedList,
    required List<String> processedOutboxIds,
    String? nextCursor,
  }) {
    return transaction(() async {
      // Remove applied outbox entries
      if (processedOutboxIds.isNotEmpty) {
        await (delete(syncOutbox)..where((tbl) => tbl.id.isIn(processedOutboxIds))).go();
      }

      // Update local transactions to synced and assign server version
      for (final applied in appliedList) {
        final txId = applied['id'] as String;
        final serverVer = applied['version'] as int;
        final updatedStr = applied['updated_at'] as String?;
        final updatedAt = updatedStr != null ? DateTime.tryParse(updatedStr) : null;

        await (update(transactions)..where((tbl) => tbl.id.equals(txId))).write(
          TransactionsCompanion(
            version: Value(serverVer),
            syncStatus: const Value('synced'),
            updatedAt: updatedAt != null ? Value(updatedAt) : const Value.absent(),
          ),
        );
      }

      if (nextCursor != null) {
        await setSyncState('last_pulled_cursor', nextCursor);
      }
      await setSyncState('last_sync_time', DateTime.now().toUtc().toIso8601String());
    });
  }

  Future<void> handleConflictBatch({
    required List<Map<String, dynamic>> conflictList,
    required List<String> inFlightOutboxIds,
  }) {
    return transaction(() async {
      for (final conflict in conflictList) {
        final txId = conflict['id'] as String;
        // Mark outbox entry as conflict
        await (update(syncOutbox)
              ..where((tbl) => tbl.transactionId.equals(txId) & tbl.id.isIn(inFlightOutboxIds)))
            .write(const SyncOutboxCompanion(status: Value('conflict')));

        // Mark transaction as conflict
        await (update(transactions)..where((tbl) => tbl.id.equals(txId))).write(
          const TransactionsCompanion(syncStatus: Value('conflict')),
        );
      }
    });
  }

  Future<void> applyPullChanges({
    required List<Map<String, dynamic>> serverItems,
    String? nextCursor,
  }) {
    return transaction(() async {
      // Get all pending/in_flight outbox transaction IDs
      final activeOutbox = await (select(syncOutbox)
            ..where((tbl) => tbl.status.isIn(['pending', 'in_flight', 'conflict'])))
          .get();
      final activeTxIds = activeOutbox.map((e) => e.transactionId).toSet();

      for (final item in serverItems) {
        final txId = item['id'] as String;
        final userId = item['user_id'] as String;
        final amount = item['amount'] as int;
        final type = item['type'] as String;
        final category = item['category'] as String;
        final note = item['note'] as String?;
        final date = item['date'] as String;
        final version = item['version'] as int;
        final deletedAtStr = item['deleted_at'] as String?;
        final deletedAt = deletedAtStr != null ? DateTime.tryParse(deletedAtStr) : null;
        final updatedAtStr = item['updated_at'] as String;
        final updatedAt = DateTime.parse(updatedAtStr);

        if (activeTxIds.contains(txId)) {
          // If local has active changes, flag conflict
          await (update(transactions)..where((tbl) => tbl.id.equals(txId))).write(
            const TransactionsCompanion(syncStatus: Value('conflict')),
          );
        } else {
          // Clean update/insert from server
          await into(transactions).insertOnConflictUpdate(TransactionsCompanion(
            id: Value(txId),
            userId: Value(userId),
            amount: Value(amount),
            type: Value(type),
            category: Value(category),
            note: Value(note),
            date: Value(date),
            version: Value(version),
            syncStatus: const Value('synced'),
            deletedAt: Value(deletedAt),
            updatedAt: Value(updatedAt),
          ));
        }
      }

      if (nextCursor != null) {
        await setSyncState('last_pulled_cursor', nextCursor);
      }
      await setSyncState('last_sync_time', DateTime.now().toUtc().toIso8601String());
    });
  }

  // -------------------------------------------------------------
  // Conflict Resolution
  // -------------------------------------------------------------

  Future<void> resolveConflictWithServerRecord({
    required String transactionId,
    required Map<String, dynamic> serverRecord,
  }) {
    return transaction(() async {
      // User chose server version: discard outbox entries
      await (delete(syncOutbox)..where((tbl) => tbl.transactionId.equals(transactionId))).go();

      final userId = serverRecord['user_id'] as String;
      final amount = serverRecord['amount'] as int;
      final type = serverRecord['type'] as String;
      final category = serverRecord['category'] as String;
      final note = serverRecord['note'] as String?;
      final date = serverRecord['date'] as String;
      final version = serverRecord['version'] as int;
      final deletedAtStr = serverRecord['deleted_at'] as String?;
      final deletedAt = deletedAtStr != null ? DateTime.tryParse(deletedAtStr) : null;
      final updatedAt = DateTime.parse(serverRecord['updated_at'] as String);

      await into(transactions).insertOnConflictUpdate(TransactionsCompanion(
        id: Value(transactionId),
        userId: Value(userId),
        amount: Value(amount),
        type: Value(type),
        category: Value(category),
        note: Value(note),
        date: Value(date),
        version: Value(version),
        syncStatus: const Value('synced'),
        deletedAt: Value(deletedAt),
        updatedAt: Value(updatedAt),
      ));
    });
  }

  Future<void> resolveConflictWithClientRecord({
    required String transactionId,
    required int serverVersion,
  }) {
    return transaction(() async {
      // User chose client version: bump base_version in outbox to serverVersion, set to pending
      await (update(syncOutbox)
            ..where((tbl) => tbl.transactionId.equals(transactionId)))
          .write(SyncOutboxCompanion(
        baseVersion: Value(serverVersion),
        status: const Value('pending'),
      ));

      await (update(transactions)..where((tbl) => tbl.id.equals(transactionId))).write(
        const TransactionsCompanion(syncStatus: Value('pending')),
      );
    });
  }

  // -------------------------------------------------------------
  // Sync State
  // -------------------------------------------------------------

  Future<String?> getSyncState(String key) async {
    final entry = await (select(syncState)..where((tbl) => tbl.key.equals(key)))
        .getSingleOrNull();
    return entry?.value;
  }

  Future<void> setSyncState(String key, String value) {
    return into(syncState).insertOnConflictUpdate(SyncStateCompanion(
      key: Value(key),
      value: Value(value),
    ));
  }

  Future<void> clearAll() {
    return transaction(() async {
      await delete(syncOutbox).go();
      await delete(transactions).go();
      await delete(syncState).go();
    });
  }
}
