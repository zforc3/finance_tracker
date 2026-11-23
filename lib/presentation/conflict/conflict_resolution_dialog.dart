import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/local/database.dart';
import '../../../providers/sync_provider.dart';

class ConflictResolutionDialog extends ConsumerWidget {
  final TransactionEntry localTransaction;

  const ConflictResolutionDialog({
    super.key,
    required this.localTransaction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncNotifier = ref.read(syncProvider.notifier);
    final serverRecord = syncNotifier.getConflictServerRecord(localTransaction.id);

    final serverAmount = serverRecord?['amount'] as int? ?? localTransaction.amount;
    final serverType = serverRecord?['type'] as String? ?? localTransaction.type;
    final serverCategory = serverRecord?['category'] as String? ?? localTransaction.category;
    final serverNote = serverRecord?['note'] as String? ?? localTransaction.note;
    final serverDate = serverRecord?['date'] as String? ?? localTransaction.date;
    final serverVersion = serverRecord?['version'] as int? ?? (localTransaction.version + 1);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.syncConflict),
          SizedBox(width: 8),
          Text('Konflik Sinkronisasi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Data di server telah diperbarui oleh perangkat lain. Pilih versi mana yang ingin Anda simpan:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              // Versi Lokal Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Versi Lokal (Perangkat Ini)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'Draft Lokal',
                          style: TextStyle(fontSize: 11, color: AppColors.syncPending),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    _buildFieldRow('Nominal', CurrencyFormatter.format(localTransaction.amount)),
                    _buildFieldRow('Tipe', localTransaction.type == 'income' ? 'Pemasukan' : 'Pengeluaran'),
                    _buildFieldRow('Kategori', localTransaction.category),
                    _buildFieldRow('Tanggal', localTransaction.date),
                    _buildFieldRow('Catatan', localTransaction.note ?? '-'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Versi Server Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB), // Amber 50
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCD34D)), // Amber 300
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Versi Server (Terbaru di Cloud)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E)),
                        ),
                        Text(
                          'Versi $serverVersion',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFB45309), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    _buildFieldRow('Nominal', CurrencyFormatter.format(serverAmount)),
                    _buildFieldRow('Tipe', serverType == 'income' ? 'Pemasukan' : 'Pengeluaran'),
                    _buildFieldRow('Kategori', serverCategory),
                    _buildFieldRow('Tanggal', serverDate),
                    _buildFieldRow('Catatan', serverNote ?? '-'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.all(16),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(120, 44),
            foregroundColor: AppColors.textPrimary,
          ),
          onPressed: () async {
            Navigator.pop(context);
            await ref.read(syncProvider.notifier).resolveConflict(
                  localTransaction.id,
                  'use_server',
                );
          },
          child: const Text('Pakai Versi Server'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(120, 44),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            Navigator.pop(context);
            await ref.read(syncProvider.notifier).resolveConflict(
                  localTransaction.id,
                  'use_client',
                );
          },
          child: const Text('Pakai Versi Lokal'),
        ),
      ],
    );
  }

  Widget _buildFieldRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const Text(': ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
