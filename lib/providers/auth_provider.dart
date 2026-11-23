import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_provider.dart';

class AuthState {
  final bool isAuthenticated;
  final String? userId;
  final String? userEmail;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({
    this.isAuthenticated = false,
    this.userId,
    this.userEmail,
    this.isLoading = false,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    String? userId,
    String? userEmail,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userId: userId ?? this.userId,
      userEmail: userEmail ?? this.userEmail,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(() => checkStatus());
    return const AuthState(isLoading: true);
  }

  Future<void> checkStatus() async {
    final repo = ref.read(authRepositoryProvider);
    final isAuth = await repo.isAuthenticated();
    if (isAuth) {
      final userId = await repo.getUserId();
      final userEmail = await repo.getUserEmail();
      state = AuthState(
        isAuthenticated: true,
        userId: userId,
        userEmail: userEmail,
        isLoading: false,
      );
    } else {
      state = const AuthState(isAuthenticated: false, isLoading: false);
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.login(email, password);
      final userId = await repo.getUserId();
      state = AuthState(
        isAuthenticated: true,
        userId: userId,
        userEmail: email,
        isLoading: false,
      );
      return true;
    } on DioException catch (e) {
      debugPrint('Auth login DioException: [${e.type}] ${e.message} - ${e.response?.data}');
      String msg = 'Gagal masuk: Periksa koneksi atau kredensial Anda.';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        msg = 'Tidak dapat menghubungi server backend (Connection Error). Pastikan backend aktif dan adb reverse berjalan.';
      } else if (e.response?.statusCode == 401) {
        msg = 'Email atau kata sandi salah.';
      } else if (e.response?.data is Map && (e.response!.data as Map).containsKey('detail')) {
        msg = (e.response!.data as Map)['detail'].toString();
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: msg,
      );
      return false;
    } catch (e) {
      debugPrint('Auth login error: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Terjadi kesalahan sistem: $e',
      );
      return false;
    }
  }

  Future<bool> register(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.register(email, password);
      final userId = await repo.getUserId();
      state = AuthState(
        isAuthenticated: true,
        userId: userId,
        userEmail: email,
        isLoading: false,
      );
      return true;
    } on DioException catch (e) {
      debugPrint('Auth register DioException: [${e.type}] ${e.message} - ${e.response?.data}');
      String msg = 'Gagal mendaftar: Email mungkin sudah digunakan.';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        msg = 'Tidak dapat menghubungi server backend (Connection Error).';
      } else if (e.response?.data is Map && (e.response!.data as Map).containsKey('detail')) {
        msg = (e.response!.data as Map)['detail'].toString();
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: msg,
      );
      return false;
    } catch (e) {
      debugPrint('Auth register error: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Terjadi kesalahan sistem: $e',
      );
      return false;
    }
  }

  Future<void> logout() async {
    final repo = ref.read(authRepositoryProvider);
    await repo.logout();
    state = const AuthState(isAuthenticated: false);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
