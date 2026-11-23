import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../data/local/database.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/transaction_provider.dart';
import '../conflict/conflict_resolution_dialog.dart';
import '../transaction/transaction_form_screen.dart';
import 'widgets/balance_card.dart';
import 'widgets/month_selector.dart';
import 'widgets/network_banner.dart';
import 'widgets/transaction_list_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final summary = ref.watch(monthlySummaryProvider);
    final asyncTxList = ref.watch(monthlyTransactionsProvider);
    final syncState = ref.watch(syncProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Finance Tracker',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          IconButton(
            tooltip: 'Sinkronisasi Manual',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: syncState.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                : const Icon(Icons.sync_rounded),
            onPressed: syncState.isSyncing
                ? null
                : () async {
                    await ref.read(syncProvider.notifier).triggerSync();
                    if (context.mounted) {
                      final res = ref.read(syncProvider).lastResult;
                      if (res != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Sinkronisasi selesai: ${res.pushedCount} dikirim, ${res.pulledCount} ditarik, ${res.conflictsCount} konflik.',
                            ),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_outlined, size: 24),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: 'Akun Pengguna',
            onSelected: (val) {
              if (val == 'logout') {
                ref.read(authProvider.notifier).logout();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  authState.userEmail ?? 'Pengguna',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: AppColors.expense),
                    SizedBox(width: 8),
                    Text('Keluar', style: TextStyle(color: AppColors.expense)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const NetworkBanner(),
            BalanceCard(summary: summary),
            const MonthSelector(),
            Expanded(
              child: asyncTxList.when(
                data: (transactions) {
                  if (transactions.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: const Icon(
                              Icons.receipt_long_outlined,
                              size: 40,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Belum ada transaksi di bulan ini',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tekan tombol Catat Transaksi untuk menambah catatan.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Group transactions by date
                  final grouped = <String, List<TransactionEntry>>{};
                  for (final tx in transactions) {
                    grouped.putIfAbsent(tx.date, () => []).add(tx);
                  }

                  final sortedDates = grouped.keys.toList()
                    ..sort((a, b) => b.compareTo(a));

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: sortedDates.length,
                    itemBuilder: (context, index) {
                      final date = sortedDates[index];
                      final dayTransactions = grouped[date]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: const Color(0xFFF1F5F9),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  DateFormatter.formatReadable(date),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                Text(
                                  '${dayTransactions.length} transaksi',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...dayTransactions.map((tx) => TransactionListTile(
                                transaction: tx,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (ctx) => TransactionFormScreen(transaction: tx),
                                    ),
                                  );
                                },
                                onResolveConflict: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => ConflictResolutionDialog(localTransaction: tx),
                                  );
                                },
                              )),
                        ],
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (err, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.expense, size: 36),
                      const SizedBox(height: 8),
                      Text('Terjadi kesalahan: $err'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Catat Transaksi',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => const TransactionFormScreen(),
            ),
          );
        },
      ),
    );
  }
}
