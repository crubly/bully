import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../theme/bully_theme.dart';

class _SessionInfo {
  final String id;
  final String deviceName;
  final String platform;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final bool current;

  _SessionInfo({
    required this.id,
    required this.deviceName,
    required this.platform,
    required this.createdAt,
    required this.lastSeenAt,
    required this.current,
  });

  factory _SessionInfo.fromJson(Map<String, dynamic> json) => _SessionInfo(
        id: json['id'] as String,
        deviceName: json['device_name'] as String,
        platform: json['platform'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        lastSeenAt: DateTime.parse(json['last_seen_at'] as String),
        current: json['current'] as bool,
      );
}

class SessionsScreen extends StatefulWidget {
  final bool embedded;
  const SessionsScreen({super.key, this.embedded = false});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<_SessionInfo> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final services = AppServices.of(context);
    final raw = await services.api.listSessions();
    setState(() {
      _sessions = raw.map((s) => _SessionInfo.fromJson(s as Map<String, dynamic>)).toList();
      _loading = false;
    });
  }

  String _describeError(Object e) {
    if (e is DioException && e.response?.statusCode == 403) {
      final code = e.response?.data is Map ? (e.response!.data as Map)['error'] : null;
      if (code == 'session_too_new') {
        return 'Эта сессия младше 24 часов — выход других устройств станет доступен позже (защита от мгновенного захвата аккаунта).';
      }
    }
    return 'Не удалось выполнить действие.';
  }

  Future<void> _revoke(String sessionId) async {
    final services = AppServices.of(context);
    setState(() => _error = null);
    try {
      await services.api.revokeSession(sessionId);
      await _load();
    } catch (e) {
      setState(() => _error = _describeError(e));
    }
  }

  Future<void> _revokeAll() async {
    final services = AppServices.of(context);
    setState(() => _error = null);
    try {
      await services.api.revokeAllOtherSessions();
      await _load();
    } catch (e) {
      setState(() => _error = _describeError(e));
    }
  }

  Widget _body(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (_error != null)
                Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: BullyColors.danger))),
              Expanded(
                child: ListView(
                  children: _sessions
                      .map((s) => ListTile(
                            leading: Icon(_iconFor(s.platform), color: BullyColors.blurple),
                            title: Text(
                              '${s.deviceName}${s.current ? ' (это устройство)' : ''}',
                              style: TextStyle(color: BullyPalette.of(context).textNormal),
                            ),
                            subtitle: Text(
                              'Платформа: ${s.platform} · последняя активность: ${_formatAgo(s.lastSeenAt)}',
                              style: TextStyle(color: BullyPalette.of(context).textMuted),
                            ),
                            trailing: s.current
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.logout, color: BullyColors.danger),
                                    onPressed: () => _revoke(s.id),
                                    tooltip: 'Кикнуть сессию',
                                  ),
                          ))
                      .toList(),
                ),
              ),
            ],
          );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: Text('Сессии', style: TextStyle(color: BullyPalette.of(context).textNormal, fontSize: 20, fontWeight: FontWeight.bold))),
                TextButton(onPressed: _revokeAll, child: const Text('Выйти на всех, кроме этого')),
              ],
            ),
          ),
          Expanded(child: _body(context)),
        ],
      );
    }
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(
        backgroundColor: BullyPalette.of(context).bgPrimary,
        title: const Text('Сессии'),
        actions: [
          TextButton(onPressed: _revokeAll, child: const Text('Выйти на всех, кроме этого')),
        ],
      ),
      body: _body(context),
    );
  }

  IconData _iconFor(String platform) {
    switch (platform) {
      case 'ios':
      case 'android':
        return Icons.smartphone;
      case 'macos':
      case 'windows':
      case 'linux':
        return Icons.laptop;
      case 'web':
        return Icons.public;
      default:
        return Icons.devices_other;
    }
  }

  String _formatAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин назад';
    if (diff.inDays < 1) return '${diff.inHours} ч назад';
    return '${diff.inDays} дн назад';
  }
}
