import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'bandwidth_tracker.dart';
import 'node_trust_monitor.dart';
import 'padding.dart';

class RelayEnvelope {
  final String type;
  final String conversationId;
  final String fromUserId;
  final String? toUserId;
  final String? messageId;
  final String? ciphertext;
  final String? header;

  RelayEnvelope({
    required this.type,
    required this.conversationId,
    required this.fromUserId,
    this.toUserId,
    this.messageId,
    this.ciphertext,
    this.header,
  });

  factory RelayEnvelope.fromJson(Map<String, dynamic> json) => RelayEnvelope(
        type: json['type'] as String,
        conversationId: json['conversation_id'] as String,
        fromUserId: json['from_user_id'] as String,
        toUserId: json['to_user_id'] as String?,
        messageId: json['message_id'] as String?,
        ciphertext: json['ciphertext'] as String?,
        header: json['header'] as String?,
      );

  Map<String, dynamic> toOutboundJson() => {
        'type': type,
        'conversation_id': conversationId,
        'to_user_id': toUserId,
        'ciphertext': ciphertext,
        'header': header,
      };
}

class WsClient {
  static const _tickInterval = Duration(milliseconds: 200);

  final String baseUrl;
  WebSocketChannel? _channel;
  final _controller = StreamController<RelayEnvelope>.broadcast();
  final _outbox = <Uint8List>[];
  Uint8List? _pending;
  Timer? _pump;
  final _assembly = BytesBuilder();
  String? _token;
  bool _closed = false;

  /// True once the WebSocket handshake has actually completed — connecting
  /// doesn't mean connected, and previously nothing distinguished the two,
  /// so a stuck/rejected handshake looked identical to "everything's fine,
  /// just no messages yet" from the UI's perspective.
  final connected = ValueNotifier<bool>(false);
  final lastError = ValueNotifier<String?>(null);

  WsClient(this.baseUrl);

  Stream<RelayEnvelope> get messages => _controller.stream;

  Future<void> connect(String token) async {
    _token = token;
    _closed = false;
    NodeTrustMonitor.instance.bindNode(baseUrl);
    await _open();
  }

  Future<void> _open() async {
    NodeTrustMonitor.instance.onConnectionOpened();
    final wsBase = baseUrl.replaceFirst('http', 'ws');
    final channel = WebSocketChannel.connect(Uri.parse('$wsBase/ws?token=$_token'));
    _channel = channel;
    try {
      await channel.ready;
    } catch (e) {
      connected.value = false;
      lastError.value = '$e';
      _scheduleReconnect();
      return;
    }
    if (_closed) return;
    connected.value = true;
    lastError.value = null;
    channel.stream.listen(
      _handleFrame,
      onDone: () {
        connected.value = false;
        _scheduleReconnect();
      },
      onError: (e) {
        connected.value = false;
        lastError.value = '$e';
        _scheduleReconnect();
      },
      cancelOnError: true,
    );
    _pump?.cancel();
    _pump = Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _handleFrame(dynamic raw) {
    if (raw is! List<int>) return;
    BandwidthTracker.recordReceived(raw.length);
    NodeTrustMonitor.instance.onRawFrame(raw.length);
    final decoded = WsPadding.decodeFrame(Uint8List.fromList(raw));
    if (decoded == null) return;
    _assembly.add(decoded.payload);
    if (decoded.hasMore) return;

    final bytes = _assembly.takeBytes();
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final envelope = RelayEnvelope.fromJson(json);
      NodeTrustMonitor.instance.onEnvelope(envelope.type);
      _controller.add(envelope);
    } catch (_) {

    }
  }

  void _tick() {
    final channel = _channel;
    if (channel == null) return;

    if (_pending == null || _pending!.isEmpty) {
      if (_outbox.isNotEmpty) _pending = _outbox.removeAt(0);
    }

    if (_pending != null && _pending!.isNotEmpty) {
      final end = _pending!.length > WsPadding.maxPayloadPerFrame ? WsPadding.maxPayloadPerFrame : _pending!.length;
      final slice = _pending!.sublist(0, end);
      final hasMore = end < _pending!.length;
      _pending = _pending!.sublist(end);
      final frame = WsPadding.encodeFrame(slice, hasMore: hasMore);
      channel.sink.add(frame);
      BandwidthTracker.recordSent(frame.length);
    } else {
      final frame = WsPadding.dummyFrame();
      channel.sink.add(frame);
      BandwidthTracker.recordSent(frame.length);
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    Future.delayed(const Duration(seconds: 2), () {
      if (!_closed) _open();
    });
  }

  void send(RelayEnvelope env) {
    if (NodeTrustMonitor.instance.compromised) return;
    _outbox.add(Uint8List.fromList(utf8.encode(jsonEncode(env.toOutboundJson()))));
  }

  void close() {
    _closed = true;
    _pump?.cancel();
    _channel?.sink.close();
    _controller.close();
    connected.dispose();
    lastError.dispose();
  }
}
