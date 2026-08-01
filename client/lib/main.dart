import 'dart:async';

import 'package:flutter/material.dart';

import 'core/app_services.dart';
import 'core/media/media_cache.dart';
import 'core/network/api_client.dart';
import 'core/network/bandwidth_tracker.dart';
import 'core/node_store.dart';
import 'core/storage/chat_history_store.dart';
import 'core/storage/secure_store.dart';
import 'features/auth/auth_screen.dart';
import 'features/nodes/node_picker_screen.dart';
import 'features/shell/app_shell.dart';
import 'theme/discord_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ChatHistoryStore.init();
  await NodeStore.init();
  await BandwidthTracker.init();
  await MediaCache.init();
  runApp(const BullyApp());
}

class BullyApp extends StatelessWidget {
  const BullyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bully',
      debugShowCheckedModeBanner: false,
      theme: buildDiscordTheme(),
      home: const _Bootstrap(),
    );
  }
}

/// Every account lives on exactly one node (see NodePickerScreen), so the
/// resolved node URL must be known BEFORE AppServices (and its ApiClient/
/// WsClient) can be constructed. This widget owns that one piece of
/// bootstrap state; everything under it gets a real AppServices.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  BullyNode? _node;
  bool _checkingSavedNode = true;

  @override
  void initState() {
    super.initState();
    _tryResumeActiveNode();
  }

  Future<void> _tryResumeActiveNode() async {
    final active = NodeStore.active();
    if (active != null) {
      final name = await probeNode(active.url);
      if (name != null && mounted) {
        setState(() {
          _node = BullyNode(name, active.url);
          _checkingSavedNode = false;
        });
        return;
      }
    }
    if (mounted) setState(() => _checkingSavedNode = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSavedNode) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_node == null) {
      return NodePickerScreen(onNodeReady: (node) => setState(() => _node = node));
    }
    return AppServices(
      key: ValueKey(_node!.url),
      nodeUrl: _node!.url,
      child: const _RootRouter(),
    );
  }
}

/// Sends the user to the auth screen or straight into the app shell
/// depending on whether a token is already stored locally.
class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  bool _loading = true;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final services = AppServices.of(context);
    final token = await SecureStore.getAuthToken(services.api.baseUrl);
    if (token != null && mounted) {
      await services.ws.connect(token);
      unawaited(startBackgroundSyncForCurrentAccount(services));
    }
    setState(() {
      _authenticated = token != null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _authenticated ? const AppShell() : const AuthScreen();
  }
}
