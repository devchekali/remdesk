import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_hbb/desktop/pages/account_gate.dart';
import 'package:flutter_hbb/models/account_api_client.dart';
import 'package:flutter_hbb/models/session_store.dart';

// A lightweight stand-in for the real (FFI-backed) DesktopTabPage, which
// can't be constructed in a plain widget-test harness. AccountGate accepts
// `unlockedChild` precisely so tests can substitute this.
const _unlockedPlaceholder = Text('UNLOCKED_PLACEHOLDER');

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
        unlockedChild: _unlockedPlaceholder,
      ),
    ));
    await tester.pumpAndSettle();
  }

  // Unmounts AccountGate so its Timer.periodic (started on unlock) is
  // cancelled before test teardown - otherwise flutter_test fails the test
  // with "A Timer is still pending".
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('shows the login form when no session token exists',
      (tester) async {
    await pumpGate(tester, (req) async {
      throw Exception('should not be called with no stored token');
    });
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('successful login shows the unlocked content', (tester) async {
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
    expect(find.byWidget(_unlockedPlaceholder), findsOneWidget);
    expect(await SessionStore(tempDir).read(), 'tok-123');

    await unmount(tester);
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

  testWidgets('a stored but now-invalid (401) token falls back to the login '
      'form with no message', (tester) async {
    await SessionStore(tempDir).write('stale-token');
    await pumpGate(tester, (req) async {
      return http.Response(jsonEncode({'valid': false}), 401);
    });

    expect(find.text('Se connecter'), findsOneWidget);
    expect(await SessionStore(tempDir).read(), null);
  });

  testWidgets(
      'a stored token that cannot be validated because the server is '
      'unreachable at startup keeps the token and shows a message',
      (tester) async {
    await SessionStore(tempDir).write('good-token');
    await pumpGate(tester, (req) async {
      throw Exception('network down');
    });

    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Impossible de joindre le serveur, réessaie plus tard'),
        findsOneWidget);
    // Unlike the 401 case, the token is not thrown away: it might still be
    // good once the network is back.
    expect(await SessionStore(tempDir).read(), 'good-token');
  });

  testWidgets('a stored and still-valid token unlocks immediately',
      (tester) async {
    await SessionStore(tempDir).write('good-token');
    await pumpGate(tester, (req) async {
      return http.Response(jsonEncode({'valid': true}), 200);
    });

    expect(find.text('Se connecter'), findsNothing);
    expect(find.byWidget(_unlockedPlaceholder), findsOneWidget);

    await unmount(tester);
  });

  testWidgets(
      'a throwing store factory falls back to the login form instead of '
      'spinning forever', (tester) async {
    final apiClient = AccountApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        throw Exception('should not be called');
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: AccountGate(
        apiClient: apiClient,
        storeFactory: () async => throw Exception('AppData unavailable'),
        unlockedChild: _unlockedPlaceholder,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'an account disabled (401) mid-session locks immediately with the '
      'deactivation message', (tester) async {
    await SessionStore(tempDir).write('good-token');
    var validateCalls = 0;
    await pumpGate(tester, (req) async {
      validateCalls++;
      // 1st call: the startup check - still valid.
      if (validateCalls == 1) {
        return http.Response(jsonEncode({'valid': true}), 200);
      }
      // 2nd call: the first revalidation tick - account got disabled.
      return http.Response(jsonEncode({'valid': false}), 401);
    });

    expect(find.byWidget(_unlockedPlaceholder), findsOneWidget);

    // Fire the first 12s revalidation tick.
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();

    expect(find.byWidget(_unlockedPlaceholder), findsNothing);
    expect(
        find.text("Ton accès a été désactivé, contacte l'administrateur"),
        findsOneWidget);
    expect(await SessionStore(tempDir).read(), null);

    await unmount(tester);
  });

  testWidgets(
      '2 consecutive unreachable revalidations do not lock, but a 3rd does, '
      'with the connection-lost message', (tester) async {
    await SessionStore(tempDir).write('good-token');
    var validateCalls = 0;
    await pumpGate(tester, (req) async {
      validateCalls++;
      if (validateCalls == 1) {
        return http.Response(jsonEncode({'valid': true}), 200);
      }
      throw Exception('network down');
    });

    expect(find.byWidget(_unlockedPlaceholder), findsOneWidget);

    // Tick 1: unreachable (failure 1/3) - still unlocked.
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(find.byWidget(_unlockedPlaceholder), findsOneWidget);

    // Tick 2: unreachable (failure 2/3) - still unlocked.
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(find.byWidget(_unlockedPlaceholder), findsOneWidget);

    // Tick 3: unreachable (failure 3/3) - locks now.
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(find.byWidget(_unlockedPlaceholder), findsNothing);
    expect(find.text('Connexion au serveur perdue, réessaie plus tard'),
        findsOneWidget);

    await unmount(tester);
  });

  testWidgets(
      'a validate success in between two failures resets the failure '
      'counter, so 2 failures + 1 success + 2 more failures does not lock',
      (tester) async {
    await SessionStore(tempDir).write('good-token');
    var validateCalls = 0;
    await pumpGate(tester, (req) async {
      validateCalls++;
      // startup(1)=valid, tick1(2)=fail, tick2(3)=fail, tick3(4)=valid,
      // tick4(5)=fail, tick5(6)=fail. Never 3 in a row.
      if (validateCalls == 1 || validateCalls == 4) {
        return http.Response(jsonEncode({'valid': true}), 200);
      }
      throw Exception('network down');
    });

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(find.byWidget(_unlockedPlaceholder), findsOneWidget,
          reason: 'tick ${i + 1} should not have locked the app');
    }

    await unmount(tester);
  });

  testWidgets(
      'the session file disappearing while unlocked locks on the next tick '
      'instead of silently staying unlocked forever', (tester) async {
    final store = SessionStore(tempDir);
    await store.write('good-token');
    await pumpGate(tester, (req) async {
      return http.Response(jsonEncode({'valid': true}), 200);
    });

    expect(find.byWidget(_unlockedPlaceholder), findsOneWidget);

    // Simulate the session file vanishing / becoming unreadable.
    await store.clear();

    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();

    expect(find.byWidget(_unlockedPlaceholder), findsNothing);
    expect(
        find.text("Ton accès a été désactivé, contacte l'administrateur"),
        findsOneWidget);

    await unmount(tester);
  });
}
