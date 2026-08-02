import 'dart:convert';
import 'dart:typed_data';

import '../network/api_client.dart';
import '../network/ws_client.dart';
import '../storage/secure_store.dart';
import 'double_ratchet.dart';
import 'kdf.dart';
import 'keys.dart';
import 'security/peer_identity_store.dart';
import 'sender_keys.dart';

class GroupSessionManager {
  final ApiClient api;
  final WsClient ws;
  final X25519KeyPair Function() identityKeyPair;
  final Map<String, SenderKeyState> _ownKeys = {};
  final Map<String, Map<String, SenderKeyState>> _peerKeys = {};
  final Map<String, RatchetSession> _kxSessions = {};

  GroupSessionManager(this.api, this.ws, this.identityKeyPair);

  String _kxId(String groupId, String userA, String userB) {
    final sorted = [userA, userB]..sort();
    return 'group-kx:$groupId:${sorted[0]}:${sorted[1]}';
  }

  Future<RatchetSession> _ensureKx(String groupId, String myUserId, String otherUserId, String passphrase) async {
    final kxId = _kxId(groupId, myUserId, otherUserId);
    final cached = _kxSessions[kxId];
    if (cached != null) return cached;

    final stored = await SecureStore.getBlob('ratchet:$kxId');
    if (stored != null) {
      final session = await RatchetSession.fromJson(jsonDecode(stored) as Map<String, dynamic>);
      _kxSessions[kxId] = session;
      return session;
    }

    final bootstrapSecret = await PassphraseKdf.deriveBootstrapSecret(passphrase, kxId);

    final bundle = await api.fetchKeyBundle(otherUserId);
    final peerPublicKey = Uint8List.fromList(base64Decode(bundle['signed_public_key'] as String));
    await PeerIdentityStore.checkOrPin(otherUserId, peerPublicKey);

    final session = await RatchetSession.init(
      bootstrapSecret: bootstrapSecret,
      myIdentityKeyPair: identityKeyPair(),
      peerIdentityPublicKey: peerPublicKey,
    );
    _kxSessions[kxId] = session;
    await SecureStore.setBlob('ratchet:$kxId', jsonEncode(await session.toJson()));
    return session;
  }

  Future<void> _persistKx(String groupId, String myUserId, String otherUserId, RatchetSession session) async {
    final kxId = _kxId(groupId, myUserId, otherUserId);
    await SecureStore.setBlob('ratchet:$kxId', jsonEncode(await session.toJson()));
  }

  Future<RatchetSession> _loadExistingKx(String groupId, String myUserId, String otherUserId) async {
    final kxId = _kxId(groupId, myUserId, otherUserId);
    final cached = _kxSessions[kxId];
    if (cached != null) return cached;
    final stored = await SecureStore.getBlob('ratchet:$kxId');
    if (stored == null) {
      throw StateError('no key-exchange session with $otherUserId in group $groupId yet — message them in the group chat first');
    }
    final session = await RatchetSession.fromJson(jsonDecode(stored) as Map<String, dynamic>);
    _kxSessions[kxId] = session;
    return session;
  }

  /// Call signaling (offer/answer/ice/mute) between two members of a group
  /// call is end-to-end encrypted through the SAME pairwise key-exchange
  /// ratchet already established for sender-key distribution — no separate
  /// passphrase prompt needed as long as the two have exchanged at least
  /// one group message/rekey before (which a call between existing chat
  /// members already implies).
  Future<RatchetMessage> encryptForCall({required String groupId, required String myUserId, required String otherUserId, required String plaintext}) async {
    final session = await _loadExistingKx(groupId, myUserId, otherUserId);
    final message = await session.encrypt(Uint8List.fromList(utf8.encode(plaintext)));
    await _persistKx(groupId, myUserId, otherUserId, session);
    return message;
  }

  Future<String> decryptForCall({required String groupId, required String myUserId, required String otherUserId, required Uint8List header, required Uint8List ciphertext}) async {
    final session = await _loadExistingKx(groupId, myUserId, otherUserId);
    final plaintext = await session.decrypt(header, ciphertext);
    await _persistKx(groupId, myUserId, otherUserId, session);
    return utf8.decode(plaintext);
  }

  Future<bool> hasPersistedOwnKey(String groupId) async => (await SecureStore.getBlob('senderkey-own:$groupId')) != null;

  Future<void> restore(String groupId, List<String> memberIds) async {
    final ownRaw = await SecureStore.getBlob('senderkey-own:$groupId');
    if (ownRaw != null) {
      _ownKeys[groupId] = SenderKeyState.fromDistributionMessage(jsonDecode(ownRaw) as Map<String, dynamic>);
    }
    for (final memberId in memberIds) {
      final raw = await SecureStore.getBlob('senderkey-peer:$groupId:$memberId');
      if (raw != null) {
        _peerKeys.putIfAbsent(groupId, () => {})[memberId] =
            SenderKeyState.fromDistributionMessage(jsonDecode(raw) as Map<String, dynamic>);
      }
    }
  }

  Future<void> _persistOwnKey(String groupId, SenderKeyState state) =>
      SecureStore.setBlob('senderkey-own:$groupId', jsonEncode(state.toDistributionMessage()));

  Future<void> _persistPeerKey(String groupId, String senderId, SenderKeyState state) =>
      SecureStore.setBlob('senderkey-peer:$groupId:$senderId', jsonEncode(state.toDistributionMessage()));

  Future<void> rekeyAndDistribute({
    required String groupId,
    required String myUserId,
    required List<String> otherMemberIds,
    required String passphrase,
  }) async {
    final state = await SenderKeyState.generate();
    _ownKeys[groupId] = state;
    await _persistOwnKey(groupId, state);

    for (final otherUserId in otherMemberIds) {
      final session = await _ensureKx(groupId, myUserId, otherUserId, passphrase);
      final payload = utf8.encode(jsonEncode({
        'group_id': groupId,
        ...state.toDistributionMessage(),
      }));
      final message = await session.encrypt(Uint8List.fromList(payload));
      await _persistKx(groupId, myUserId, otherUserId, session);

      ws.send(RelayEnvelope(
        type: 'direct',
        conversationId: _kxId(groupId, myUserId, otherUserId),
        fromUserId: myUserId,
        toUserId: otherUserId,
        ciphertext: base64Encode(message.ciphertext),
        header: base64Encode(message.header),
      ));
    }
  }

  Future<void> handleDistribution({
    required String groupId,
    required String fromUserId,
    required String myUserId,
    required Uint8List header,
    required Uint8List ciphertext,
    required String passphrase,
  }) async {
    final session = await _ensureKx(groupId, myUserId, fromUserId, passphrase);
    final plaintext = await session.decrypt(header, ciphertext);
    await _persistKx(groupId, myUserId, fromUserId, session);

    final map = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    final state = SenderKeyState.fromDistributionMessage(map);
    _peerKeys.putIfAbsent(groupId, () => {})[fromUserId] = state;
    await _persistPeerKey(groupId, fromUserId, state);
  }

  Future<GroupCiphertext> encrypt(String groupId, String plaintext) async {
    final state = _ownKeys[groupId];
    if (state == null) {
      throw StateError('no own sender key for group $groupId — call rekeyAndDistribute first');
    }

    final result = await SenderKeyCipher.encrypt(state, Uint8List.fromList(utf8.encode(plaintext)));
    await _persistOwnKey(groupId, state);
    return result;
  }

  Future<String?> decrypt(String groupId, String senderId, int iteration, Uint8List ciphertext) async {
    final state = _peerKeys[groupId]?[senderId];
    if (state == null) return null;
    final plaintext = await SenderKeyCipher.decrypt(state, iteration, ciphertext);
    await _persistPeerKey(groupId, senderId, state);
    return utf8.decode(plaintext);
  }

  bool hasOwnKey(String groupId) => _ownKeys.containsKey(groupId);

  /// Call after importing a device-transfer snapshot alongside
  /// CryptoSessionManager.reloadAfterTransfer() — any group key-exchange
  /// session cached in memory was established under this device's
  /// now-discarded identity and must be re-derived from the transferred
  /// state on disk instead.
  void clearCaches() {
    _kxSessions.clear();
    _ownKeys.clear();
    _peerKeys.clear();
  }
}
