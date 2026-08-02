import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../crypto/group_session_manager.dart';
import '../crypto/session_manager.dart';
import '../desktop_window.dart';
import '../network/api_client.dart';
import '../network/ws_client.dart';
import '../storage/secure_store.dart';
import 'sdp_privacy.dart';

enum CallState { idle, outgoingRinging, incomingRinging, connecting, active, ended }

const _speakingThreshold = 0.02;
const _statsPollInterval = Duration(milliseconds: 500);

class IncomingCall {
  final String conversationId;
  final String fromUserId;
  final bool video;
  final bool isGroup;
  IncomingCall(this.conversationId, this.fromUserId, this.video, {this.isGroup = false});
}

/// One WebRTC leg to a single other participant. A DM call has exactly one
/// of these; a group call has one per other member currently connected
/// (mesh topology — every pair of participants gets its own direct leg,
/// there is no SFU).
class _Peer {
  final RTCPeerConnection pc;
  MediaStream? remoteStream;
  bool muted = false;
  bool speaking = false;
  _Peer(this.pc);
}

class CallController {
  final ApiClient api;
  final WsClient ws;
  final CryptoSessionManager crypto;
  final GroupSessionManager groupCrypto;

  CallController(this.api, this.ws, this.crypto, this.groupCrypto) {
    ws.messages.listen(_handleSignal);
  }

  final Map<String, _Peer> _peers = {};
  final Map<String, String> _groupIdByConversation = {};
  MediaStream? _localStream;
  String? _myUserId;
  String? _conversationId;
  String? _groupId;
  bool _isGroup = false;
  bool _isVideo = false;
  bool _localMuted = false;
  bool _localSpeaking = false;
  Timer? _statsTimer;

  /// Lets any open GroupChatScreen tell CallController which groupId a
  /// conversationId belongs to, so an incoming call_signal for that
  /// conversation (which carries only conversationId) can be decrypted via
  /// the right pairwise key-exchange session instead of the DM one.
  void registerGroup(String conversationId, String groupId) {
    _groupIdByConversation[conversationId] = groupId;
  }

  final _stateController = StreamController<CallState>.broadcast();
  final _incomingController = StreamController<IncomingCall>.broadcast();
  final _participantsController = StreamController<void>.broadcast();

  CallState _state = CallState.idle;
  CallState get state => _state;
  Stream<CallState> get stateStream => _stateController.stream;
  Stream<IncomingCall> get incomingCalls => _incomingController.stream;

  /// Fires whenever a participant's remote stream, mute state or speaking
  /// state changes — UI should re-read participantIds()/peerFor() on this.
  Stream<void> get participantsChanged => _participantsController.stream;

  void _setState(CallState s) {
    _state = s;
    _stateController.add(s);
  }

  List<String> get participantIds => _peers.keys.toList();
  MediaStream? remoteStreamOf(String userId) => _peers[userId]?.remoteStream;
  bool isPeerMuted(String userId) => _peers[userId]?.muted ?? false;
  bool isPeerSpeaking(String userId) => _peers[userId]?.speaking ?? false;
  bool get localMuted => _localMuted;
  bool get localSpeaking => _localSpeaking;
  MediaStream? get localStreamNow => _localStream;
  String? get activeConversationId => _conversationId;
  bool get isVideo => _isVideo;
  bool get isGroup => _isGroup;

  Future<Map<String, dynamic>> _rtcConfig() async {
    final servers = await api.fetchIceServers();
    return {
      'iceServers': servers,
      'iceTransportPolicy': 'relay',
    };
  }

  Future<void> _sendSignalTo(String peerUserId, Map<String, dynamic> payload) async {
    final conversationId = _conversationId!;
    final plaintext = jsonEncode(payload);
    late Uint8List header;
    late Uint8List ciphertext;
    if (_isGroup) {
      final myId = await _resolveMyUserId();
      final message = await groupCrypto.encryptForCall(groupId: _groupId!, myUserId: myId, otherUserId: peerUserId, plaintext: plaintext);
      header = message.header;
      ciphertext = message.ciphertext;
    } else {
      final message = await crypto.encrypt(conversationId, plaintext);
      header = message.header;
      ciphertext = message.ciphertext;
    }
    ws.send(RelayEnvelope(
      type: 'call_signal',
      conversationId: conversationId,
      fromUserId: '',
      toUserId: peerUserId,
      ciphertext: base64Encode(ciphertext),
      header: base64Encode(header),
    ));
  }

  // ---- DM (1:1) calls — direct offer/answer, no negotiation needed since
  // there's always exactly one caller and one callee. ----

  Future<void> startCall({required String conversationId, required String peerUserId, required bool video}) async {
    _conversationId = conversationId;
    _isGroup = false;
    _isVideo = video;
    _setState(CallState.outgoingRinging);

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': video});
      final pc = await createPeerConnection(await _rtcConfig());
      final peer = _Peer(pc);
      _peers[peerUserId] = peer;
      _wireCommonHandlers(peerUserId, peer);
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }

      final offer = await pc.createOffer();
      final munged = RTCSessionDescription(SdpPrivacy.disableAudioDtx(offer.sdp!), offer.type);
      await pc.setLocalDescription(munged);

      await _sendSignalTo(peerUserId, {'kind': 'offer', 'sdp': munged.sdp, 'video': video});
      _startStatsPolling();
    } catch (e) {
      await _reset();
      rethrow;
    }
  }

  Future<String> _resolveMyUserId() async {
    _myUserId ??= await SecureStore.getUserId(api.baseUrl) ?? '';
    return _myUserId!;
  }

  Future<void> acceptCall(IncomingCall call) async {
    if (call.isGroup && !_peers.containsKey(call.fromUserId)) {
      // This IncomingCall came from a 'group_announce', not a direct offer
      // (nobody had a leg to us yet) — accepting means fully joining: fetch
      // the current member list, get local media, announce ourselves, then
      // apply the same lower-id-offers tie-break as joinGroupCall.
      _conversationId = call.conversationId;
      final resolvedGroupId = _groupIdByConversation[call.conversationId];
      if (resolvedGroupId == null) {
        throw StateError('unknown group for conversation ${call.conversationId} — open the group chat once before accepting its calls');
      }
      _groupId = resolvedGroupId;
      final myId = await _resolveMyUserId();
      _isGroup = true;
      _isVideo = call.video;
      _setState(CallState.connecting);
      _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': call.video});
      _setState(CallState.active);
      _startStatsPolling();

      List<String> others;
      try {
        others = (await api.conversationMembers(call.conversationId)).cast<String>().where((m) => m != myId).toList();
      } catch (_) {
        others = [call.fromUserId];
      }
      for (final other in others) {
        await _sendSignalTo(other, {'kind': 'group_announce', 'video': call.video});
      }
      for (final other in others) {
        if (myId.compareTo(other) < 0) {
          await _offerTo(other, call.video);
        }
      }
      return;
    }

    _conversationId = call.conversationId;
    _isGroup = call.isGroup;
    _isVideo = call.video;
    _setState(CallState.connecting);

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': call.video});
      final peer = _peers[call.fromUserId];
      if (peer == null) return;
      for (final track in _localStream!.getTracks()) {
        await peer.pc.addTrack(track, _localStream!);
      }

      final answer = await peer.pc.createAnswer();
      final munged = RTCSessionDescription(SdpPrivacy.disableAudioDtx(answer.sdp!), answer.type);
      await peer.pc.setLocalDescription(munged);
      await _sendSignalTo(call.fromUserId, {'kind': 'answer', 'sdp': munged.sdp});
      _setState(CallState.active);
      _startStatsPolling();
    } catch (e) {
      await _reset();
      rethrow;
    }
  }

  Future<void> declineCall(IncomingCall call) async {
    _conversationId = call.conversationId;
    await _sendSignalTo(call.fromUserId, {'kind': 'hangup'});
    _peers.remove(call.fromUserId)?.pc.close();
    if (_peers.isEmpty) await _reset();
  }

  // ---- Group calls — mesh: every pair connects directly. To avoid both
  // sides racing to send an offer to each other (glare), only the
  // participant with the lexicographically SMALLER user id ever sends the
  // offer for a given pair; the other side just answers. Presence is
  // learned via a lightweight 'group_announce' broadcast to every other
  // member, sent on join and re-sent (harmlessly, idempotently) whenever a
  // new announce from someone else arrives while already in the call. ----

  Future<void> joinGroupCall({
    required String conversationId,
    required String groupId,
    required String myUserId,
    required List<String> otherMemberIds,
    required bool video,
  }) async {
    _conversationId = conversationId;
    _groupId = groupId;
    registerGroup(conversationId, groupId);
    _myUserId = myUserId;
    _isGroup = true;
    _isVideo = video;
    _setState(CallState.connecting);

    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': video});
    _setState(CallState.active);
    _startStatsPolling();

    for (final other in otherMemberIds) {
      await _sendSignalTo(other, {'kind': 'group_announce', 'video': video});
    }
    for (final other in otherMemberIds) {
      if (myUserId.compareTo(other) < 0) {
        await _offerTo(other, video);
      }
    }
  }

  Future<void> _offerTo(String peerUserId, bool video) async {
    if (_peers.containsKey(peerUserId) || _localStream == null) return;
    final pc = await createPeerConnection(await _rtcConfig());
    final peer = _Peer(pc);
    _peers[peerUserId] = peer;
    _wireCommonHandlers(peerUserId, peer);
    for (final track in _localStream!.getTracks()) {
      await pc.addTrack(track, _localStream!);
    }
    final offer = await pc.createOffer();
    final munged = RTCSessionDescription(SdpPrivacy.disableAudioDtx(offer.sdp!), offer.type);
    await pc.setLocalDescription(munged);
    await _sendSignalTo(peerUserId, {'kind': 'offer', 'sdp': munged.sdp, 'video': video, 'group': true});
  }

  Future<void> toggleScreenShare({required bool enable}) async {
    if (!DesktopWindow.isDesktop) {
      throw UnsupportedError('Screen share needs native platform integration on mobile — desktop only for now.');
    }
    if (_localStream == null || _peers.isEmpty) return;

    final newStream = enable
        ? await navigator.mediaDevices.getDisplayMedia({'video': true})
        : await navigator.mediaDevices.getUserMedia({'video': true});
    final newTrack = newStream.getVideoTracks().first;
    for (final track in newStream.getTracks()) {
      if (track.id != newTrack.id) await track.stop();
    }

    for (final peer in _peers.values) {
      final senders = await peer.pc.senders;
      final videoSender = senders.where((s) => s.track?.kind == 'video').cast<RTCRtpSender?>().firstWhere((s) => s != null, orElse: () => null);
      if (videoSender == null) continue;
      final oldTrack = videoSender.track;
      await videoSender.replaceTrack(newTrack);
      if (oldTrack != null && oldTrack.id != newTrack.id) await oldTrack.stop();
    }

    final oldLocalTrack = _localStream!.getVideoTracks().isEmpty ? null : _localStream!.getVideoTracks().first;
    if (oldLocalTrack != null) await _localStream!.removeTrack(oldLocalTrack);
    await _localStream!.addTrack(newTrack);
  }

  void _wireCommonHandlers(String peerUserId, _Peer peer) {
    peer.pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        peer.remoteStream = event.streams.first;
        _participantsController.add(null);
      }
    };
    peer.pc.onIceCandidate = (candidate) {
      _sendSignalTo(peerUserId, {
        'kind': 'ice',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    peer.pc.onConnectionState = (rtcState) {
      if (rtcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setState(CallState.active);
      } else if (rtcState == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          rtcState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _peers.remove(peerUserId)?.pc.close();
        _participantsController.add(null);
        if (!_isGroup && _peers.isEmpty) unawaited(_reset());
      }
    };
  }

  Future<void> hangUp() async {
    final conversationId = _conversationId;
    final peers = _peers.keys.toList();
    if (conversationId != null) {
      for (final p in peers) {
        await _sendSignalTo(p, {'kind': 'hangup'});
      }
    }
    await _reset();
  }

  Future<void> _handleSignal(RelayEnvelope env) async {
    if (env.type != 'call_signal') return;
    final groupId = _groupIdByConversation[env.conversationId];
    Map<String, dynamic> payload;
    try {
      String plaintext;
      if (groupId != null) {
        final myId = await _resolveMyUserId();
        plaintext = await groupCrypto.decryptForCall(
          groupId: groupId,
          myUserId: myId,
          otherUserId: env.fromUserId,
          header: base64Decode(env.header!),
          ciphertext: base64Decode(env.ciphertext!),
        );
      } else {
        plaintext = await crypto.decrypt(env.conversationId, base64Decode(env.header!), base64Decode(env.ciphertext!));
      }
      payload = jsonDecode(plaintext) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (payload['kind']) {
      case 'group_announce':
        if (_conversationId != env.conversationId || _state == CallState.idle) {
          _incomingController.add(IncomingCall(env.conversationId, env.fromUserId, payload['video'] as bool? ?? false, isGroup: true));
          return;
        }
        final myId = _myUserId;
        if (myId != null && myId.compareTo(env.fromUserId) < 0) {
          await _offerTo(env.fromUserId, _isVideo);
        }
        break;
      case 'offer':
        if (_conversationId != null && _conversationId != env.conversationId) return;
        final isGroupOffer = payload['group'] as bool? ?? false;
        if (!isGroupOffer && _state != CallState.idle && _conversationId != env.conversationId) return;
        _conversationId = env.conversationId;
        _isGroup = isGroupOffer || _isGroup;
        if (isGroupOffer && groupId != null) _groupId = groupId;
        final video = payload['video'] as bool? ?? false;
        _isVideo = _isVideo || video;
        final pc = await createPeerConnection(await _rtcConfig());
        final peer = _Peer(pc);
        _peers[env.fromUserId] = peer;
        _wireCommonHandlers(env.fromUserId, peer);
        await pc.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String, 'offer'));
        if (_localStream != null) {
          for (final track in _localStream!.getTracks()) {
            await pc.addTrack(track, _localStream!);
          }
          final answer = await pc.createAnswer();
          final munged = RTCSessionDescription(SdpPrivacy.disableAudioDtx(answer.sdp!), answer.type);
          await pc.setLocalDescription(munged);
          await _sendSignalTo(env.fromUserId, {'kind': 'answer', 'sdp': munged.sdp});
          _setState(CallState.active);
        } else {
          _setState(CallState.incomingRinging);
          _incomingController.add(IncomingCall(env.conversationId, env.fromUserId, video, isGroup: isGroupOffer));
        }
        break;
      case 'answer':
        final peer = _peers[env.fromUserId];
        await peer?.pc.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String, 'answer'));
        _setState(CallState.active);
        break;
      case 'ice':
        if (payload['candidate'] != null) {
          await _peers[env.fromUserId]?.pc.addCandidate(RTCIceCandidate(
            payload['candidate'] as String,
            payload['sdpMid'] as String?,
            payload['sdpMLineIndex'] as int?,
          ));
        }
        break;
      case 'mute_state':
        final peer = _peers[env.fromUserId];
        if (peer != null) {
          peer.muted = payload['muted'] as bool? ?? false;
          _participantsController.add(null);
        }
        break;
      case 'hangup':
        _peers.remove(env.fromUserId)?.pc.close();
        _participantsController.add(null);
        if (!_isGroup || _peers.isEmpty) await _reset();
        break;
    }
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(_statsPollInterval, (_) => _pollAudioLevels());
  }

  Future<void> _pollAudioLevels() async {
    var anyLocal = false;
    for (final entry in _peers.entries) {
      try {
        final reports = await entry.value.pc.getStats();
        var speaking = false;
        for (final report in reports) {
          if (report.type == 'inbound-rtp' && report.values['kind'] == 'audio') {
            final level = (report.values['audioLevel'] as num?)?.toDouble() ?? 0;
            if (level > _speakingThreshold) speaking = true;
          }
          if (report.type == 'media-source' && report.values['kind'] == 'audio') {
            final level = (report.values['audioLevel'] as num?)?.toDouble() ?? 0;
            if (level > _speakingThreshold) anyLocal = true;
          }
        }
        if (entry.value.speaking != speaking) {
          entry.value.speaking = speaking;
          _participantsController.add(null);
        }
      } catch (_) {

      }
    }
    if (_localSpeaking != anyLocal) {
      _localSpeaking = anyLocal;
      _participantsController.add(null);
    }
  }

  Future<void> _reset() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    for (final peer in _peers.values) {
      peer.remoteStream?.getTracks().forEach((t) => t.stop());
      await peer.pc.close();
    }
    _peers.clear();
    _localStream = null;
    _conversationId = null;
    _groupId = null;
    _myUserId = null;
    _isGroup = false;
    _localMuted = false;
    _localSpeaking = false;
    _setState(CallState.idle);
  }

  Future<void> setMuted(bool muted) async {
    _localMuted = muted;
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = !muted;
    }
    for (final peerUserId in _peers.keys) {
      await _sendSignalTo(peerUserId, {'kind': 'mute_state', 'muted': muted});
    }
  }
}
