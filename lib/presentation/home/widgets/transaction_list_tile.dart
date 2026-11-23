import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/local/database.dart';
import '../../../providers/transaction_provider.dart';

class TransactionListTile extends ConsumerWidget {
  final TransactionEntry transaction;
  final VoidCallback onTap;
  final VoidCallback onResolveConflict;

  const TransactionListTile({
    super.key,
    required this.transaction,
    required this.onTap,
    required this.onResolveConflict,
  });

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'makanan':
      case 'kuliner':
        return Icons.restaurant_rounded;
      case 'transportasi':
      case 'bensin':
        return Icons.directions_car_filled_rounded;
      case 'belanja':
        return Icons.shopping_bag_rounded;
      case 'hiburan':
        return Icons.movie_rounded;
      case 'gaji':
      case 'pendapatan':
        return Icons.payments_rounded;
      case 'investasi':
        return Icons.trending_up_rounded;
      case 'tagihan':
      case 'listrik':
        return Icons.receipt_long_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Widget _buildSyncBadge() {
    switch (transaction.syncStatus) {
      case 'conflict':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.syncConflictBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.syncConflict, width: 0.8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 12, color: AppColors.syncConflict),
              SizedBox(width: 4),
              Text(
                'Konflik',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.syncConflict,
                ),
              ),
            ],
          ),
        );
      case 'pending':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.syncPendingBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.access_time_rounded, size: 11, color: AppColors.syncPending),
              SizedBox(width: 4),
              Text(
                'Lokal',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.syncPending,
                ),
              ),
            ],
          ),
        );
      case 'synced':
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = transaction.type == 'income';
    final isConflict = transaction.syncStatus == 'conflict';

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: isConflict ? onResolveConflict : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: const BoxConstraints(minHeight: 56),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isIncome ? AppColors.incomeLight : AppColors.expenseLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getCategoryIcon(transaction.category),
                  color: isIncome ? AppColors.income : AppColors.expense,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            transaction.category,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildSyncBadge(),
                      ],
                    ),
                    if (transaction.note != null && transaction.note!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        transaction.note!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isIncome ? '+' : '-'} ${CurrencyFormatter.format(transaction.amount)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isIncome ? AppColors.income : AppColors.expense,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppColors.textSecondary),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onSelected: (value) {
                  if (value == 'edit') {
                    onTap();
                  } else if (value == 'delete') {
                    _showDeleteConfirm(context, ref);
                  } else if (value == 'resolve') {
                    onResolveConflict();
                  }
                },
                itemBuilder: (context) => [
                  if (isConflict)
                    const PopupMenuItem(
                      value: 'resolve',
                      child: Row(
                        children: [
                          Icon(Icons.rule_rounded, size: 18, color: AppColors.syncConflict),
                          SizedBox(width: 8),
                          Text('Selesaikan Konflik'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.expense),
                        SizedBox(width: 8),
                        Text('Hapus', style: TextStyle(color: AppColors.expense)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Transaksi?'),
        content: const Text(
          'Transaksi akan dihapus secara lokal dan perubahannya akan disinkronkan ke server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.expense,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(transactionActionsProvider).deleteTransaction(transaction.id);
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}
