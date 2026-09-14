import 'dart:convert';

import 'package:http/http.dart' as http;

/// Outcome of validating a stored session token against the server.
///
/// Kept distinct from a plain bool so callers can tell an explicitly
/// rejected/disabled account (`invalid`) apart from a server that
/// could not be reached at all (`unreachable`) — the two call for very
/// different UX (immediate lock vs. a few retries before locking).
enum AccountValidationResult { valid, invalid, unreachable }

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
      if (res.statusCode == 401) {
        return AccountLoginResult.error(
          "Nom d'utilisateur ou mot de passe incorrect",
        );
      }
      // Any other non-200/429 status (500/502/503 during a restart or deploy,
      // etc.) is a server-side error, not a wrong-credentials problem.
      return AccountLoginResult.error(
        'Le serveur a répondu une erreur, réessaie plus tard',
      );
    } catch (_) {
      return AccountLoginResult.error(
        'Impossible de joindre le serveur, réessaie plus tard',
      );
    }
  }

  Future<AccountValidationResult> validate(String token) async {
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl/api/session/validate'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      // The server contract only defines 200 (valid) and 401 (invalid).
      // Anything else (500/502/503 during a restart or deploy, etc.) is
      // not proof the account was deactivated - treat it the same as an
      // unreachable server so it goes through the 3-strike counter
      // instead of locking (and wiping the session) immediately.
      if (res.statusCode == 200) return AccountValidationResult.valid;
      if (res.statusCode == 401) return AccountValidationResult.invalid;
      return AccountValidationResult.unreachable;
    } catch (_) {
      return AccountValidationResult.unreachable;
    }
  }
}
