import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';

import '../avatar/avatar_store.dart';
import '../storage/chat_history_store.dart';
import '../storage/secure_store.dart';
import 'pairing_code.dart';
import 'transfer_crypto.dart';

const bullyTransferServiceType = '_bully-transfer._tcp';

class TransferSnapshot {
  static Future<Map<String, dynamic>> capture() async => {
        'blobs': await SecureStore.exportAllBlobs(),
        'messages': ChatHistoryStore.exportAll(),
        'avatars': AvatarStore.exportAll(),
      };

  static Future<void> apply(Map<String, dynamic> snapshot) async {
    await SecureStore.importAllBlobs(Map<String, String>.from(snapshot['blobs'] as Map));
    await ChatHistoryStore.importAll(Map<String, dynamic>.from(snapshot['messages'] as Map));
    final avatars = snapshot['avatars'] as Map?;
    if (avatars != null) {
      await AvatarStore.importAll(Map<String, dynamic>.from(avatars));
    }
  }
}

class TransferHost {
  ServerSocket? _server;
  BonsoirBroadcast? _broadcast;
  final String code = PairingCode.generate();
  final _doneController = StreamController<void>.broadcast();

  Stream<void> get onTransferComplete => _doneController.stream;

  Future<void> start({required String deviceLabel}) async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final service = BonsoirService(
      name: 'bully-$deviceLabel-${_server!.port}',
      type: bullyTransferServiceType,
      port: _server!.port,
    );
    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.ready;
    await _broadcast!.start();
    _server!.listen(_handleConnection);
  }

  Future<void> _handleConnection(Socket socket) async {
    final key = await TransferCrypto.deriveKey(code);
    final buffer = BytesBuilder();
    late StreamSubscription sub;
    sub = socket.listen((data) async {
      buffer.add(data);
      final frame = TransferCrypto.tryReadFrame(buffer);
      if (frame == null) return;
      try {
        final request = await TransferCrypto.decryptFrame(key, frame);
        if (request['type'] == 'request_snapshot') {
          final snapshot = await TransferSnapshot.capture();
          final response = await TransferCrypto.encryptFrame(key, {'type': 'snapshot', 'data': snapshot});
          await TransferCrypto.writeFrame(socket, response);
          _doneController.add(null);
        }
      } catch (_) {

      } finally {
        await sub.cancel();
        await socket.close();
      }
    });
  }

  Future<void> stop() async {
    await _broadcast?.stop();
    await _server?.close();
    await _doneController.close();
  }
}

class DiscoveredHost {
  final String name;
  final String host;
  final int port;
  DiscoveredHost(this.name, this.host, this.port);
}

class TransferJoin {
  BonsoirDiscovery? _discovery;
  final _foundController = StreamController<DiscoveredHost>.broadcast();

  Stream<DiscoveredHost> get onHostFound => _foundController.stream;

  Future<void> startDiscovery() async {
    _discovery = BonsoirDiscovery(type: bullyTransferServiceType);
    await _discovery!.ready;
    await _discovery!.start();
    _discovery!.eventStream?.listen((event) {
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
        event.service?.resolve(_discovery!.serviceResolver);
      } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
        final resolved = event.service;
        if (resolved is ResolvedBonsoirService && resolved.host != null) {
          _foundController.add(DiscoveredHost(resolved.name, resolved.host!, resolved.port));
        }
      }
    });
  }

  Future<void> stopDiscovery() async {
    await _discovery?.stop();
    await _foundController.close();
  }

  Future<void> pullSnapshot({required String host, required int port, required String code}) async {
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 8));
    final key = await TransferCrypto.deriveKey(code);
    final request = await TransferCrypto.encryptFrame(key, {'type': 'request_snapshot'});
    await TransferCrypto.writeFrame(socket, request);

    final buffer = BytesBuilder();
    final completer = Completer<Map<String, dynamic>>();
    late StreamSubscription sub;
    sub = socket.listen(
      (data) async {
        buffer.add(data);
        final frame = TransferCrypto.tryReadFrame(buffer);
        if (frame == null) return;
        try {
          final response = await TransferCrypto.decryptFrame(key, frame);
          if (!completer.isCompleted) completer.complete(response['data'] as Map<String, dynamic>);
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
        } finally {
          await sub.cancel();
          await socket.close();
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    final snapshot = await completer.future.timeout(const Duration(seconds: 20));
    await TransferSnapshot.apply(snapshot);
  }
}
