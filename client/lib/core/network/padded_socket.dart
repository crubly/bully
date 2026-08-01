import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'padding.dart';

/// Same constant-rate padded framing as [WsClient], applied to a raw
/// point-to-point [Socket] instead of the relay WebSocket. Used by
/// [BackgroundSyncService] so a LAN router watching two of this account's
/// devices talk to each other can't tell, by timing or packet size, when a
/// real sync actually happened versus the connection just idling.
class PaddedSocket {
  static const tickInterval = Duration(milliseconds: 200);

  final Socket _socket;
  final _outbox = <Uint8List>[];
  Uint8List? _pending;
  final _assembly = BytesBuilder();
  final _inbox = StreamController<Uint8List>.broadcast();
  Timer? _pump;
  bool _closed = false;

  PaddedSocket(this._socket) {
    _socket.listen(_handleBytes, onDone: close, onError: (_) => close(), cancelOnError: true);
    _pump = Timer.periodic(tickInterval, (_) => _tick());
  }

  static Future<PaddedSocket> connect(String host, int port, {Duration timeout = const Duration(seconds: 8)}) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    return PaddedSocket(socket);
  }

  /// Yields the raw bytes of each reassembled message — callers own
  /// serialization/encryption, this class only owns framing/pacing.
  Stream<Uint8List> get messages => _inbox.stream;

  void send(Uint8List payload) {
    if (_closed) return;
    _outbox.add(payload);
  }

  final _incomingBuffer = BytesBuilder();

  void _handleBytes(List<int> data) {
    _incomingBuffer.add(data);
    while (true) {
      final bytes = _incomingBuffer.toBytes();
      if (bytes.length < WsPadding.frameSize) return;
      final frame = Uint8List.fromList(bytes.sublist(0, WsPadding.frameSize));
      _incomingBuffer.clear();
      _incomingBuffer.add(bytes.sublist(WsPadding.frameSize));

      final decoded = WsPadding.decodeFrame(frame);
      if (decoded == null) continue; // cover frame
      _assembly.add(decoded.payload);
      if (decoded.hasMore) continue;

      _inbox.add(_assembly.takeBytes());
    }
  }

  void _tick() {
    if (_closed) return;
    if (_pending == null || _pending!.isEmpty) {
      if (_outbox.isNotEmpty) _pending = _outbox.removeAt(0);
    }
    if (_pending != null && _pending!.isNotEmpty) {
      final end = _pending!.length > WsPadding.maxPayloadPerFrame ? WsPadding.maxPayloadPerFrame : _pending!.length;
      final slice = _pending!.sublist(0, end);
      final hasMore = end < _pending!.length;
      _pending = _pending!.sublist(end);
      _socket.add(WsPadding.encodeFrame(slice, hasMore: hasMore));
    } else {
      _socket.add(WsPadding.dummyFrame());
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _pump?.cancel();
    _socket.destroy();
    _inbox.close();
  }
}
