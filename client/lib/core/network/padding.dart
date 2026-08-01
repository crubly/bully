import 'dart:math';
import 'dart:typed_data';

/// Dart mirror of the backend's internal/ws/padding.go frame format — see
/// that file for the full rationale (constant-rate cover traffic so a
/// network observer can't tell real messages from padding by timing/size).
class WsPadding {
  static const frameSize = 2048;
  static const _headerBytes = 3;
  static const maxPayloadPerFrame = frameSize - _headerBytes;

  static const _flagIsReal = 1 << 0;
  static const _flagHasMore = 1 << 1;

  static final _random = Random.secure();

  static Uint8List _randomFrame() {
    final frame = Uint8List(frameSize);
    for (var i = 0; i < frame.length; i++) {
      frame[i] = _random.nextInt(256);
    }
    return frame;
  }

  static Uint8List dummyFrame() {
    final frame = _randomFrame();
    frame[0] = 0;
    return frame;
  }

  static Uint8List encodeFrame(Uint8List payload, {required bool hasMore}) {
    assert(payload.length <= maxPayloadPerFrame);
    final frame = _randomFrame();
    var flags = _flagIsReal;
    if (hasMore) flags |= _flagHasMore;
    frame[0] = flags;
    frame[1] = (payload.length >> 8) & 0xFF;
    frame[2] = payload.length & 0xFF;
    frame.setRange(_headerBytes, _headerBytes + payload.length, payload);
    return frame;
  }

  /// Returns null for frames that aren't well-formed real payload frames
  /// (including cover/dummy frames, which callers should just discard).
  static ({Uint8List payload, bool hasMore})? decodeFrame(Uint8List frame) {
    if (frame.length != frameSize) return null;
    final flags = frame[0];
    final isReal = flags & _flagIsReal != 0;
    if (!isReal) return null;
    final hasMore = flags & _flagHasMore != 0;
    final length = (frame[1] << 8) | frame[2];
    if (length > maxPayloadPerFrame) return null;
    return (payload: frame.sublist(_headerBytes, _headerBytes + length), hasMore: hasMore);
  }

  /// Splits an arbitrary-length message into as many fixed-size frames as
  /// needed, each carrying up to [maxPayloadPerFrame] bytes.
  static List<Uint8List> splitIntoFrames(Uint8List message) {
    if (message.isEmpty) return [encodeFrame(Uint8List(0), hasMore: false)];
    final frames = <Uint8List>[];
    for (var offset = 0; offset < message.length; offset += maxPayloadPerFrame) {
      final end = (offset + maxPayloadPerFrame < message.length) ? offset + maxPayloadPerFrame : message.length;
      frames.add(encodeFrame(message.sublist(offset, end), hasMore: end < message.length));
    }
    return frames;
  }
}
