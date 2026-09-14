import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/models/account_api_client.dart';
import 'package:flutter_hbb/models/session_store.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';

enum _GateStatus { checking, login, unlocked, locked }

class AccountGate extends StatefulWidget {
  final AccountApiClient? apiClient;
  final Future<SessionStore> Function()? storeFactory;

  const AccountGate({Key? key, this.apiClient, this.storeFactory})
      : super(key: key);

  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  late final AccountApiClient _api =
      widget.apiClient ?? AccountApiClient(baseUrl: kAccountApiBaseUrl);

  SessionStore? _store;
  _GateStatus _status = _GateStatus.checking;
  String? _message;
  bool _busy = false;
  int _consecutiveFailures = 0;
  Timer? _timer;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _store = await (widget.storeFactory ?? SessionStore.create)();
    final token = await _store!.read();
    if (token == null) {
      if (!mounted) return;
      setState(() => _status = _GateStatus.login);
      return;
    }
    final valid = await _api.validate(token);
    if (!mounted) return;
    if (valid) {
      _unlock();
    } else {
      await _store!.clear();
      if (!mounted) return;
      setState(() => _status = _GateStatus.login);
    }
  }

  void _unlock() {
    _timer?.cancel();
    _consecutiveFailures = 0;
    setState(() {
      _status = _GateStatus.unlocked;
      _message = null;
    });
    _timer =
        Timer.periodic(const Duration(seconds: 12), (_) => _revalidate());
  }

  Future<void> _revalidate() async {
    final token = await _store?.read();
    if (token == null) return;
    final valid = await _api.validate(token);
    if (!mounted) return;
    if (valid) {
      _consecutiveFailures = 0;
      return;
    }
    _consecutiveFailures++;
    if (_consecutiveFailures >= 3) {
      await _lock('Connexion au serveur perdue, réessaie plus tard');
    }
  }

  Future<void> _lock(String message) async {
    _timer?.cancel();
    await _store?.clear();
    await rustDeskWinManager.closeAllSubWindows();
    if (!mounted) return;
    setState(() {
      _status = _GateStatus.locked;
      _message = message;
    });
  }

  Future<void> _submitLogin() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final result =
        await _api.login(_usernameController.text, _passwordController.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isOk) {
      await _store!.write(result.token!);
      _passwordController.clear();
      if (!mounted) return;
      _unlock();
    } else {
      setState(() => _message = result.error);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _GateStatus.checking:
        return const Scaffold(
            body: Center(child: CircularProgressIndicator()));
      case _GateStatus.unlocked:
        return const DesktopTabPage();
      case _GateStatus.locked:
        return _buildLoginScreen(
          title: 'Accès verrouillé',
          submitLabel: 'Se reconnecter',
        );
      case _GateStatus.login:
        return _buildLoginScreen(
            title: 'Connexion', submitLabel: 'Se connecter');
    }
  }

  Widget _buildLoginScreen(
      {required String title, required String submitLabel}) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 16),
              if (_message != null && _message!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_message!,
                      style: const TextStyle(color: Colors.red)),
                ),
              TextField(
                controller: _usernameController,
                decoration:
                    const InputDecoration(labelText: "Nom d'utilisateur"),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _busy ? null : _submitLogin,
                child: Text(_busy ? '...' : submitLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
