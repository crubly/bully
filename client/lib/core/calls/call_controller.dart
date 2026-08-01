import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../crypto/session_manager.dart';
import '../network/api_client.dart';
import '../network/ws_client.dart';
import 'sdp_privacy.dart';

enum CallState { idle, outgoingRinging, incomingRinging, connecting, active, ended }

class IncomingCall {
  final String conversationId;
  final String fromUserId;
  final bool video;
  IncomingCall(this.conversationId, this.fromUserId, this.video);
}

class CallController {
  final ApiClient api;
  final WsClient ws;
  final CryptoSessionManager crypto;

  CallController(this.api, this.ws, this.crypto) {
    ws.messages.listen(_handleSignal);
  }

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _peerUserId;
  String? _conversationId;
  bool _isVideo = false;

  final _stateController = StreamController<CallState>.broadcast();
  final _incomingController = StreamController<IncomingCall>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _localStreamController = StreamController<MediaStream?>.broadcast();

  CallState _state = CallState.idle;
  CallState get state => _state;
  Stream<CallState> get stateStream => _stateController.stream;
  Stream<IncomingCall> get incomingCalls => _incomingController.stream;
  Stream<MediaStream?> get remoteStream => _remoteStreamController.stream;
  Stream<MediaStream?> get localStream => _localStreamController.stream;

  void _setState(CallState s) {
    _state = s;
    _stateController.add(s);
  }

  Future<Map<String, dynamic>> _rtcConfig() async {
    final servers = await api.fetchIceServers();
    return {
      'iceServers': servers,
      'iceTransportPolicy': 'relay',
    };
  }

  Future<void> _sendSignal(Map<String, dynamic> payload) async {
    final message = await crypto.encrypt(_conversationId!, jsonEncode(payload));
    ws.send(RelayEnvelope(
      type: 'call_signal',
      conversationId: _conversationId!,
      fromUserId: '',
      toUserId: _peerUserId,
      ciphertext: base64Encode(message.ciphertext),
      header: base64Encode(message.header),
    ));
  }

  Future<void> startCall({required String conversationId, required String peerUserId, required bool video}) async {
    _conversationId = conversationId;
    _peerUserId = peerUserId;
    _isVideo = video;
    _setState(CallState.outgoingRinging);

    _pc = await createPeerConnection(await _rtcConfig());
    _wireCommonHandlers();

    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': video});
    _localStreamController.add(_localStream);
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    final offer = await _pc!.createOffer();
    final munged = RTCSessionDescription(SdpPrivacy.disableAudioDtx(offer.sdp!), offer.type);
    await _pc!.setLocalDescription(munged);

    await _sendSignal({'kind': 'offer', 'sdp': munged.sdp, 'video': video});
  }

  Future<void> acceptCall(IncomingCall call) async {
    _conversationId = call.conversationId;
    _peerUserId = call.fromUserId;
    _isVideo = call.video;
    _setState(CallState.connecting);

    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': call.video});
    _localStreamController.add(_localStream);
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    final answer = await _pc!.createAnswer();
    final munged = RTCSessionDescription(SdpPrivacy.disableAudioDtx(answer.sdp!), answer.type);
    await _pc!.setLocalDescription(munged);
    await _sendSignal({'kind': 'answer', 'sdp': munged.sdp});
    _setState(CallState.active);
  }

  Future<void> declineCall(IncomingCall call) async {
    _conversationId = call.conversationId;
    _peerUserId = call.fromUserId;
    await _sendSignal({'kind': 'hangup'});
    _reset();
  }

  Future<void> hangUp() async {
    if (_conversationId != null && _peerUserId != null) {
      await _sendSignal({'kind': 'hangup'});
    }
    _reset();
  }

  Future<void> toggleScreenShare({required bool enable}) async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      throw UnsupportedError('Screen share needs native platform integration on mobile — desktop only for now.');
    }
    if (_pc == null || _localStream == null) return;

    final senders = await _pc!.senders;
    final videoSender = senders.firstWhere((s) => s.track?.kind == 'video', orElse: () => throw StateError('no video sender'));
    if (enable) {
      final screenStream = await navigator.mediaDevices.getDisplayMedia({'video': true});
      await videoSender.replaceTrack(screenStream.getVideoTracks().first);
    } else {
      final cameraStream = await navigator.mediaDevices.getUserMedia({'video': true});
      await videoSender.replaceTrack(cameraStream.getVideoTracks().first);
    }
  }

  void _wireCommonHandlers() {
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _remoteStreamController.add(_remoteStream);
      }
    };
    _pc!.onIceCandidate = (candidate) {
      _sendSignal({
        'kind': 'ice',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    _pc!.onConnectionState = (rtcState) {
      if (rtcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setState(CallState.active);
      } else if (rtcState == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          rtcState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _reset();
      }
    };
  }

  Future<void> _handleSignal(RelayEnvelope env) async {
    if (env.type != 'call_signal') return;
    Map<String, dynamic> payload;
    try {
      final plaintext = await crypto.decrypt(env.conversationId, base64Decode(env.header!), base64Decode(env.ciphertext!));
      payload = jsonDecode(plaintext) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (payload['kind']) {
      case 'offer':
        if (_state != CallState.idle) {
          return;
        }
        _conversationId = env.conversationId;
        _peerUserId = env.fromUserId;
        _isVideo = payload['video'] as bool? ?? false;
        _pc = await createPeerConnection(await _rtcConfig());
        _wireCommonHandlers();
        await _pc!.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String, 'offer'));
        _setState(CallState.incomingRinging);
        _incomingController.add(IncomingCall(env.conversationId, env.fromUserId, _isVideo));
        break;
      case 'answer':
        await _pc?.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String, 'answer'));
        _setState(CallState.active);
        break;
      case 'ice':
        if (payload['candidate'] != null) {
          await _pc?.addCandidate(RTCIceCandidate(
            payload['candidate'] as String,
            payload['sdpMid'] as String?,
            payload['sdpMLineIndex'] as int?,
          ));
        }
        break;
      case 'hangup':
        _reset();
        break;
    }
  }

  void _reset() {
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _pc?.close();
    _pc = null;
    _localStream = null;
    _remoteStream = null;
    _conversationId = null;
    _peerUserId = null;
    _localStreamController.add(null);
    _remoteStreamController.add(null);
    _setState(CallState.idle);
  }

  bool get isVideo => _isVideo;

  void setMuted(bool muted) {
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = !muted;
    }
  }
}
