import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/core/utils/currency_formatter.dart';
import 'package:finance_tracker/core/utils/date_formatter.dart';
import 'package:finance_tracker/data/local/database.dart';

void main() {
  group('Formatters Test', () {
    test('CurrencyFormatter formats and parses IDR amounts accurately', () {
      expect(CurrencyFormatter.parse('Rp 50.000'), equals(50000));
      expect(CurrencyFormatter.parse('1.250.000'), equals(1250000));
      expect(CurrencyFormatter.parse(''), equals(0));

      final formatted = CurrencyFormatter.format(75000);
      expect(formatted.contains('75.000'), isTrue);
    });

    test('DateFormatter handles ISO dates and month formatting', () {
      final dt = DateTime(2026, 11, 15);
      final iso = DateFormatter.toIsoDate(dt);
      expect(iso, equals('2026-11-15'));

      final parsed = DateFormatter.parseIsoDate('2026-11-15');
      expect(parsed.year, equals(2026));
      expect(parsed.month, equals(11));
      expect(parsed.day, equals(15));
    });
  });

  group('Drift Offline-First & Outbox Engine Test', () {
    late AppDatabase db;

    setUp(() {
      // Use in-memory SQLite for test isolation
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('Create transaction writes to transactions table and logs to outbox', () async {
      await db.createTransaction(
        userId: 'test_user_1',
        amount: 50000,
        type: 'expense',
        category: 'Makanan',
        note: 'Makan Siang',
        date: '2026-11-15',
      );

      // Verify transaction list stream for November 2026
      final txList = await db.watchTransactionsForMonth(2026, 11).first;
      expect(txList.length, equals(1));
      final tx = txList.first;
      expect(tx.amount, equals(50000));
      expect(tx.category, equals('Makanan'));
      expect(tx.syncStatus, equals('pending'));
      expect(tx.version, equals(1));

      // Verify outbox queue
      final outbox = await db.getPendingOutbox();
      expect(outbox.length, equals(1));
      final outboxItem = outbox.first;
      expect(outboxItem.transactionId, equals(tx.id));
      expect(outboxItem.action, equals('create'));
      expect(outboxItem.status, equals('pending'));

      final payload = jsonDecode(outboxItem.payload) as Map<String, dynamic>;
      expect(payload['amount'], equals(50000));
    });

    test('Soft delete hides transaction from monthly stream and logs delete to outbox', () async {
      await db.createTransaction(
        userId: 'test_user_1',
        amount: 25000,
        type: 'expense',
        category: 'Transportasi',
        date: '2026-11-16',
      );

      final initialList = await db.watchTransactionsForMonth(2026, 11).first;
      final txId = initialList.first.id;

      // Soft delete
      await db.softDeleteTransaction(txId);

      // Stream should now be empty (latency 0ms local reflection)
      final afterDeleteList = await db.watchTransactionsForMonth(2026, 11).first;
      expect(afterDeleteList.isEmpty, isTrue);

      // Outbox should contain create and delete entries
      final outbox = await db.getPendingOutbox();
      expect(outbox.length, equals(2));
      expect(outbox.last.action, equals('delete'));
      expect(outbox.last.transactionId, equals(txId));
    });

    test('Push success purges outbox and updates syncStatus to synced', () async {
      await db.createTransaction(
        userId: 'test_user_1',
        amount: 100000,
        type: 'income',
        category: 'Gaji',
        date: '2026-11-01',
      );

      final outbox = await db.getPendingOutbox();
      final outboxId = outbox.first.id;
      final txId = outbox.first.transactionId;

      // Mark applied from server
      await db.handleAppliedBatch(
        appliedList: [
          {
            'id': txId,
            'version': 2,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }
        ],
        processedOutboxIds: [outboxId],
        nextCursor: 'cursor_token_123',
      );

      // Outbox should now be empty
      final remainingOutbox = await db.getPendingOutbox();
      expect(remainingOutbox.isEmpty, isTrue);

      // Transaction sync status should be synced
      final updatedTx = await db.getTransactionById(txId);
      expect(updatedTx!.syncStatus, equals('synced'));
      expect(updatedTx.version, equals(2));

      // Cursor should be saved
      final cursor = await db.getSyncState('last_pulled_cursor');
      expect(cursor, equals('cursor_token_123'));
    });

    test('Conflict handling marks transaction and outbox as conflict', () async {
      await db.createTransaction(
        userId: 'test_user_1',
        amount: 30000,
        type: 'expense',
        category: 'Belanja',
        date: '2026-11-10',
      );

      final outbox = await db.getPendingOutbox();
      final txId = outbox.first.transactionId;

      await db.handleConflictBatch(
        conflictList: [
          {'id': txId, 'conflict_reason': 'Version mismatch'}
        ],
        inFlightOutboxIds: [outbox.first.id],
      );

      final tx = await db.getTransactionById(txId);
      expect(tx!.syncStatus, equals('conflict'));
    });
  });
}
