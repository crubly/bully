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

/// Keeps this account's devices mirrored while they happen to share a LAN,
/// with no human interaction after the initial device-transfer pairing.
///
/// Authentication/encryption key: every device that went through the
/// "full clone" transfer holds an IDENTICAL identity keypair (see
/// CryptoSessionManager / TransferSnapshot), so `sha256(identityPrivateKey)`
/// is automatically the same secret on every device of this account and
/// never needs to be re-entered or sent anywhere — it's simply derived
/// locally on both ends.
///
/// Transport privacy: every peer connection is a [PaddedSocket] — a
/// persistent, constant-rate, fixed-size-frame channel (see padding.dart).
/// It stays open and ticking (real traffic or cover filler, indistinguishable
/// by size/timing) for as long as the peer is reachable, specifically so a
/// LAN router watching two of this account's devices can't tell, by timing
/// or packet size, WHEN a sync actually carried new data versus just idling.
/// The manifest/push payloads themselves are additionally AES-GCM encrypted
/// with the sync key before framing, so even the padded connection's
/// content (not just its cadence) is opaque to anyone without that key.
///
/// Sync scope: message history (union merge, dedup by id). Crypto session
/// state (Double Ratchet / Sender Key blobs) is intentionally NOT
/// auto-merged here — see the class-level limitation note below.
///
/// Known limitation: if two devices of the same account both send/receive
/// messages independently on the SAME conversation while never in sync
/// (e.g. two different networks), the ratchet state fork can only be
/// resolved by picking one side as authoritative — the other side's
/// post-fork sends may become undecryptable by the remote peer. This is an
/// inherent tradeoff of the "shared identity clone" model chosen over
/// separate per-device identities (see plan notes).
class BackgroundSyncService {
  ServerSocket? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  Timer? _manifestTimer;
  Uint8List? _syncKey;
  final _peers = <String, DiscoveredPeer>{}; // "$host:$port" -> peer
  final _connections = <String, PaddedSocket>{}; // "$host:$port" -> live connection
  String? _selfServiceName;

  Future<void> start({required String userIdShortHash}) async {
    _syncKey = await _deriveSyncKey();
    if (_syncKey == null) return; // no identity yet (not fully set up) — nothing to sync

    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _server!.listen((socket) => _adopt('${socket.remoteAddress.address}:${socket.remotePort}', PaddedSocket(socket)));

    _selfServiceName = 'bully-sync-$userIdShortHash-${_server!.port}';
    _broadcast = BonsoirBroadcast(
      service: BonsoirService(name: _selfServiceName!, type: _syncServiceType, port: _server!.port),
    );
    await _broadcast!.ready;
    await _broadcast!.start();

    _discovery = BonsoirDiscovery(type: _syncServiceType);
    await _discovery!.ready;
    await _discovery!.start();
    _discovery!.eventStream?.listen((event) {
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
        event.service?.resolve(_discovery!.serviceResolver);
      } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
        final resolved = event.service;
        if (resolved is ResolvedBonsoirService && resolved.host != null && resolved.name != _selfServiceName) {
          final key = '${resolved.host}:${resolved.port}';
          _peers[key] = DiscoveredPeer(resolved.host!, resolved.port);
          _ensureConnected(key, _peers[key]!);
        }
      }
      // Lost-service events aren't tracked: a peer that goes offline just
      // fails/closes its connection and gets retried on next discovery.
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
      // Peer not reachable yet — the next discovery/manifest tick retries.
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
      // Encryption never fails in practice; guard anyway rather than crash a timer callback.
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
      return; // wrong account (key mismatch) or malformed peer — ignore
    }

    switch (message['type']) {
      case 'manifest':
        final theirManifest = Map<String, dynamic>.from(message['messages'] as Map? ?? {});
        final push = _computePush(theirManifest);
        if (push.isNotEmpty) {
          // Reply on whichever connection this manifest arrived on isn't
          // tracked per-message here, so push to every open connection —
          // harmless no-op merges on peers that already have the data.
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
