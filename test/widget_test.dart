import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/presentation/home/widgets/balance_card.dart';
import 'package:finance_tracker/presentation/home/widgets/month_selector.dart';
import 'package:finance_tracker/presentation/home/widgets/network_banner.dart';
import 'package:finance_tracker/presentation/transaction/transaction_form_screen.dart';
import 'package:finance_tracker/providers/transaction_provider.dart';

void main() {
  Widget createTestWidget(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('id', 'ID')],
        home: Scaffold(body: child),
      ),
    );
  }

  group('Widget UI Verification', () {
    testWidgets('BalanceCard renders Net Balance, Income, and Expense correctly', (tester) async {
      const summary = MonthlySummary(
        totalIncome: 10000000,
        totalExpense: 3500000,
        netBalance: 6500000,
      );

      await tester.pumpWidget(createTestWidget(const BalanceCard(summary: summary)));
      await tester.pumpAndSettle();

      expect(find.text('Saldo Bersih'), findsOneWidget);
      expect(find.text('Pemasukan'), findsOneWidget);
      expect(find.text('Pengeluaran'), findsOneWidget);
      expect(find.textContaining('6.500.000'), findsOneWidget);
      expect(find.textContaining('10.000.000'), findsOneWidget);
      expect(find.textContaining('3.500.000'), findsOneWidget);
    });

    testWidgets('MonthSelector responds to previous and next month buttons', (tester) async {
      await tester.pumpWidget(createTestWidget(const MonthSelector()));
      await tester.pumpAndSettle();

      expect(find.byType(IconButton), findsNWidgets(2));
      // Tap next month
      await tester.tap(find.byTooltip('Bulan Berikutnya'));
      await tester.pumpAndSettle();
    });

    testWidgets('NetworkBanner renders cleanly without error in default online state', (tester) async {
      await tester.pumpWidget(createTestWidget(const NetworkBanner()));
      await tester.pumpAndSettle();
      // Should not throw or crash
      expect(find.byType(NetworkBanner), findsOneWidget);
    });

    testWidgets('TransactionFormScreen renders fields and toggles type', (tester) async {
      await tester.pumpWidget(createTestWidget(const TransactionFormScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Catat Transaksi'), findsOneWidget);
      expect(find.text('Pengeluaran'), findsOneWidget);
      expect(find.text('Pemasukan'), findsOneWidget);
      expect(find.text('Simpan Transaksi'), findsOneWidget);

      // Tap Pemasukan toggle
      await tester.tap(find.text('Pemasukan'));
      await tester.pumpAndSettle();

      // Income categories should now be visible
      expect(find.text('Gaji'), findsOneWidget);
    });
  });
}
