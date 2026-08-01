import 'dart:io';

class DeviceInfo {
  static String platform() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String deviceName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return platform();
    }
  }
}
