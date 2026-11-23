import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/sync/sync_engine.dart';
import 'database_provider.dart';
import 'network_provider.dart';

class SyncStateData {
  final bool isSyncing;
  final SyncResult? lastResult;
  final DateTime? lastSyncTime;
  final String? errorMessage;

  const SyncStateData({
    this.isSyncing = false,
    this.lastResult,
    this.lastSyncTime,
    this.errorMessage,
  });

  SyncStateData copyWith({
    bool? isSyncing,
    SyncResult? lastResult,
    DateTime? lastSyncTime,
    String? errorMessage,
  }) {
    return SyncStateData(
      isSyncing: isSyncing ?? this.isSyncing,
      lastResult: lastResult ?? this.lastResult,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      errorMessage: errorMessage,
    );
  }
}

class SyncNotifier extends Notifier<SyncStateData> {
  @override
  SyncStateData build() {
    // Listen to network changes: auto sync when back online
    ref.listen<AsyncValue<NetworkStatus>>(networkStatusProvider, (previous, next) {
      if (next.value == NetworkStatus.online) {
        triggerSync();
      }
    });

    return const SyncStateData();
  }

  Future<void> triggerSync() async {
    if (state.isSyncing) return;
    state = state.copyWith(isSyncing: true, errorMessage: null);

    final engine = ref.read(syncEngineProvider);
    final result = await engine.sync();
    state = state.copyWith(
      isSyncing: false,
      lastResult: result,
      lastSyncTime: DateTime.now(),
      errorMessage: result.error,
    );
  }

  Future<void> resolveConflict(String transactionId, String choice) async {
    final engine = ref.read(syncEngineProvider);
    await engine.resolveConflict(
      transactionId: transactionId,
      choice: choice,
    );
    await triggerSync();
  }

  Map<String, dynamic>? getConflictServerRecord(String txId) {
    final engine = ref.read(syncEngineProvider);
    return engine.getConflictServerRecord(txId);
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncStateData>(SyncNotifier.new);
