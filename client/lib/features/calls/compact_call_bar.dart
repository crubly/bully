import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/calls/call_controller.dart';
import '../../core/desktop_window.dart';
import '../../theme/bully_theme.dart';

/// Desktop and tablets get a small in-chat call bar instead of the
/// full-screen CallScreen (which stays reserved for phones).
bool useCompactCallUi(BuildContext context) =>
    DesktopWindow.isDesktop || MediaQuery.sizeOf(context).shortestSide >= 600;

class CompactCallBar extends StatefulWidget {
  final CallController calls;
  final String Function(String userId) labelFor;
  const CompactCallBar({super.key, required this.calls, required this.labelFor});

  @override
  State<CompactCallBar> createState() => _CompactCallBarState();
}

class _CompactCallBarState extends State<CompactCallBar> {
  bool _muted = false;
  bool _deafened = false;
  StreamSubscription<void>? _participantsSub;

  @override
  void initState() {
    super.initState();
    _participantsSub = widget.calls.participantsChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _participantsSub?.cancel();
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    widget.calls.setMuted(_muted);
  }

  void _toggleDeafen() {
    setState(() => _deafened = !_deafened);
    for (final id in widget.calls.participantIds) {
      for (final track in widget.calls.remoteStreamOf(id)?.getAudioTracks() ?? const []) {
        track.enabled = !_deafened;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final participants = widget.calls.participantIds;
    return FractionallySizedBox(
      heightFactor: 0.3,
      widthFactor: 1,
      child: Container(
        decoration: BoxDecoration(
          color: BullyPalette.of(context).bgTertiary,
          border: Border(bottom: BorderSide(color: BullyPalette.of(context).cardBorder)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: participants.isEmpty
                    ? [_avatar('?', false, false, hasVideo: false)]
                    : participants
                        .map((id) => _avatar(
                              widget.labelFor(id),
                              widget.calls.isPeerSpeaking(id),
                              widget.calls.isPeerMuted(id),
                              hasVideo: widget.calls.remoteStreamOf(id) != null && widget.calls.isVideo,
                            ))
                        .toList(),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _iconButton(icon: _muted ? Icons.mic_off : Icons.mic, active: _muted, onTap: _toggleMute),
                  const SizedBox(width: 12),
                  _iconButton(icon: _deafened ? Icons.volume_off : Icons.volume_up, active: _deafened, onTap: _toggleDeafen),
                  const SizedBox(width: 12),
                  _iconButton(icon: Icons.call_end, danger: true, onTap: widget.calls.hangUp),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String label, bool speaking, bool muted, {required bool hasVideo}) {
    const radius = 24.0;
    return SizedBox(
      width: radius * 2 + 8,
      height: radius * 2 + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: radius * 2 + (speaking ? 6 : 0),
            height: radius * 2 + (speaking ? 6 : 0),
            decoration: BoxDecoration(shape: BoxShape.circle, border: speaking ? Border.all(color: BullyColors.blurple, width: 2) : null),
          ),
          CircleAvatar(
            radius: radius,
            backgroundColor: BullyColors.blurple,
            child: Text(label.isNotEmpty ? label[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 18)),
          ),
          if (muted)
            const Positioned(
              bottom: 0,
              child: CircleAvatar(radius: 8, backgroundColor: BullyColors.danger, child: Icon(Icons.mic_off, size: 10, color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Widget _iconButton({required IconData icon, required VoidCallback onTap, bool active = false, bool danger = false}) {
    final color = danger ? BullyColors.danger : (active ? BullyColors.danger : BullyPalette.of(context).bgSecondary);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: CircleAvatar(radius: 18, backgroundColor: color, child: Icon(icon, size: 16, color: Colors.white)),
    );
  }
}
