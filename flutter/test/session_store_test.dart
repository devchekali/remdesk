import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/session_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_store_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('read() returns null when no token was ever written', () async {
    final store = SessionStore(tempDir);
    expect(await store.read(), null);
  });

  test('write() then read() round-trips the token', () async {
    final store = SessionStore(tempDir);
    await store.write('tok-123');
    expect(await store.read(), 'tok-123');
  });

  test('write() then write() overwrites the previous token', () async {
    final store = SessionStore(tempDir);
    await store.write('tok-1');
    await store.write('tok-2');
    expect(await store.read(), 'tok-2');
  });

  test('clear() removes a previously written token', () async {
    final store = SessionStore(tempDir);
    await store.write('tok-123');
    await store.clear();
    expect(await store.read(), null);
  });

  test('clear() is a no-op when nothing was ever written', () async {
    final store = SessionStore(tempDir);
    await store.clear();
    expect(await store.read(), null);
  });

  test('read() returns null for a corrupted session file', () async {
    final store = SessionStore(tempDir);
    await File('${tempDir.path}/account_session.json')
        .writeAsString('not json');
    expect(await store.read(), null);
  });
}
