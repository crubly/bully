import 'dart:convert';
import 'dart:typed_data';

import '../network/api_client.dart';
import '../network/ws_client.dart';
import '../storage/secure_store.dart';
import 'double_ratchet.dart';
import 'kdf.dart';
import 'keys.dart';
import 'sender_keys.dart';

/// Wires Sender Keys group encryption on top of pairwise Double Ratchet
/// "direct" control channels used only to distribute each member's sender
/// key. See sender_keys.dart for the encryption scheme rationale.
///
/// Distribution channel: for every other member of the group, this device
/// maintains a private Double Ratchet session keyed by a synthetic,
/// order-independent conversation id (`group-kx:<groupId>:<userA>:<userB>`),
/// bootstrapped from the SAME passphrase the humans shared for the group.
/// Distribution messages travel as envelope type "direct" — the relay
/// forwards them point-to-point without persisting or checking conversation
/// membership (see backend/internal/relay), so the server never learns the
/// sender key.
class GroupSessionManager {
  final ApiClient api;
  final WsClient ws;
  final X25519KeyPair Function() identityKeyPair;
  final Map<String, SenderKeyState> _ownKeys = {}; // groupId -> own sender key
  final Map<String, Map<String, SenderKeyState>> _peerKeys = {}; // groupId -> senderId -> state
  final Map<String, RatchetSession> _kxSessions = {}; // synthetic id -> ratchet

  GroupSessionManager(this.api, this.ws, this.identityKeyPair);

  /// Deterministic, order-independent id so both members of the pair derive
  /// the same synthetic conversation id (and thus the same bootstrap
  /// secret) regardless of who initiates.
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
    // Whichever member sorts first always plays the DH "sender" role for
    // this pair, independent of who happens to distribute their key first.
    final iAmFirst = ([myUserId, otherUserId]..sort()).first == myUserId;
    final RatchetSession session;
    if (iAmFirst) {
      final bundle = await api.fetchKeyBundle(otherUserId);
      final peerPublicKey = base64Decode(bundle['signed_public_key'] as String);
      session = await RatchetSession.initAsSender(bootstrapSecret: bootstrapSecret, peerPublicKey: Uint8List.fromList(peerPublicKey));
    } else {
      session = await RatchetSession.initAsReceiver(bootstrapSecret: bootstrapSecret, myKeyPair: identityKeyPair());
    }
    _kxSessions[kxId] = session;
    await SecureStore.setBlob('ratchet:$kxId', jsonEncode(await session.toJson()));
    return session;
  }

  Future<void> _persistKx(String groupId, String myUserId, String otherUserId, RatchetSession session) async {
    final kxId = _kxId(groupId, myUserId, otherUserId);
    await SecureStore.setBlob('ratchet:$kxId', jsonEncode(await session.toJson()));
  }

  /// True once we have generated (or restored) our own sender key for the
  /// group — used to decide whether [rekeyAndDistribute] needs to run.
  Future<bool> hasPersistedOwnKey(String groupId) async => (await SecureStore.getBlob('senderkey-own:$groupId')) != null;

  /// Restores previously distributed sender keys (own + peers') from local
  /// storage, so re-opening a group doesn't require the passphrase again
  /// unless a brand-new pairwise session is needed.
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

  /// Generates (or rotates) this device's sender key for [groupId] and
  /// pushes it to every other member over their pairwise control channel.
  /// Call on first send in a group and again whenever membership changes
  /// (re-keying is what gives groups post-compromise security).
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

  /// Call for every inbound envelope with type "direct". Decrypts and
  /// stores the sender's key state for the group.
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
    // Mutates state's chain key/iteration in place, so persist afterwards.
    final result = await SenderKeyCipher.encrypt(state, Uint8List.fromList(utf8.encode(plaintext)));
    await _persistOwnKey(groupId, state);
    return result;
  }

  Future<String?> decrypt(String groupId, String senderId, int iteration, Uint8List ciphertext) async {
    final state = _peerKeys[groupId]?[senderId];
    if (state == null) return null; // sender key not yet received — message undecryptable until it arrives
    final plaintext = await SenderKeyCipher.decrypt(state, iteration, ciphertext);
    await _persistPeerKey(groupId, senderId, state);
    return utf8.decode(plaintext);
  }

  bool hasOwnKey(String groupId) => _ownKeys.containsKey(groupId);
}
