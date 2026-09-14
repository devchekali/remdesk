import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/models/account_api_client.dart';
import 'package:flutter_hbb/models/session_store.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';

enum _GateStatus { checking, login, unlocked, locked }

const String _kDeactivatedMessage =
    "Ton accès a été désactivé, contacte l'administrateur";
const String _kConnectionLostMessage =
    'Connexion au serveur perdue, réessaie plus tard';
const String _kUnreachableAtStartupMessage =
    'Impossible de joindre le serveur, réessaie plus tard';

class AccountGate extends StatefulWidget {
  final AccountApiClient? apiClient;
  final Future<SessionStore> Function()? storeFactory;

  /// What to render once unlocked. Defaults to the real [DesktopTabPage];
  /// overridable so widget tests can substitute a lightweight placeholder
  /// instead of standing up the whole FFI-backed desktop UI.
  final Widget? unlockedChild;

  const AccountGate(
      {Key? key, this.apiClient, this.storeFactory, this.unlockedChild})
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

  // Guards against overlapping revalidation ticks (a slow HTTP call still
  // in flight when the next 12s tick fires).
  bool _revalidating = false;

  // Bumped on every unlock/lock transition. A revalidation call captures
  // the epoch it started under; if the epoch has moved on by the time an
  // `await` resolves (e.g. a lock happened, or the user logged back in),
  // the call's result is stale and discarded instead of mutating state
  // that belongs to a different session.
  int _epoch = 0;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _store = await (widget.storeFactory ?? SessionStore.create)();
      final token = await _store!.read();
      if (token == null) {
        if (!mounted) return;
        setState(() => _status = _GateStatus.login);
        return;
      }
      final result = await _api.validate(token);
      if (!mounted) return;
      switch (result) {
        case AccountValidationResult.valid:
          _unlock();
          break;
        case AccountValidationResult.invalid:
          await _store!.clear();
          if (!mounted) return;
          setState(() {
            _status = _GateStatus.login;
            _message = null;
          });
          break;
        case AccountValidationResult.unreachable:
          // Keep the token: the server being unreachable right now says
          // nothing about whether the session is actually still good.
          setState(() {
            _status = _GateStatus.login;
            _message = _kUnreachableAtStartupMessage;
          });
          break;
      }
    } catch (_) {
      // A throwing store factory (e.g. inaccessible AppData) must not
      // strand the user on an infinite spinner.
      if (!mounted) return;
      setState(() {
        _status = _GateStatus.login;
        _message = null;
      });
    }
  }

  void _unlock() {
    _timer?.cancel();
    _consecutiveFailures = 0;
    _epoch++;
    setState(() {
      _status = _GateStatus.unlocked;
      _message = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => _revalidate());
  }

  Future<void> _revalidate() async {
    if (_revalidating) return;
    _revalidating = true;
    final epoch = _epoch;
    try {
      final token = await _store?.read();
      if (!mounted || epoch != _epoch) return;
      if (token == null) {
        // No proof of a valid session any more (file missing/corrupted) -
        // do not stay unlocked on nothing.
        await _lock(_kDeactivatedMessage);
        return;
      }
      final result = await _api.validate(token);
      if (!mounted || epoch != _epoch) return;
      switch (result) {
        case AccountValidationResult.valid:
          _consecutiveFailures = 0;
          break;
        case AccountValidationResult.invalid:
          await _lock(_kDeactivatedMessage);
          break;
        case AccountValidationResult.unreachable:
          _consecutiveFailures++;
          if (_consecutiveFailures >= 3) {
            await _lock(_kConnectionLostMessage);
          }
          break;
      }
    } finally {
      _revalidating = false;
    }
  }

  Future<void> _lock(String message) async {
    _timer?.cancel();
    _epoch++;
    _consecutiveFailures = 0;
    // Take effect immediately, before any cleanup that might throw -
    // a failure clearing the store or closing sub-windows must not leave
    // the app unlocked and never re-checked again.
    if (mounted) {
      setState(() {
        _status = _GateStatus.locked;
        _message = message;
      });
    } else {
      _status = _GateStatus.locked;
      _message = message;
    }
    try {
      await _store?.clear();
    } catch (_) {}
    try {
      await rustDeskWinManager.closeAllSubWindows();
    } catch (_) {}
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
        return widget.unlockedChild ?? const DesktopTabPage();
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
