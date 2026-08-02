import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../storage/secure_store.dart';

const _channel = MethodChannel('bully/screen_privacy');

/// Controls what's visible to screen recording/casting from OTHER apps
/// (not screenshots within this app). "Скрыть всё" asks the OS to physically
/// exclude our window content from any capture (Android FLAG_SECURE) or, on
/// platforms without a prevention API (iOS), detects an active capture and
/// swaps the UI for a blurred placeholder for as long as it's being
/// recorded/mirrored.
class ScreenPrivacy extends ChangeNotifier {
  static final ScreenPrivacy instance = ScreenPrivacy._();
  ScreenPrivacy._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  bool _hideAll = false;
  bool _hideTransferCodes = true;
  bool _captured = false;

  bool get hideAll => _hideAll;
  bool get hideTransferCodes => _hideTransferCodes;
  bool get isCaptured => _captured;

  Future<void> load() async {
    _hideAll = (await SecureStore.getBlob('privacy:hide_all')) == '1';
    _hideTransferCodes = (await SecureStore.getBlob('privacy:hide_transfer_codes')) != '0';
    if (_hideAll) await _applyNative(true);
    notifyListeners();
  }

  Future<void> setHideAll(bool value) async {
    _hideAll = value;
    await SecureStore.setBlob('privacy:hide_all', value ? '1' : '0');
    await _applyNative(value);
    notifyListeners();
  }

  Future<void> setHideTransferCodes(bool value) async {
    _hideTransferCodes = value;
    await SecureStore.setBlob('privacy:hide_transfer_codes', value ? '1' : '0');
    notifyListeners();
  }

  Future<void> _applyNative(bool secure) async {
    try {
      await _channel.invokeMethod('setSecure', {'secure': secure});
    } catch (_) {

    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'captureStateChanged') {
      _captured = call.arguments as bool? ?? false;
      notifyListeners();
    }
    return null;
  }
}
