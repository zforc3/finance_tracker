import '../../core/network/api_client.dart';
import '../../core/network/token_storage.dart';

class AuthRepository {
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  AuthRepository(this._apiClient, this._tokenStorage);

  Future<bool> isAuthenticated() async {
    final token = await _tokenStorage.getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<String?> getUserId() async {
    return await _tokenStorage.getUserId();
  }

  Future<String?> getUserEmail() async {
    return await _tokenStorage.getUserEmail();
  }

  Future<void> register(String email, String password) async {
    final res = await _apiClient.register(email, password);
    final userId = res['id'] as String?;
    await login(email, password, userId: userId);
  }

  Future<void> login(String email, String password, {String? userId}) async {
    final res = await _apiClient.login(email, password);
    final accessToken = res['access_token'] as String;
    final refreshToken = res['refresh_token'] as String;

    String? finalUserId = userId;
    if (finalUserId == null) {
      try {
        await _tokenStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
          userEmail: email,
        );
        final me = await _apiClient.getMe();
        finalUserId = me['id'] as String?;
      } catch (_) {}
    }

    await _tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userId: finalUserId,
      userEmail: email,
    );
  }

  Future<void> logout() async {
    await _tokenStorage.clear();
  }
}
