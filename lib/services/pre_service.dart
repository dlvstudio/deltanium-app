import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/services/pre_ffi.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:deltanium_app/services/crypto_service.dart';

class PreService {
  /// Fetch a short-lived transform token (proxy mode) from Central API
  Future<String?> fetchTransformToken(
    String apiBaseUrl,
    String followerPubKey,
    String followingPubKey,
    String policyTag,
    String mnemonic, {
    String? fileId,
  }) async {
    try {
      // 1) Get PoP nonce (expects userPubKey in query)
      final nonceResp = await http.get(Uri.parse('$apiBaseUrl/policy/nonce?userPubKey=$followerPubKey'));
      if (nonceResp.statusCode != 200) return null;
      final nonce = (json.decode(nonceResp.body) as Map<String, dynamic>)['nonce'] as String?;
      if (nonce == null || nonce.isEmpty) return null;

      // 2) Sign nonce with follower's key
      final popSignature = await CryptoService.sign(nonce, mnemonic);

      // 3) Request token (proxy mode) with signed headers
      final method = 'POST';
      final pathForUrl = '/policy/fetch-rekey';
      final pathForSign = '/api/policy/fetch-rekey';
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final bodyJson = json.encode({
        'followerPubKey': followerPubKey,
        'followingPubKey': followingPubKey,
        'tag': policyTag,
        'mode': 'proxy',
        if (fileId != null) 'fileId': fileId,
        'proof': {
          'nonce': nonce,
          'signature': popSignature,
        }
      });
      final bodyHash = base64Encode(utf8.encode(bodyJson));
      final sig = await CryptoService.sign('$method$pathForSign$ts$bodyHash', mnemonic);

      final resp = await http.post(
        Uri.parse('$apiBaseUrl$pathForUrl'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': followerPubKey,
          'X-Timestamp': ts,
          'X-Signature': sig,
        },
        body: bodyJson,
      );
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      return data['token'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Ask the Store to re-encrypt the PRE bundle for the follower (proxy mode)
  Future<Uint8List?> requestProxyReencrypt(
    String nodeEndpoint,
    String fileId,
    String policyTag,
    String token,
    String followerPubKey,
    String mnemonic,
  ) async {
    try {
      final method = 'POST';
      final path = '/api/file/pre/reencrypt';
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final body = json.encode({'fileId': fileId, 'policyTag': policyTag, 'token': token});
      final bodyHash = base64Encode(utf8.encode(body));
      final dataToSign = '$method$path$ts$bodyHash';
      final signature = await CryptoService.sign(dataToSign, mnemonic);

      final resp = await http.post(
        Uri.parse('$nodeEndpoint$path'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': followerPubKey,
          'X-Timestamp': ts,
          'X-Signature': signature,
        },
        body: body,
      );
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final b64 = data['encryptedKeyForB'] as String? ?? data['EncryptedKeyForB'] as String?; // handle casing
      if (b64 == null || b64.isEmpty) return null;
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Decapsulate PRE re-encrypted bundle to recover symmetric key K
  Future<Uint8List?> decapsulateAndRecoverKey(Uint8List reencryptedBundle, String mnemonic, {required String policyTag}) async {
    try {
      // Derive sk_B: seed = BIP39.mnemonicToSeed(mnemonic), sk = sha256(seed)
      final seed = bip39.mnemonicToSeed(mnemonic);
      final seedHash = await CryptoService.hashSHA256(Uint8List.fromList(seed));
      final sk = seedHash; // 32-byte private key material
      final pre = PreFfi.instance();
      final key = pre.decapsulateForRecipient(
        encapsulatedForRecipient: reencryptedBundle,
        skRecipient: sk,
        tag: policyTag,
      );
      return key.isEmpty ? null : key;
    } catch (e) {
      return null;
    }
  }

  /// Build policy tag for current year
  String buildPolicyTagForYear([int? year]) {
    final y = year ?? DateTime.now().year;
    return 'followers:$y';
  }

  /// Extract author's public key (pkA bytes) from PRE bundle (length-prefixed format)
  /// Format: [u32 cap_len][cap][u32 ct_len][ct][u32 pkA_len][pkA] ...
  Uint8List? extractAuthorPkFromBundle(Uint8List bundle) {
    if (bundle.length < 12) return null;
    int offset = 0;
    int readU32() {
      if (offset + 4 > bundle.length) return -1;
      final v = (bundle[offset] << 24) | (bundle[offset + 1] << 16) | (bundle[offset + 2] << 8) | (bundle[offset + 3]);
      offset += 4;
      return v;
    }
    int capLen = readU32();
    if (capLen < 0 || offset + capLen > bundle.length) return null;
    offset += capLen;
    int ctLen = readU32();
    if (ctLen < 0 || offset + ctLen > bundle.length) return null;
    offset += ctLen;
    int pkLen = readU32();
    if (pkLen < 0 || offset + pkLen > bundle.length) return null;
    return Uint8List.fromList(bundle.sublist(offset, offset + pkLen));
  }

  String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Client-transform fallback: fetch rk (mode=client) and reencrypt locally via FFI
  Future<Uint8List?> clientTransform({
    required String apiBaseUrl,
    required Uint8List bundleForAuthor,
    required String followerPubKey,
    required String mnemonic,
    required String policyTag,
  }) async {
    try {
      final pkABytes = extractAuthorPkFromBundle(bundleForAuthor);
      if (pkABytes == null || pkABytes.isEmpty) return null;
      final pkAHex = _bytesToHex(pkABytes);

      // PoP (nonce requires userPubKey)
      final nonceResp = await http.get(Uri.parse('$apiBaseUrl/policy/nonce?userPubKey=$followerPubKey'));
      if (nonceResp.statusCode != 200) return null;
      final nonce = (json.decode(nonceResp.body) as Map<String, dynamic>)['nonce'] as String?;
      if (nonce == null || nonce.isEmpty) return null;
      final popSignature = await CryptoService.sign(nonce, mnemonic);

      // Request rk (client mode) with signed headers
      final method = 'POST';
      final pathForUrl = '/policy/fetch-rekey';
      final pathForSign = '/api/policy/fetch-rekey';
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final bodyJson = json.encode({
        'followerPubKey': followerPubKey,
        'followingPubKey': pkAHex,
        'tag': policyTag,
        'mode': 'client',
        'proof': { 'nonce': nonce, 'signature': popSignature }
      });
      final bodyHash = base64Encode(utf8.encode(bodyJson));
      final sig = await CryptoService.sign('$method$pathForSign$ts$bodyHash', mnemonic);
      final resp = await http.post(
        Uri.parse('$apiBaseUrl$pathForUrl'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': followerPubKey,
          'X-Timestamp': ts,
          'X-Signature': sig,
        },
        body: bodyJson,
      );
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final rkB64 = data['rekey'] as String?;
      if (rkB64 == null || rkB64.isEmpty) return null;
      final rk = base64Decode(rkB64);

      // Local transform
      final pre = PreFfi.instance();
      final transformed = pre.reencrypt(encapsulatedForAuthor: bundleForAuthor, rekey: rk);
      return transformed.isEmpty ? null : transformed;
    } catch (_) {
      return null;
    }
  }

  /// Author publishes intent to use a tag
  Future<bool> publishTag({
    required String apiBaseUrl,
    required String authorPubKey,
    required String mnemonic,
    required String tag,
    String policyScheme = 'CPRE',
  }) async {
    try {
      final method = 'POST';
      final pathForUrl = '/policy/publish-tag';
      final pathForSign = '/api/policy/publish-tag';
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final bodyJson = json.encode({'tag': tag, 'policyScheme': policyScheme, 'authorPubKey': authorPubKey});
      final bodyHash = base64Encode(utf8.encode(bodyJson));
      final signature = await CryptoService.sign('$method$pathForSign$ts$bodyHash', mnemonic);
      final resp = await http.post(
        Uri.parse('$apiBaseUrl$pathForUrl'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': authorPubKey,
          'X-Timestamp': ts,
          'X-Signature': signature,
        },
        body: bodyJson,
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Author uploads re-encryption key rk for a follower
  Future<bool> uploadRekey({
    required String apiBaseUrl,
    required String authorPubKey,
    required String followerPubKey,
    required String mnemonic,
    required String tag,
    required String rkBase64,
    String? scope,
    String? fileId,
  }) async {
    try {
      final method = 'POST';
      final pathForUrl = '/policy/upload-rekey';
      final pathForSign = '/api/policy/upload-rekey';
      final ts = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
      final payload = {
        'authorPubKey': authorPubKey,
        'followerPubKey': followerPubKey,
        'tag': tag,
        'rk': rkBase64,
        if (scope != null) 'scope': scope,
        if (fileId != null) 'fileId': fileId,
      };
      final bodyJson = json.encode(payload);
      final bodyHash = base64Encode(utf8.encode(bodyJson));
      final signature = await CryptoService.sign('$method$pathForSign$ts$bodyHash', mnemonic);
      final resp = await http.post(
        Uri.parse('$apiBaseUrl$pathForUrl'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': authorPubKey,
          'X-Timestamp': ts,
          'X-Signature': signature,
        },
        body: bodyJson,
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Generate rk for each follower and upload to Central API
  Future<Map<String, bool>> generateAndUploadRekeys({
    required String apiBaseUrl,
    required String authorPubKey,
    required String mnemonic,
    required List<String> followerPubKeys,
    required String tag,
    String? scope,
    String? fileId,
  }) async {
    final results = <String, bool>{};
    try {
      // Publish tag (best-effort)
      await publishTag(apiBaseUrl: apiBaseUrl, authorPubKey: authorPubKey, mnemonic: mnemonic, tag: tag);

      // Derive sk_A
      final seed = bip39.mnemonicToSeed(mnemonic);
      final skA = await CryptoService.hashSHA256(Uint8List.fromList(seed));
      final pre = PreFfi.instance();

      // Ensure author can also access their own PRE posts via proxy transform (rk A->A)
      final targetRecipients = <String>{...followerPubKeys, authorPubKey};
      for (final pkBHex in targetRecipients) {
        try {
          final pkB = _hexToBytes(pkBHex);
          final rk = pre.generateRekey(skAuthor: skA, pkRecipient: pkB, tag: tag);
          final rkB64 = base64Encode(rk);
          final ok = await uploadRekey(
            apiBaseUrl: apiBaseUrl,
            authorPubKey: authorPubKey,
            followerPubKey: pkBHex,
            mnemonic: mnemonic,
            tag: tag,
            rkBase64: rkB64,
            scope: scope,
            fileId: fileId,
          );
          results[pkBHex] = ok;
        } catch (e) {
          results[pkBHex] = false;
        }
      }
    } catch (_) {
      for (final pk in followerPubKeys) {
        results[pk] = false;
      }
    }
    return results;
  }

  // Hex to bytes helper
  Uint8List _hexToBytes(String hex) {
    final s = hex.trim();
    final len = s.length;
    final out = Uint8List(len ~/ 2);
    for (int i = 0; i < len; i += 2) {
      out[i >> 1] = int.parse(s.substring(i, i + 2), radix: 16);
    }
    return out;
  }
}


