import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SessionStore {
  final Directory _dir;

  SessionStore(this._dir);

  static Future<SessionStore> create() async {
    final dir = await getApplicationSupportDirectory();
    return SessionStore(dir);
  }

  File get _file => File('${_dir.path}/account_session.json');

  Future<String?> read() async {
    try {
      final file = _file;
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return data['token'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String token) async {
    await _dir.create(recursive: true);
    await _file.writeAsString(jsonEncode({'token': token}));
  }

  Future<void> clear() async {
    final file = _file;
    if (await file.exists()) {
      await file.delete();
    }
  }
}
