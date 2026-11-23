import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiEndpoints {
  static String get defaultBaseUrl {
    const customUrl = String.fromEnvironment('API_URL');
    if (customUrl.isNotEmpty) {
      return customUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:8000/api/v1';
    }
    if (Platform.isAndroid) {
      // 127.0.0.1 is used with 'adb reverse tcp:8000 tcp:8000' for physical devices over USB.
      // Can be overridden via --dart-define=API_URL=http://<IP>:8000/api/v1
      return 'http://127.0.0.1:8000/api/v1';
    }
    return 'http://localhost:8000/api/v1';
  }

  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String me = '/auth/me';

  static const String syncPush = '/sync/push';
  static const String syncPull = '/sync/pull';
  static const String resolveConflict = '/sync/resolve-conflict';
}
