import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../providers/transaction_provider.dart';

class MonthSelector extends ConsumerWidget {
  const MonthSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(selectedMonthProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppColors.textPrimary,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: 'Bulan Sebelumnya',
            onPressed: () {
              ref.read(selectedMonthProvider.notifier).previousMonth();
            },
          ),
          Text(
            DateFormatter.formatMonthYear(filter.year, filter.month),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            color: AppColors.textPrimary,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: 'Bulan Berikutnya',
            onPressed: () {
              ref.read(selectedMonthProvider.notifier).nextMonth();
            },
          ),
        ],
      ),
    );
  }
}
