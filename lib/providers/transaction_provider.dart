import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local/database.dart';
import '../domain/repositories/transaction_repository.dart';
import 'auth_provider.dart';
import 'database_provider.dart';
import 'sync_provider.dart';

class MonthFilter {
  final int year;
  final int month;

  const MonthFilter({required this.year, required this.month});

  MonthFilter previousMonth() {
    if (month == 1) {
      return MonthFilter(year: year - 1, month: 12);
    }
    return MonthFilter(year: year, month: month - 1);
  }

  MonthFilter nextMonth() {
    if (month == 12) {
      return MonthFilter(year: year + 1, month: 1);
    }
    return MonthFilter(year: year, month: month + 1);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MonthFilter &&
          runtimeType == other.runtimeType &&
          year == other.year &&
          month == other.month;

  @override
  int get hashCode => year.hashCode ^ month.hashCode;
}

class SelectedMonthNotifier extends Notifier<MonthFilter> {
  @override
  MonthFilter build() {
    final now = DateTime.now();
    return MonthFilter(year: now.year, month: now.month);
  }

  void setFilter(MonthFilter filter) => state = filter;
  void previousMonth() => state = state.previousMonth();
  void nextMonth() => state = state.nextMonth();
}

final selectedMonthProvider =
    NotifierProvider<SelectedMonthNotifier, MonthFilter>(SelectedMonthNotifier.new);

final monthlyTransactionsProvider = StreamProvider<List<TransactionEntry>>((ref) {
  final repo = ref.watch(transactionRepositoryProvider);
  final filter = ref.watch(selectedMonthProvider);
  return repo.watchTransactionsForMonth(filter.year, filter.month);
});

class MonthlySummary {
  final int totalIncome;
  final int totalExpense;
  final int netBalance;

  const MonthlySummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.netBalance,
  });
}

final monthlySummaryProvider = Provider<MonthlySummary>((ref) {
  final asyncTxList = ref.watch(monthlyTransactionsProvider);
  final txList = asyncTxList.value ?? [];

  int income = 0;
  int expense = 0;

  for (final tx in txList) {
    if (tx.type == 'income') {
      income += tx.amount;
    } else if (tx.type == 'expense') {
      expense += tx.amount;
    }
  }

  return MonthlySummary(
    totalIncome: income,
    totalExpense: expense,
    netBalance: income - expense,
  );
});

class TransactionActions {
  final TransactionRepository _repo;
  final Ref _ref;

  TransactionActions(this._repo, this._ref);

  Future<void> createTransaction({
    required int amount,
    required String type,
    required String category,
    String? note,
    required String date,
  }) async {
    final authState = _ref.read(authProvider);
    final userId = authState.userId ?? 'local_user';

    await _repo.createTransaction(
      userId: userId,
      amount: amount,
      type: type,
      category: category,
      note: note,
      date: date,
    );

    _ref.read(syncProvider.notifier).triggerSync();
  }

  Future<void> updateTransaction({
    required String id,
    required int amount,
    required String type,
    required String category,
    String? note,
    required String date,
  }) async {
    await _repo.updateTransaction(
      id: id,
      amount: amount,
      type: type,
      category: category,
      note: note,
      date: date,
    );

    _ref.read(syncProvider.notifier).triggerSync();
  }

  Future<void> deleteTransaction(String id) async {
    await _repo.deleteTransaction(id);
    _ref.read(syncProvider.notifier).triggerSync();
  }
}

final transactionActionsProvider = Provider<TransactionActions>((ref) {
  final repo = ref.watch(transactionRepositoryProvider);
  return TransactionActions(repo, ref);
});
