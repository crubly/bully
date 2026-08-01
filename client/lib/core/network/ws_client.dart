import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'bandwidth_tracker.dart';
import 'padding.dart';

/// A relay envelope exactly mirroring the backend's ws.Envelope — the
/// server only ever sees `ciphertext`/`header` as opaque strings.
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

/// Persistent WebSocket connection to the relay, with auto-reconnect.
///
/// Traffic is constant-rate padded (see padding.dart / backend's
/// internal/ws/padding.go): exactly one fixed-size frame goes out every
/// [WsPadding.frameSize]-sized tick regardless of whether there's a real
/// message queued, so a network observer between this device and the node
/// (a LAN router, an ISP, a Tailscale DERP relay) sees uniform traffic and
/// can't tell a real event from cover traffic by timing or size. Callers
/// subscribe to [messages] and never need to know about the underlying
/// socket lifecycle or framing.
class WsClient {
  static const _tickInterval = Duration(milliseconds: 200);

  final String baseUrl;
  WebSocketChannel? _channel;
  final _controller = StreamController<RelayEnvelope>.broadcast();
  final _outbox = <Uint8List>[]; // queued raw JSON envelope bytes awaiting fragmentation/send
  Uint8List? _pending; // bytes of the message currently being fragmented out
  Timer? _pump;
  final _assembly = BytesBuilder();
  String? _token;
  bool _closed = false;

  WsClient(this.baseUrl);

  Stream<RelayEnvelope> get messages => _controller.stream;

  Future<void> connect(String token) async {
    _token = token;
    _closed = false;
    await _open();
  }

  Future<void> _open() async {
    final wsBase = baseUrl.replaceFirst('http', 'ws');
    _channel = WebSocketChannel.connect(Uri.parse('$wsBase/ws?token=$_token'));
    _channel!.stream.listen(
      _handleFrame,
      onDone: _scheduleReconnect,
      onError: (_) => _scheduleReconnect(),
      cancelOnError: true,
    );
    _pump?.cancel();
    _pump = Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _handleFrame(dynamic raw) {
    if (raw is! List<int>) return; // ignore anything that isn't a binary frame
    BandwidthTracker.recordReceived(raw.length);
    final decoded = WsPadding.decodeFrame(Uint8List.fromList(raw));
    if (decoded == null) return; // cover/dummy frame — discard
    _assembly.add(decoded.payload);
    if (decoded.hasMore) return;

    final bytes = _assembly.takeBytes();
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      _controller.add(RelayEnvelope.fromJson(json));
    } catch (_) {
      // malformed reassembly — drop rather than crash the stream
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

  /// Queues an envelope for send; the fixed-rate pump drains it on the next
  /// tick(s) rather than sending it immediately, so send() never itself
  /// creates an observable off-cadence packet.
  void send(RelayEnvelope env) {
    _outbox.add(Uint8List.fromList(utf8.encode(jsonEncode(env.toOutboundJson()))));
  }

  void close() {
    _closed = true;
    _pump?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}
