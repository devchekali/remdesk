import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_hbb/models/account_api_client.dart';

void main() {
  test('login() returns a token on success', () async {
    final client = AccountApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        expect(req.url.path, '/api/login');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['username'], 'alice');
        expect(body['password'], 'secret');
        return http.Response(jsonEncode({'token': 'tok-123'}), 200);
      }),
    );

    final result = await client.login('alice', 'secret');
    expect(result.isOk, true);
    expect(result.token, 'tok-123');
  });

  test('login() reports a generic error on wrong credentials', () async {
    final client = AccountApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        return http.Response(jsonEncode({'error': 'nope'}), 401);
      }),
    );

    final result = await client.login('alice', 'wrong');
    expect(result.isOk, false);
    expect(result.error, "Nom d'utilisateur ou mot de passe incorrect");
    expect(result.tooManyAttempts, false);
  });

  test('login() reports rate limiting on 429', () async {
    final client = AccountApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        return http.Response(jsonEncode({'error': 'trop'}), 429);
      }),
    );

    final result = await client.login('alice', 'secret');
    expect(result.isOk, false);
    expect(result.tooManyAttempts, true);
  });

  test(
      'login() reports a server error (not wrong credentials) on a non-401/429 '
      'status, e.g. a 500 during a server restart', () async {
    final client = AccountApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        return http.Response('Internal Server Error', 500);
      }),
    );

    final result = await client.login('alice', 'secret');
    expect(result.isOk, false);
    expect(result.error, 'Le serveur a répondu une erreur, réessaie plus tard');
    expect(result.tooManyAttempts, false);
  });

  test('login() reports unreachable server on network failure', () async {
    final client = AccountApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        throw Exception('network down');
      }),
    );

    final result = await client.login('alice', 'secret');
    expect(result.isOk, false);
    expect(result.error, 'Impossible de joindre le serveur, réessaie plus tard');
  });

  test('validate() returns valid for a 200 response', () async {
    final client = AccountApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        expect(req.url.path, '/api/session/validate');
        expect(req.headers['Authorization'], 'Bearer tok-123');
        return http.Response(jsonEncode({'valid': true}), 200);
      }),
    );

    expect(await client.validate('tok-123'), AccountValidationResult.valid);
  });

  test('validate() returns invalid for a 401 response', () async {
    final client = AccountApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        return http.Response(jsonEncode({'valid': false}), 401);
      }),
    );

    expect(await client.validate('tok-123'), AccountValidationResult.invalid);
  });

  test('validate() returns unreachable when the server cannot be reached',
      () async {
    final client = AccountApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        throw Exception('network down');
      }),
    );

    expect(
        await client.validate('tok-123'), AccountValidationResult.unreachable);
  });

  test(
      'validate() returns unreachable (not invalid) for a non-401 error '
      'status, e.g. a 503 during a server restart', () async {
    final client = AccountApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        return http.Response('Service Unavailable', 503);
      }),
    );

    expect(
        await client.validate('tok-123'), AccountValidationResult.unreachable);
  });
}
