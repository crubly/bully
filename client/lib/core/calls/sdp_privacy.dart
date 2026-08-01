
class SdpPrivacy {
  static String disableAudioDtx(String sdp) {
    return sdp
        .split('\r\n')
        .map((line) {
          if (line.startsWith('a=fmtp:') && !line.contains('usedtx')) {
            return '$line;usedtx=0;cbr=1';
          }
          return line;
        })
        .join('\r\n');
  }
}
