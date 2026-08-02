import 'dart:async';

import 'package:flutter/foundation.dart';

import '../node_store.dart';
import 'padding.dart';

class NodeTrustMonitor extends ChangeNotifier {
  static final NodeTrustMonitor instance = NodeTrustMonitor._();
  NodeTrustMonitor._();

  static const _allowedTypes = {'direct', 'call_signal', 'avatar', 'message'};
  static const _maxFrameGap = Duration(milliseconds: 600);

  bool _compromised = false;
  String? _reason;
  String? _nodeUrl;
  DateTime? _lastFrameAt;

  bool get compromised => _compromised;
  String? get reason => _reason;

  void bindNode(String nodeUrl) {
    if (_nodeUrl == nodeUrl) return;
    _nodeUrl = nodeUrl;
    _compromised = false;
    _reason = null;
    _lastFrameAt = null;
    notifyListeners();
  }

  void onRawFrame(int lengthBytes) {
    final now = DateTime.now();
    if (lengthBytes != WsPadding.frameSize) {
      _flag('Нода прислала кадр неверного размера ($lengthBytes байт вместо ${WsPadding.frameSize}) — нарушение протокола.');
      return;
    }
    final last = _lastFrameAt;
    _lastFrameAt = now;
    if (last != null) {
      final gap = now.difference(last);
      if (gap > _maxFrameGap) {
        _flag('Нода нарушает постоянный тайминг трафика (пауза ${gap.inMilliseconds} мс) — это может раскрывать момент отправки сообщений.');
      }
    }
  }

  void onEnvelope(String type) {
    if (!_allowedTypes.contains(type)) {
      _flag('Нода прислала неизвестный тип сообщения "$type" — не по протоколу.');
    }
  }

  void _flag(String reason) {
    if (_compromised) return;
    _compromised = true;
    _reason = reason;
    final url = _nodeUrl;
    if (url != null) unawaited(NodeStore.setFlagged(url, true, reason: reason));
    notifyListeners();
  }
}
