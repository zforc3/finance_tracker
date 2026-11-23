import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NetworkStatus { online, offline }

final networkStatusProvider = StreamProvider<NetworkStatus>((ref) async* {
  final connectivity = Connectivity();
  final initial = await connectivity.checkConnectivity();
  final isInitialOnline = initial.any((r) => r != ConnectivityResult.none);
  yield isInitialOnline ? NetworkStatus.online : NetworkStatus.offline;

  await for (final results in connectivity.onConnectivityChanged) {
    final isOnline = results.any((r) => r != ConnectivityResult.none);
    yield isOnline ? NetworkStatus.online : NetworkStatus.offline;
  }
});
