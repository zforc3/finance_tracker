import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/network_provider.dart';
import '../../../providers/sync_provider.dart';

class NetworkBanner extends ConsumerWidget {
  const NetworkBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networkStatus = ref.watch(networkStatusProvider);
    final syncState = ref.watch(syncProvider);

    final isOffline = networkStatus.value == NetworkStatus.offline;
    final isSyncing = syncState.isSyncing;

    if (!isOffline && !isSyncing && syncState.errorMessage == null) {
      return const SizedBox.shrink();
    }

    if (isOffline) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFFF1F5F9), // Slate 100
        child: const Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Mode Offline: Transaksi tersimpan lokal dan akan disinkronkan saat terhubung.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    if (isSyncing) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFFEFF6FF), // Blue 50
        child: const Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
            ),
            SizedBox(width: 8),
            Text(
              'Menyinkronkan data dengan server...',
              style: TextStyle(fontSize: 12, color: Color(0xFF1D4ED8)),
            ),
          ],
        ),
      );
    }

    if (syncState.errorMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFFFEF2F2), // Red 50
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFDC2626)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sinkronisasi tertunda: Server belum dapat dijangkau.',
                style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
              ),
            ),
            TextButton(
              onPressed: () {
                ref.read(syncProvider.notifier).triggerSync();
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Coba Lagi', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
