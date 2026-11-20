import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:deltanium_app/config/network.dart';
import 'package:pointycastle/export.dart';

/// Node identity on a DLTP connection to an IP address (no domain, so no CA certificate).
///
/// The node serves TLS with a self-signed certificate. Asked with a HELLO frame it answers with its public key
/// (X-Node-PubKey) and a signature by that key (X-Node-Proof, base64 DER) over
/// `Network.scope("DLTP-ID|" + sha256hex(certificate DER))`. The app hashes the certificate it actually
/// received, so the proof only checks out when the node that holds the registered key also holds this TLS
/// certificate: nobody in between can relay it.
class NodeProof {
  NodeProof._();

  static String certHash(List<int> der) => crypto.sha256.convert(der).toString();

  static String message(String certSha256Hex) => Network.scope('DLTP-ID|${certSha256Hex.toLowerCase()}');

  /// True when [proofBase64] is [expectedPublicKey]'s signature over this certificate.
  static bool verify({
    required String expectedPublicKey,
    required String? presentedPublicKey,
    required String? proofBase64,
    required List<int> certificateDer,
  }) {
    if (presentedPublicKey == null || proofBase64 == null) return false;
    if (presentedPublicKey.trim().toLowerCase() != expectedPublicKey.trim().toLowerCase()) return false;
    try {
      final domain = ECDomainParameters('secp256k1');
      final point = domain.curve.decodePoint(_hex(expectedPublicKey.trim()));
      if (point == null) return false;
      final sig = _parseDer(base64.decode(proofBase64));
      if (sig == null) return false;
      final signer = Signer('SHA-256/ECDSA')
        ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(point, domain)));
      final msg = Uint8List.fromList(utf8.encode(message(certHash(certificateDer))));
      return signer.verifySignature(msg, sig);
    } catch (_) {
      return false;
    }
  }

  static Uint8List _hex(String h) =>
      Uint8List.fromList(List.generate(h.length ~/ 2, (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16)));

  /// DER `SEQUENCE { INTEGER r, INTEGER s }`.
  static ECSignature? _parseDer(List<int> d) {
    var i = 0;
    if (d.length < 8 || d[i++] != 0x30) return null;
    var len = d[i++];
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | d[i++];
      }
    }
    BigInt? readInt() {
      if (d[i++] != 0x02) return null;
      final l = d[i++];
      final v = d.sublist(i, i + l);
      i += l;
      return v.fold<BigInt>(BigInt.zero, (a, b) => (a << 8) | BigInt.from(b));
    }

    final r = readInt();
    final s = readInt();
    if (r == null || s == null) return null;
    return ECSignature(r, s);
  }
}
