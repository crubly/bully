import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/app_services.dart';
import '../../core/calls/call_controller.dart';
import '../../core/desktop_window.dart';
import '../../theme/bully_theme.dart';

class CallScreen extends StatefulWidget {
  final IncomingCall? incoming;
  final Map<String, String>? labels;
  const CallScreen({super.key, this.incoming, this.labels});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _renderers = <String, RTCVideoRenderer>{};
  StreamSubscription? _stateSub;
  StreamSubscription? _participantsSub;
  CallState _state = CallState.connecting;
  bool _muted = false;
  bool _sharingScreen = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();

    final calls = AppServices.of(context).calls;
    _state = calls.state;
    _localRenderer.srcObject = calls.localStreamNow;
    _stateSub = calls.stateStream.listen((s) {
      setState(() => _state = s);
      if (s == CallState.idle && mounted) Navigator.of(context).pop();
    });
    _participantsSub = calls.participantsChanged.listen((_) => _syncRenderers(calls));
    _syncRenderers(calls);
  }

  Future<void> _syncRenderers(CallController calls) async {
    for (final id in calls.participantIds) {
      final renderer = _renderers.putIfAbsent(id, () => RTCVideoRenderer());
      if (renderer.textureId == null) await renderer.initialize();
      renderer.srcObject = calls.remoteStreamOf(id);
    }
    _renderers.removeWhere((id, r) {
      if (!calls.participantIds.contains(id)) {
        r.dispose();
        return true;
      }
      return false;
    });
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _participantsSub?.cancel();
    _localRenderer.dispose();
    for (final r in _renderers.values) {
      r.dispose();
    }
    super.dispose();
  }

  void _toggleMute() {
    final calls = AppServices.of(context).calls;
    setState(() => _muted = !_muted);
    calls.setMuted(_muted);
  }

  Future<void> _toggleScreenShare() async {
    final calls = AppServices.of(context).calls;
    try {
      await calls.toggleScreenShare(enable: !_sharingScreen);
      setState(() => _sharingScreen = !_sharingScreen);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  bool get _isDesktop => DesktopWindow.isDesktop;

  String _labelFor(String userId) => widget.labels?[userId] ?? (userId.isNotEmpty ? userId.substring(0, userId.length.clamp(0, 8)) : '?');

  @override
  Widget build(BuildContext context) {
    final calls = AppServices.of(context).calls;
    final participants = calls.participantIds;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _mainArea(calls, participants)),
            if (_localRenderer.srcObject != null && !calls.isGroup)
              Positioned(
                right: 16,
                top: 16,
                width: 120,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),
            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Text(_stateLabel(_state), style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _controlButton(
                    icon: Icons.mic,
                    iconColor: _muted ? BullyColors.danger : Colors.white,
                    onTap: _toggleMute,
                  ),
                  const SizedBox(width: 16),
                  if (_isDesktop)
                    _controlButton(
                      icon: _sharingScreen ? Icons.stop_screen_share : Icons.screen_share,
                      onTap: _toggleScreenShare,
                    ),
                  if (_isDesktop) const SizedBox(width: 16),
                  _controlButton(
                    icon: Icons.call_end,
                    color: BullyColors.danger,
                    onTap: () => calls.hangUp(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mainArea(CallController calls, List<String> participants) {
    if (participants.isEmpty) {
      return Center(child: Icon(Icons.person, size: 96, color: BullyPalette.of(context).textMuted));
    }
    if (participants.length == 1 && !calls.isGroup) {
      final id = participants.first;
      final renderer = _renderers[id];
      if (renderer?.srcObject != null) {
        return RTCVideoView(renderer!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
      }
      return Center(child: _ParticipantAvatar(label: _labelFor(id), speaking: calls.isPeerSpeaking(id), muted: calls.isPeerMuted(id), radius: 64));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 80, bottom: 120, left: 16, right: 16),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: participants.length <= 2 ? 1 : 2,
          childAspectRatio: 1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: participants.length,
        itemBuilder: (context, i) {
          final id = participants[i];
          final renderer = _renderers[id];
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Colors.grey.shade900,
              child: renderer?.srcObject != null
                  ? RTCVideoView(renderer!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Center(child: _ParticipantAvatar(label: _labelFor(id), speaking: calls.isPeerSpeaking(id), muted: calls.isPeerMuted(id), radius: 40)),
            ),
          );
        },
      ),
    );
  }

  String _stateLabel(CallState s) => switch (s) {
        CallState.outgoingRinging => 'Вызов...',
        CallState.incomingRinging => 'Входящий звонок',
        CallState.connecting => 'Подключение...',
        CallState.active => 'В разговоре',
        CallState.ended || CallState.idle => 'Завершено',
      };

  Widget _controlButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    Color iconColor = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: CircleAvatar(radius: 28, backgroundColor: color ?? BullyPalette.of(context).bgSecondary, child: Icon(icon, color: iconColor)),
    );
  }
}

/// Avatar with a thin accent-color ring while the participant is speaking,
/// and a small red mic-off badge on the bottom edge while muted.
class _ParticipantAvatar extends StatelessWidget {
  final String label;
  final bool speaking;
  final bool muted;
  final double radius;
  const _ParticipantAvatar({required this.label, required this.speaking, required this.muted, this.radius = 40});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: radius * 2 + 8,
      height: radius * 2 + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: radius * 2 + (speaking ? 8 : 0),
            height: radius * 2 + (speaking ? 8 : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: speaking ? Border.all(color: BullyColors.blurple, width: 3) : null,
            ),
          ),
          CircleAvatar(
            radius: radius,
            backgroundColor: BullyColors.blurple,
            child: Text(label.isNotEmpty ? label[0].toUpperCase() : '?', style: TextStyle(color: Colors.white, fontSize: radius * 0.5)),
          ),
          if (muted)
            Positioned(
              bottom: 0,
              child: CircleAvatar(radius: radius * 0.22, backgroundColor: BullyColors.danger, child: Icon(Icons.mic_off, size: radius * 0.26, color: Colors.white)),
            ),
        ],
      ),
    );
  }
}
