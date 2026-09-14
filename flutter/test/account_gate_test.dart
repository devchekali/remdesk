import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_hbb/desktop/pages/account_gate.dart';
import 'package:flutter_hbb/models/account_api_client.dart';
import 'package:flutter_hbb/models/session_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('account_gate_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> pumpGate(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final apiClient = AccountApiClient(
      baseUrl: 'https://example.test',
      client: MockClient(handler),
    );
    await tester.pumpWidget(MaterialApp(
      home: AccountGate(
        apiClient: apiClient,
        storeFactory: () async => SessionStore(tempDir),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the login form when no session token exists',
      (tester) async {
    await pumpGate(tester, (req) async {
      throw Exception('should not be called with no stored token');
    });
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('successful login shows the unlocked content',
      (tester) async {
    await pumpGate(tester, (req) async {
      if (req.url.path == '/api/login') {
        return http.Response(jsonEncode({'token': 'tok-123'}), 200);
      }
      return http.Response('', 404);
    });

    await tester.enterText(
        find.widgetWithText(TextField, "Nom d'utilisateur"), 'alice');
    await tester.enterText(
        find.widgetWithText(TextField, 'Mot de passe'), 'secret');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Se connecter'), findsNothing);
    expect(await SessionStore(tempDir).read(), 'tok-123');
  });

  testWidgets('wrong credentials show an error and stay on the login form',
      (tester) async {
    await pumpGate(tester, (req) async {
      return http.Response(jsonEncode({'error': 'nope'}), 401);
    });

    await tester.enterText(
        find.widgetWithText(TextField, "Nom d'utilisateur"), 'alice');
    await tester.enterText(
        find.widgetWithText(TextField, 'Mot de passe'), 'wrong');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text("Nom d'utilisateur ou mot de passe incorrect"),
        findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('a stored but now-invalid token falls back to the login form',
      (tester) async {
    await SessionStore(tempDir).write('stale-token');
    await pumpGate(tester, (req) async {
      return http.Response(jsonEncode({'valid': false}), 401);
    });

    expect(find.text('Se connecter'), findsOneWidget);
    expect(await SessionStore(tempDir).read(), null);
  });

  testWidgets('a stored and still-valid token unlocks immediately',
      (tester) async {
    await SessionStore(tempDir).write('good-token');
    await pumpGate(tester, (req) async {
      return http.Response(jsonEncode({'valid': true}), 200);
    });

    expect(find.text('Se connecter'), findsNothing);
  });
}
