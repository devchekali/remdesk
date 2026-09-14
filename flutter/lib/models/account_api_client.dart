import 'dart:convert';

import 'package:http/http.dart' as http;

class AccountLoginResult {
  final String? token;
  final String? error;
  final bool tooManyAttempts;

  AccountLoginResult.ok(this.token)
      : error = null,
        tooManyAttempts = false;

  AccountLoginResult.error(this.error, {this.tooManyAttempts = false})
      : token = null;

  bool get isOk => token != null;
}

class AccountApiClient {
  final String baseUrl;
  final http.Client _client;

  AccountApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  Future<AccountLoginResult> login(String username, String password) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$baseUrl/api/login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return AccountLoginResult.ok(body['token'] as String);
      }
      if (res.statusCode == 429) {
        return AccountLoginResult.error(
          'Trop de tentatives, réessaie plus tard',
          tooManyAttempts: true,
        );
      }
      return AccountLoginResult.error(
        "Nom d'utilisateur ou mot de passe incorrect",
      );
    } catch (_) {
      return AccountLoginResult.error(
        'Impossible de joindre le serveur, réessaie plus tard',
      );
    }
  }

  Future<bool> validate(String token) async {
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl/api/session/validate'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
