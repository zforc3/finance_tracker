import 'package:dio/dio.dart';
import '../constants/api_endpoints.dart';
import 'token_storage.dart';

class ApiClient {
  late final Dio _dio;
  final TokenStorage _tokenStorage;
  final String _baseUrl;

  ApiClient({
    TokenStorage? tokenStorage,
    String? baseUrl,
  })  : _tokenStorage = tokenStorage ?? TokenStorage(),
        _baseUrl = baseUrl ?? ApiEndpoints.defaultBaseUrl {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Exclude auth routes from bearer header
          if (!options.path.contains('/auth/login') &&
              !options.path.contains('/auth/register') &&
              !options.path.contains('/auth/refresh')) {
            final token = await _tokenStorage.getAccessToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401 &&
              !error.requestOptions.path.contains('/auth/')) {
            final refreshToken = await _tokenStorage.getRefreshToken();
            if (refreshToken != null && refreshToken.isNotEmpty) {
              try {
                // Call refresh with a separate clean Dio instance to avoid recursive interceptor calls
                final refreshDio = Dio(BaseOptions(baseUrl: _baseUrl));
                final refreshResp = await refreshDio.post(
                  ApiEndpoints.refresh,
                  data: {'refresh_token': refreshToken},
                );
                if (refreshResp.statusCode == 200) {
                  final newAccessToken = refreshResp.data['access_token'] as String;
                  final newRefreshToken = refreshResp.data['refresh_token'] as String?;
                  await _tokenStorage.saveTokens(
                    accessToken: newAccessToken,
                    refreshToken: newRefreshToken ?? refreshToken,
                  );

                  // Retry the original request
                  final retryOptions = error.requestOptions;
                  retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
                  final retryResp = await _dio.fetch(retryOptions);
                  return handler.resolve(retryResp);
                }
              } catch (_) {
                await _tokenStorage.clear();
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  // -------------------------------------------------------------
  // Auth API
  // -------------------------------------------------------------

  Future<Map<String, dynamic>> register(String email, String password) async {
    final response = await _dio.post(
      ApiEndpoints.register,
      data: {'email': email, 'password': password},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _dio.post(
      ApiEndpoints.login,
      data: {'email': email, 'password': password},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await _dio.get(ApiEndpoints.me);
    return response.data as Map<String, dynamic>;
  }

  // -------------------------------------------------------------
  // Sync API
  // -------------------------------------------------------------

  Future<Map<String, dynamic>> pushBatch({
    required String batchId,
    required List<Map<String, dynamic>> items,
  }) async {
    final response = await _dio.post(
      ApiEndpoints.syncPush,
      data: {
        'batch_id': batchId,
        'items': items,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> pull({
    String? cursor,
    int limit = 100,
  }) async {
    final queryParams = <String, dynamic>{'limit': limit};
    if (cursor != null && cursor.isNotEmpty) {
      queryParams['cursor'] = cursor;
    }
    final response = await _dio.get(
      ApiEndpoints.syncPull,
      queryParameters: queryParams,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resolveConflict({
    required String id,
    required String resolution,
    required int targetVersion,
    Map<String, dynamic>? clientData,
  }) async {
    final payload = <String, dynamic>{
      'id': id,
      'resolution': resolution,
      'target_version': targetVersion,
    };
    if (clientData != null) {
      payload['client_data'] = clientData;
    }
    final response = await _dio.post(
      ApiEndpoints.resolveConflict,
      data: payload,
    );
    return response.data as Map<String, dynamic>;
  }
}
