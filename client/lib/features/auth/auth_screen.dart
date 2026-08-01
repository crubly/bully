import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/storage/secure_store.dart';
import '../shell/app_shell.dart';
import '../../theme/discord_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final services = AppServices.of(context);
      final api = services.api;
      final result = _isRegister
          ? await api.register(_username.text.trim(), _password.text)
          : await api.login(_username.text.trim(), _password.text);
      await SecureStore.setAuthToken(api.baseUrl, result['token'] as String);
      await SecureStore.setUser(api.baseUrl, result['user_id'] as String, result['username'] as String);
      await services.ws.connect(result['token'] as String);
      unawaited(startBackgroundSyncForCurrentAccount(services));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AppShell()));
    } catch (e) {
      setState(() => _error = 'Ошибка: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isRegister ? 'Создать аккаунт' : 'С возвращением!',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: DiscordColors.textNormal),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Имя пользователя'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Пароль'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: DiscordColors.danger)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: Text(_loading ? '...' : (_isRegister ? 'Зарегистрироваться' : 'Войти')),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isRegister = !_isRegister),
                  child: Text(_isRegister ? 'У меня уже есть аккаунт' : 'Создать новый аккаунт'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
