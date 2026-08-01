/// SDP tweaks applied to every offer/answer before it's sent, purely for
/// call-traffic privacy (not correctness): Opus's default DTX/VAD behavior
/// stops sending audio packets during silence, which lets anyone who can
/// see encrypted RTP packet timing (even through a TURN relay that can't
/// decrypt SRTP) infer exactly when each participant is speaking. Forcing
/// continuous transmission at a fixed rate removes that timing signal,
/// mirroring the constant-rate padding used on the chat/relay channel.
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
