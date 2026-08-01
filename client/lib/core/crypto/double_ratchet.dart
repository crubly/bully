import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'keys.dart';

/// A message ready to send over the relay. [header] is NOT secret (it only
/// carries the current ratchet public key and counters needed for the
/// receiver to derive the same message key) — the server stores/relays it
/// verbatim alongside [ciphertext] without being able to read either.
class RatchetMessage {
  final Uint8List header;
  final Uint8List ciphertext;
  RatchetMessage(this.header, this.ciphertext);
}

class _MessageHeader {
  final Uint8List dhPublicKey;
  final int previousChainLength;
  final int messageNumber;
  _MessageHeader(this.dhPublicKey, this.previousChainLength, this.messageNumber);

  Uint8List encode() {
    final map = {
      'dh': base64Encode(dhPublicKey),
      'pn': previousChainLength,
      'n': messageNumber,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  static _MessageHeader decode(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return _MessageHeader(base64Decode(map['dh'] as String), map['pn'] as int, map['n'] as int);
  }
}

/// Signal-style Double Ratchet: a DH ratchet (X25519) mixed with a symmetric
/// KDF chain (HMAC-SHA256) per message. Gives forward secrecy (past message
/// keys are unrecoverable from later state) and post-compromise security
/// (a fresh DH ratchet step heals the session even if a prior state leaked).
class RatchetSession {
  Uint8List _rootKey;
  X25519KeyPair _dhSelf;
  Uint8List? _dhRemote;
  Uint8List? _sendingChainKey;
  Uint8List? _receivingChainKey;
  int _ns = 0;
  int _nr = 0;
  int _pn = 0;

  /// Skipped message keys, keyed by "base64(dhRemote):n", to handle
  /// out-of-order delivery over the relay.
  final Map<String, Uint8List> _skippedKeys = {};

  static const _maxSkip = 1000;

  RatchetSession._(this._rootKey, this._dhSelf);

  /// The side that creates the conversation (has the peer's public key
  /// available immediately) calls this to bootstrap as the "sender".
  static Future<RatchetSession> initAsSender({
    required Uint8List bootstrapSecret,
    required Uint8List peerPublicKey,
  }) async {
    final dhSelf = await X25519KeyPair.generate();
    final dhOut = await X25519KeyPair.sharedSecret(privateKey: dhSelf.keyPair, peerPublicKeyBytes: peerPublicKey);
    final session = RatchetSession._(bootstrapSecret, dhSelf);
    final derived = await session._kdfRootKey(session._rootKey, dhOut);
    session._rootKey = derived.rootKey;
    session._sendingChainKey = derived.chainKey;
    session._dhRemote = peerPublicKey;
    return session;
  }

  /// The receiving side bootstraps without an immediate DH ratchet step;
  /// it derives the matching receiving chain key on the first inbound
  /// message once it learns the sender's ratchet public key from the header.
  static Future<RatchetSession> initAsReceiver({
    required Uint8List bootstrapSecret,
    required X25519KeyPair myKeyPair,
  }) async {
    return RatchetSession._(bootstrapSecret, myKeyPair);
  }

  Future<RatchetMessage> encrypt(Uint8List plaintext) async {
    if (_sendingChainKey == null) {
      throw StateError('sending chain not initialized — call initAsSender or receive a message first');
    }
    final stepped = await _kdfChainKey(_sendingChainKey!);
    _sendingChainKey = stepped.chainKey;

    final header = _MessageHeader(_dhSelf.publicKeyBytes, _pn, _ns).encode();
    final aead = AesGcm.with256bits();
    final secretKey = SecretKey(stepped.messageKey);
    final box = await aead.encrypt(plaintext, secretKey: secretKey, aad: header);
    _ns++;
    return RatchetMessage(header, Uint8List.fromList(box.concatenation()));
  }

  Future<Uint8List> decrypt(Uint8List headerBytes, Uint8List ciphertextWithNonceAndMac) async {
    final header = _MessageHeader.decode(headerBytes);

    if (_dhRemote == null || !_bytesEqual(_dhRemote!, header.dhPublicKey)) {
      // New DH ratchet public key from peer -> perform a DH ratchet step
      // (this is what gives post-compromise security: the session heals).
      await _skipMessageKeys(header.previousChainLength);
      await _dhRatchetStep(header.dhPublicKey);
    }

    final cached = _skippedKeys.remove('${base64Encode(header.dhPublicKey)}:${header.messageNumber}');
    Uint8List messageKey;
    if (cached != null) {
      messageKey = cached;
    } else {
      await _skipMessageKeys(header.messageNumber);
      final stepped = await _kdfChainKey(_receivingChainKey!);
      _receivingChainKey = stepped.chainKey;
      messageKey = stepped.messageKey;
      _nr++;
    }

    final aead = AesGcm.with256bits();
    final box = SecretBox.fromConcatenation(ciphertextWithNonceAndMac, nonceLength: 12, macLength: 16);
    final plaintext = await aead.decrypt(box, secretKey: SecretKey(messageKey), aad: headerBytes);
    return Uint8List.fromList(plaintext);
  }

  Future<void> _skipMessageKeys(int until) async {
    if (_receivingChainKey == null) return;
    if (_nr + _maxSkip < until) {
      throw StateError('too many skipped messages');
    }
    while (_nr < until) {
      final stepped = await _kdfChainKey(_receivingChainKey!);
      _receivingChainKey = stepped.chainKey;
      _skippedKeys['${base64Encode(_dhRemote!)}:$_nr'] = stepped.messageKey;
      _nr++;
    }
  }

  Future<void> _dhRatchetStep(Uint8List newRemotePublicKey) async {
    _pn = _ns;
    _ns = 0;
    _nr = 0;
    _dhRemote = newRemotePublicKey;

    final dhOut1 = await X25519KeyPair.sharedSecret(privateKey: _dhSelf.keyPair, peerPublicKeyBytes: newRemotePublicKey);
    final derived1 = await _kdfRootKey(_rootKey, dhOut1);
    _rootKey = derived1.rootKey;
    _receivingChainKey = derived1.chainKey;

    _dhSelf = await X25519KeyPair.generate();
    final dhOut2 = await X25519KeyPair.sharedSecret(privateKey: _dhSelf.keyPair, peerPublicKeyBytes: newRemotePublicKey);
    final derived2 = await _kdfRootKey(_rootKey, dhOut2);
    _rootKey = derived2.rootKey;
    _sendingChainKey = derived2.chainKey;
  }

  Future<({Uint8List rootKey, Uint8List chainKey})> _kdfRootKey(Uint8List rootKey, Uint8List dhOut) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(dhOut),
      nonce: rootKey,
      info: utf8.encode('bully-double-ratchet-root'),
    );
    final bytes = await derived.extractBytes();
    return (rootKey: Uint8List.fromList(bytes.sublist(0, 32)), chainKey: Uint8List.fromList(bytes.sublist(32, 64)));
  }

  Future<({Uint8List chainKey, Uint8List messageKey})> _kdfChainKey(Uint8List chainKey) async {
    final hmac = Hmac.sha256();
    final nextChain = await hmac.calculateMac(utf8.encode('chain'), secretKey: SecretKey(chainKey));
    final messageKey = await hmac.calculateMac(utf8.encode('message'), secretKey: SecretKey(chainKey));
    return (chainKey: Uint8List.fromList(nextChain.bytes), messageKey: Uint8List.fromList(messageKey.bytes));
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Serializes full session state for local secure storage so a
  /// conversation survives app restarts. This never leaves the device.
  Future<Map<String, dynamic>> toJson() async {
    final keyPairData = await _dhSelf.keyPair.extractPrivateKeyBytes();
    return {
      'rootKey': base64Encode(_rootKey),
      'dhSelfPrivate': base64Encode(keyPairData),
      'dhSelfPublic': base64Encode(_dhSelf.publicKeyBytes),
      'dhRemote': _dhRemote != null ? base64Encode(_dhRemote!) : null,
      'sendingChainKey': _sendingChainKey != null ? base64Encode(_sendingChainKey!) : null,
      'receivingChainKey': _receivingChainKey != null ? base64Encode(_receivingChainKey!) : null,
      'ns': _ns,
      'nr': _nr,
      'pn': _pn,
      'skipped': _skippedKeys.map((k, v) => MapEntry(k, base64Encode(v))),
    };
  }

  static Future<RatchetSession> fromJson(Map<String, dynamic> json) async {
    final privBytes = base64Decode(json['dhSelfPrivate'] as String);
    final pubBytes = base64Decode(json['dhSelfPublic'] as String);
    final keyPair = SimpleKeyPairData(privBytes, publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519), type: KeyPairType.x25519);
    final dhSelf = X25519KeyPair.fromExisting(keyPair, Uint8List.fromList(pubBytes));

    final session = RatchetSession._(base64Decode(json['rootKey'] as String), dhSelf);
    session._dhRemote = json['dhRemote'] != null ? base64Decode(json['dhRemote'] as String) : null;
    session._sendingChainKey = json['sendingChainKey'] != null ? base64Decode(json['sendingChainKey'] as String) : null;
    session._receivingChainKey = json['receivingChainKey'] != null ? base64Decode(json['receivingChainKey'] as String) : null;
    session._ns = json['ns'] as int;
    session._nr = json['nr'] as int;
    session._pn = json['pn'] as int;
    final skipped = (json['skipped'] as Map<String, dynamic>?) ?? {};
    skipped.forEach((k, v) => session._skippedKeys[k] = base64Decode(v as String));
    return session;
  }
}
