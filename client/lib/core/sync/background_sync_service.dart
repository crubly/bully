import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';
import 'package:crypto/crypto.dart' as crypto;

import '../network/padded_socket.dart';
import '../storage/chat_history_store.dart';
import '../storage/secure_store.dart';
import '../transfer/transfer_crypto.dart';

const _syncServiceType = '_bully-sync._tcp';
const _manifestInterval = Duration(seconds: 5);

class BackgroundSyncService {
  ServerSocket? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  Timer? _manifestTimer;
  Uint8List? _syncKey;
  final _peers = <String, DiscoveredPeer>{};
  final _connections = <String, PaddedSocket>{};
  String? _selfServiceName;

  Future<void> start({required String userIdShortHash}) async {
    _syncKey = await _deriveSyncKey();
    if (_syncKey == null) return;

    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _server!.listen((socket) => _adopt('${socket.remoteAddress.address}:${socket.remotePort}', PaddedSocket(socket)));

    _selfServiceName = 'bully-sync-$userIdShortHash-${_server!.port}';
    _broadcast = BonsoirBroadcast(
      service: BonsoirService(name: _selfServiceName!, type: _syncServiceType, port: _server!.port),
    );
    await _broadcast!.initialize();
    await _broadcast!.start();

    _discovery = BonsoirDiscovery(type: _syncServiceType);
    await _discovery!.initialize();
    await _discovery!.start();
    _discovery!.eventStream?.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent(:final service):
          service.resolve(_discovery!.serviceResolver);
        case BonsoirDiscoveryServiceResolvedEvent(:final service):
          if (service.hostAddresses.isNotEmpty && service.name != _selfServiceName) {
            final key = '${service.hostAddresses.first}:${service.port}';
            _peers[key] = DiscoveredPeer(service.hostAddresses.first, service.port);
            _ensureConnected(key, _peers[key]!);
          }
        default:
          break;
      }
    });

    _manifestTimer = Timer.periodic(_manifestInterval, (_) => _broadcastManifestToAll());
  }

  Future<void> stop() async {
    _manifestTimer?.cancel();
    await _discovery?.stop();
    await _broadcast?.stop();
    await _server?.close();
    for (final conn in _connections.values) {
      conn.close();
    }
    _connections.clear();
  }

  Future<void> _ensureConnected(String key, DiscoveredPeer peer) async {
    if (_connections.containsKey(key)) return;
    try {
      final socket = await PaddedSocket.connect(peer.host, peer.port);
      _adopt(key, socket);
    } catch (_) {

    }
  }

  void _adopt(String key, PaddedSocket socket) {
    _connections[key] = socket;
    socket.messages.listen(
      (bytes) => _handleMessage(bytes),
      onDone: () => _connections.remove(key),
      onError: (_) => _connections.remove(key),
    );
  }

  Future<Uint8List?> _deriveSyncKey() async {
    final identityJson = await SecureStore.getBlob('identity_keypair');
    if (identityJson == null) return null;
    final map = jsonDecode(identityJson) as Map<String, dynamic>;
    final privateB64 = map['private'] as String;
    final digest = crypto.sha256.convert(utf8.encode(privateB64));
    return Uint8List.fromList(digest.bytes);
  }

  void _broadcastManifestToAll() {
    final manifest = {'type': 'manifest', 'messages': _buildMessageManifest()};
    for (final conn in _connections.values.toList()) {
      _sendEncrypted(conn, manifest);
    }
  }

  Future<void> _sendEncrypted(PaddedSocket conn, Map<String, dynamic> payload) async {
    try {
      conn.send(await TransferCrypto.encryptFrame(_syncKey!, payload));
    } catch (_) {

    }
  }

  Map<String, int> _buildMessageManifest() {
    final manifest = <String, int>{};
    for (final convoId in ChatHistoryStore.allConversationIds()) {
      final msgs = ChatHistoryStore.messagesFor(convoId);
      if (msgs.isNotEmpty) {
        manifest[convoId] = msgs.map((m) => m.timestampMs).reduce((a, b) => a > b ? a : b);
      }
    }
    return manifest;
  }

  Map<String, dynamic> _computePush(Map<String, dynamic> theirManifest) {
    final push = <String, dynamic>{};
    for (final convoId in ChatHistoryStore.allConversationIds()) {
      final theirMax = (theirManifest[convoId] as int?) ?? 0;
      final newer = ChatHistoryStore.messagesFor(convoId).where((m) => m.timestampMs > theirMax).toList();
      if (newer.isNotEmpty) push[convoId] = newer.map((m) => m.toMap()).toList();
    }
    return push;
  }

  Future<void> _handleMessage(Uint8List bytes) async {
    Map<String, dynamic> message;
    try {
      message = await TransferCrypto.decryptFrame(_syncKey!, bytes);
    } catch (_) {
      return;
    }

    switch (message['type']) {
      case 'manifest':
        final theirManifest = Map<String, dynamic>.from(message['messages'] as Map? ?? {});
        final push = _computePush(theirManifest);
        if (push.isNotEmpty) {

          for (final conn in _connections.values.toList()) {
            await _sendEncrypted(conn, {'type': 'push', 'data': push});
          }
        }
        break;
      case 'push':
        final data = Map<String, dynamic>.from(message['data'] as Map? ?? {});
        for (final entry in data.entries) {
          await ChatHistoryStore.importAll({entry.key: entry.value});
        }
        break;
    }
  }
}

class DiscoveredPeer {
  final String host;
  final int port;
  DiscoveredPeer(this.host, this.port);
}
