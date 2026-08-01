import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/app_services.dart';
import '../../core/calls/call_controller.dart';
import '../../theme/bully_theme.dart';

class CallScreen extends StatefulWidget {
  final IncomingCall? incoming;
  const CallScreen({super.key, this.incoming});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  StreamSubscription? _stateSub;
  StreamSubscription? _localSub;
  StreamSubscription? _remoteSub;
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
    await _remoteRenderer.initialize();

    final calls = AppServices.of(context).calls;
    _state = calls.state;
    _stateSub = calls.stateStream.listen((s) {
      setState(() => _state = s);
      if (s == CallState.idle && mounted) Navigator.of(context).pop();
    });
    _localSub = calls.localStream.listen((s) => setState(() => _localRenderer.srcObject = s));
    _remoteSub = calls.remoteStream.listen((s) => setState(() => _remoteRenderer.srcObject = s));

    if (widget.incoming != null) {

    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _localSub?.cancel();
    _remoteSub?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
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

  bool get _isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final calls = AppServices.of(context).calls;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _remoteRenderer.srcObject != null
                  ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Center(
                      child: Icon(Icons.person, size: 96, color: BullyPalette.of(context).textMuted),
                    ),
            ),
            if (_localRenderer.srcObject != null)
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
                child: Text(_labelFor(_state), style: const TextStyle(color: Colors.white, fontSize: 16)),
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

  String _labelFor(CallState s) => switch (s) {
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
