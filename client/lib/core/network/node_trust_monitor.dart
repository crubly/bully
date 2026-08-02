import 'dart:async';

import 'package:flutter/foundation.dart';

import '../node_store.dart';
import 'padding.dart';

class NodeTrustMonitor extends ChangeNotifier {
  static final NodeTrustMonitor instance = NodeTrustMonitor._();
  NodeTrustMonitor._();

  static const _allowedTypes = {'direct', 'call_signal', 'avatar', 'message'};
  // Generous vs. the 200ms tick: real jitter (mobile background throttling,
  // Wi-Fi hiccups, GC pauses) routinely blows past 1-2 tick periods without
  // any malice involved — only a SUSTAINED pattern of large gaps is signal.
  static const _maxFrameGap = Duration(seconds: 2);
  static const _violationsToFlag = 5;

  bool _compromised = false;
  String? _reason;
  String? _nodeUrl;
  DateTime? _lastFrameAt;
  int _gapViolations = 0;
  int _sizeViolations = 0;

  bool get compromised => _compromised;
  String? get reason => _reason;

  void bindNode(String nodeUrl) {
    final isNewNode = _nodeUrl != nodeUrl;
    _nodeUrl = nodeUrl;
    onConnectionOpened();
    if (isNewNode && _compromised) {
      _compromised = false;
      _reason = null;
      notifyListeners();
    }
  }

  void onConnectionOpened() {
    _lastFrameAt = null;
    _gapViolations = 0;
    _sizeViolations = 0;
  }

  void onRawFrame(int lengthBytes) {
    if (lengthBytes != WsPadding.frameSize) {
      _sizeViolations++;
      if (_sizeViolations >= _violationsToFlag) {
        _flag('Нода регулярно присылает кадры неверного размера — нарушение протокола паддинга.');
      }
      return;
    }
    _sizeViolations = 0;

    final now = DateTime.now();
    final last = _lastFrameAt;
    _lastFrameAt = now;
    if (last == null) return;

    final gap = now.difference(last);
    if (gap > _maxFrameGap) {
      _gapViolations++;
      if (_gapViolations >= _violationsToFlag) {
        _flag('Нода систематически нарушает постоянный тайминг трафика ($_gapViolations пауз подряд свыше ${_maxFrameGap.inSeconds}с) — это может раскрывать момент отправки сообщений.');
      }
    } else {
      _gapViolations = 0;
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
