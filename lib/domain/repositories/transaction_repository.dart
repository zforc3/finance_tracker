import '../../data/local/database.dart';

class TransactionRepository {
  final AppDatabase _db;

  TransactionRepository(this._db);

  Stream<List<TransactionEntry>> watchTransactionsForMonth(int year, int month) {
    return _db.watchTransactionsForMonth(year, month);
  }

  Future<TransactionEntry?> getTransactionById(String id) {
    return _db.getTransactionById(id);
  }

  Future<void> createTransaction({
    required String userId,
    required int amount,
    required String type,
    required String category,
    String? note,
    required String date,
  }) {
    return _db.createTransaction(
      userId: userId,
      amount: amount,
      type: type,
      category: category,
      note: note,
      date: date,
    );
  }

  Future<void> updateTransaction({
    required String id,
    required int amount,
    required String type,
    required String category,
    String? note,
    required String date,
  }) {
    return _db.updateTransaction(
      id: id,
      amount: amount,
      type: type,
      category: category,
      note: note,
      date: date,
    );
  }

  Future<void> deleteTransaction(String id) {
    return _db.softDeleteTransaction(id);
  }
}
