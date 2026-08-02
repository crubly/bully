import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'keys.dart';

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

class RatchetSession {
  Uint8List _rootKey;
  X25519KeyPair _dhSelf;
  Uint8List? _dhRemote;
  Uint8List? _sendingChainKey;
  Uint8List? _receivingChainKey;
  int _ns = 0;
  int _nr = 0;
  int _pn = 0;

  // True only right after the symmetric init(), while _dhSelf is still the
  // long-term identity keypair rather than a fresh ephemeral. Cleared the
  // first time we receive something in that state, which triggers rotating
  // our OWN sending side to a fresh ephemeral — kicking off the normal
  // Double Ratchet forward-secrecy cascade from that point on, the same way
  // it always worked once a conversation had messages flowing both ways.
  bool _dhSelfIsIdentity = false;

  final Map<String, ({Uint8List messageKeyA, Uint8List messageKeyB})> _skippedKeys = {};

  static const _maxSkip = 1000;

  RatchetSession._(this._rootKey, this._dhSelf);

  /// Symmetric bootstrap: both sides call this identically, each with their
  /// own identity keypair and the other's identity public key. Both compute
  /// the SAME Diffie-Hellman value (that's what ECDH guarantees), then
  /// derive two INDEPENDENT chain keys from it — one per direction, picked
  /// by comparing the two public keys — so each side's message stream never
  /// overlaps the other's even though the underlying DH secret is shared.
  /// Unlike the old sender/receiver split, this means either side can send
  /// the very first message — nobody has to wait to be messaged first.
  static Future<RatchetSession> init({
    required Uint8List bootstrapSecret,
    required X25519KeyPair myIdentityKeyPair,
    required Uint8List peerIdentityPublicKey,
  }) async {
    final session = RatchetSession._(bootstrapSecret, myIdentityKeyPair);
    final dhOut = await X25519KeyPair.sharedSecret(
      privateKey: myIdentityKeyPair.keyPair,
      peerPublicKeyBytes: peerIdentityPublicKey,
    );
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 96);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(dhOut),
      nonce: bootstrapSecret,
      info: utf8.encode('bully-double-ratchet-root'),
    );
    final bytes = await derived.extractBytes();
    final rootKey = Uint8List.fromList(bytes.sublist(0, 32));
    final chainA = Uint8List.fromList(bytes.sublist(32, 64));
    final chainB = Uint8List.fromList(bytes.sublist(64, 96));

    final amFirst = _compareBytes(myIdentityKeyPair.publicKeyBytes, peerIdentityPublicKey) < 0;
    session._rootKey = rootKey;
    session._sendingChainKey = amFirst ? chainA : chainB;
    session._receivingChainKey = amFirst ? chainB : chainA;
    session._dhRemote = peerIdentityPublicKey;
    session._dhSelfIsIdentity = true;
    return session;
  }

  static int _compareBytes(Uint8List a, Uint8List b) {
    final len = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }

  // Messages are encrypted in a cascade: AES-256-GCM first, then the whole
  // box is wrapped again in ChaCha20-Poly1305 under an independently derived
  // key. Breaking the confidentiality/integrity would require breaking BOTH
  // ciphers, not just one.
  Future<RatchetMessage> encrypt(Uint8List plaintext) async {
    if (_sendingChainKey == null) {
      throw StateError('sending chain not initialized — call init() first');
    }
    final stepped = await _kdfChainKey(_sendingChainKey!);
    _sendingChainKey = stepped.chainKey;

    final header = _MessageHeader(_dhSelf.publicKeyBytes, _pn, _ns).encode();
    final innerBox = await AesGcm.with256bits().encrypt(plaintext, secretKey: SecretKey(stepped.messageKeyA), aad: header);
    final outerBox = await Chacha20.poly1305Aead().encrypt(
      innerBox.concatenation(),
      secretKey: SecretKey(stepped.messageKeyB),
      aad: header,
    );
    _ns++;
    return RatchetMessage(header, Uint8List.fromList(outerBox.concatenation()));
  }

  Future<Uint8List> decrypt(Uint8List headerBytes, Uint8List ciphertextWithNonceAndMac) async {
    final header = _MessageHeader.decode(headerBytes);

    if (_dhRemote == null || !_bytesEqual(_dhRemote!, header.dhPublicKey)) {

      await _skipMessageKeys(header.previousChainLength);
      await _dhRatchetStep(header.dhPublicKey);
    } else if (_dhSelfIsIdentity) {
      await _rotateOwnSendingChain();
    }

    final cached = _skippedKeys.remove('${base64Encode(header.dhPublicKey)}:${header.messageNumber}');
    ({Uint8List messageKeyA, Uint8List messageKeyB}) messageKeys;
    if (cached != null) {
      messageKeys = cached;
    } else {
      await _skipMessageKeys(header.messageNumber);
      final stepped = await _kdfChainKey(_receivingChainKey!);
      _receivingChainKey = stepped.chainKey;
      messageKeys = (messageKeyA: stepped.messageKeyA, messageKeyB: stepped.messageKeyB);
      _nr++;
    }

    final outerBox = SecretBox.fromConcatenation(ciphertextWithNonceAndMac, nonceLength: 12, macLength: 16);
    final innerBytes = await Chacha20.poly1305Aead().decrypt(outerBox, secretKey: SecretKey(messageKeys.messageKeyB), aad: headerBytes);
    final innerBox = SecretBox.fromConcatenation(Uint8List.fromList(innerBytes), nonceLength: 12, macLength: 16);
    final plaintext = await AesGcm.with256bits().decrypt(innerBox, secretKey: SecretKey(messageKeys.messageKeyA), aad: headerBytes);
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
      _skippedKeys['${base64Encode(_dhRemote!)}:$_nr'] = (messageKeyA: stepped.messageKeyA, messageKeyB: stepped.messageKeyB);
      _nr++;
    }
  }

  Future<void> _rotateOwnSendingChain() async {
    _dhSelfIsIdentity = false;
    _dhSelf = await X25519KeyPair.generate();
    final dhOut = await X25519KeyPair.sharedSecret(privateKey: _dhSelf.keyPair, peerPublicKeyBytes: _dhRemote!);
    final derived = await _kdfRootKey(_rootKey, dhOut);
    _rootKey = derived.rootKey;
    _sendingChainKey = derived.chainKey;
    _pn = _ns;
    _ns = 0;
  }

  Future<void> _dhRatchetStep(Uint8List newRemotePublicKey) async {
    _dhSelfIsIdentity = false;
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

  Future<({Uint8List chainKey, Uint8List messageKeyA, Uint8List messageKeyB})> _kdfChainKey(Uint8List chainKey) async {
    final hmac = Hmac.sha256();
    final nextChain = await hmac.calculateMac(utf8.encode('chain'), secretKey: SecretKey(chainKey));
    final messageKeyA = await hmac.calculateMac(utf8.encode('message-a'), secretKey: SecretKey(chainKey));
    final messageKeyB = await hmac.calculateMac(utf8.encode('message-b'), secretKey: SecretKey(chainKey));
    return (
      chainKey: Uint8List.fromList(nextChain.bytes),
      messageKeyA: Uint8List.fromList(messageKeyA.bytes),
      messageKeyB: Uint8List.fromList(messageKeyB.bytes),
    );
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

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
      'dhSelfIsIdentity': _dhSelfIsIdentity,
      'skipped': _skippedKeys.map((k, v) => MapEntry(k, {'a': base64Encode(v.messageKeyA), 'b': base64Encode(v.messageKeyB)})),
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
    session._dhSelfIsIdentity = json['dhSelfIsIdentity'] as bool? ?? false;
    final skipped = (json['skipped'] as Map<String, dynamic>?) ?? {};
    skipped.forEach((k, v) {
      final map = v as Map;
      session._skippedKeys[k] = (
        messageKeyA: Uint8List.fromList(base64Decode(map['a'] as String)),
        messageKeyB: Uint8List.fromList(base64Decode(map['b'] as String)),
      );
    });
    return session;
  }
}
