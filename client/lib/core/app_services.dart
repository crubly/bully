import 'package:flutter/widgets.dart';

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto_hash;

import 'calls/call_controller.dart';
import 'crypto/group_session_manager.dart';
import 'crypto/session_manager.dart';
import 'network/api_client.dart';
import 'network/ws_client.dart';
import 'storage/secure_store.dart';
import 'sync/background_sync_service.dart';

class AppServices extends InheritedWidget {
  final ApiClient api;
  final WsClient ws;
  final CryptoSessionManager crypto;
  final GroupSessionManager groupCrypto;
  final BackgroundSyncService sync;
  final CallController calls;

  AppServices._({
    super.key,
    required super.child,
    required this.api,
    required this.ws,
    required this.crypto,
    required this.groupCrypto,
    required this.sync,
    required this.calls,
  });

  factory AppServices({Key? key, required Widget child, required String nodeUrl, ApiClient? api, WsClient? ws}) {
    final resolvedApi = api ?? ApiClient(nodeUrl);
    final resolvedWs = ws ?? WsClient(nodeUrl);
    final resolvedCrypto = CryptoSessionManager(resolvedApi);
    return AppServices._(
      key: key,
      child: child,
      api: resolvedApi,
      ws: resolvedWs,
      crypto: resolvedCrypto,
      groupCrypto: GroupSessionManager(resolvedApi, resolvedWs, () => resolvedCrypto.identity),
      sync: BackgroundSyncService(),
      calls: CallController(resolvedApi, resolvedWs, resolvedCrypto),
    );
  }

  static AppServices of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<AppServices>();
    assert(result != null, 'No AppServices found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(AppServices oldWidget) => false;
}

Future<void> startBackgroundSyncForCurrentAccount(AppServices services) async {
  await services.crypto.ensureIdentity();
  final userId = await SecureStore.getUserId(services.api.baseUrl);
  if (userId == null) return;
  final shortHash = crypto_hash.sha256.convert(utf8.encode(userId)).toString().substring(0, 12);
  await services.sync.start(userIdShortHash: shortHash);
}
