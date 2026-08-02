import 'dart:async';

import 'package:flutter/material.dart';

import 'core/app_services.dart';
import 'core/avatar/avatar_store.dart';
import 'core/crypto/crypto_selftest.dart';
import 'core/desktop_title_bar.dart';
import 'core/desktop_window.dart';
import 'core/media/media_cache.dart';
import 'core/network/api_client.dart';
import 'core/network/bandwidth_tracker.dart';
import 'core/network/connection_banner.dart';
import 'core/network/node_trust_banner.dart';
import 'core/node_store.dart';
import 'core/security/app_lock.dart';
import 'core/storage/chat_history_store.dart';
import 'core/storage/secure_store.dart';
import 'features/auth/auth_screen.dart';
import 'features/nodes/node_picker_screen.dart';
import 'features/security/lock_screen.dart';
import 'features/shell/app_shell.dart';
import 'theme/bully_theme.dart';
import 'theme/theme_backdrop.dart';
import 'theme/theme_controller.dart';

void main() async {
  ErrorWidget.builder = (details) => Material(
        color: Colors.red,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${details.exception}\n\n${details.stack}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      );
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await CryptoSelfTest.runOrThrow();
  } catch (e) {
    runApp(_CryptoSelfTestFailedApp(error: '$e'));
    return;
  }

  await DesktopWindow.ensureInitialized();
  await DesktopWindow.setTitle('Bully');
  await ChatHistoryStore.init();
  await NodeStore.init();
  await BandwidthTracker.init();
  await MediaCache.init();
  await AvatarStore.init();
  await ThemeController.instance.init();
  await AppLock.instance.init();
  runApp(const BullyApp());
}

class _CryptoSelfTestFailedApp extends StatelessWidget {
  final String error;
  const _CryptoSelfTestFailedApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1E1F22),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gpp_bad, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Проверка шифрования провалилась',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Криптографические примитивы ведут себя не так, как ожидается. '
                  'Запускать приложение небезопасно.',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(error, style: const TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// AppServices must wrap the Navigator itself (via MaterialApp.builder), not
/// just the first route's content — every screen reached via
/// Navigator.push() is a SIBLING subtree of that first route, not a
/// descendant of it, so AppServices.of(context) would fail with a null
/// check on any pushed screen (Settings, DM chat, calls, everything)
/// otherwise. This is why that used to crash silently in release builds
/// (asserts are stripped, so the null-check throws with no debug message).
class BullyApp extends StatefulWidget {
  const BullyApp({super.key});

  @override
  State<BullyApp> createState() => _BullyAppState();
}

class _BullyAppState extends State<BullyApp> {
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
    final node = _node;
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) => MaterialApp(
        title: 'Bully',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeController.instance.mode,
        theme: buildBullyTheme(Brightness.light),
        darkTheme: buildBullyTheme(Brightness.dark),
        builder: node == null
            ? null
            : (context, child) => Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => AppLock.instance.recordActivity(),
                  child: Stack(
                    children: [
                      const Positioned.fill(child: ThemeBackdrop()),
                      Column(
                        children: [
                          const DesktopTitleBar(),
                          const NodeTrustBanner(),
                          Expanded(
                            child: AppServices(
                              key: ValueKey(node.url),
                              nodeUrl: node.url,
                              child: child!,
                            ),
                          ),
                        ],
                      ),
                      Positioned.fill(
                        child: ListenableBuilder(
                          listenable: AppLock.instance,
                          builder: (context, _) => AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: AppLock.instance.locked
                                ? const LockScreen(key: ValueKey('locked'))
                                : const SizedBox.shrink(key: ValueKey('unlocked')),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        home: _checkingSavedNode
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : node == null
                ? NodePickerScreen(onNodeReady: (n) => setState(() => _node = n))
                : const _RootRouter(),
      ),
    );
  }
}

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
    if (!_authenticated) return const AuthScreen();
    final services = AppServices.of(context);
    return Column(
      children: [
        ConnectionBanner(ws: services.ws),
        const Expanded(child: AppShell()),
      ],
    );
  }
}
