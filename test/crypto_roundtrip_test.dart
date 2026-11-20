// Offline round trips through the app's own crypto code: file encryption (webcrypto) and Umbral PRE.
// They need native libraries, so they run only where those are installed:
//   DELTANIUM_NATIVE_CRYPTO=1  after `dart run webcrypto:setup`
//   DELTANIUM_UMBRAL=1         with libumbral_pre on the library path (LD_LIBRARY_PATH on Linux)
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart' as crypto;
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/services/pre_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Who {
  final String mnemonic;
  final String publicKey;
  _Who(this.mnemonic) : publicKey = CryptoService.getPublicKeyHex(CryptoService.generateKeyPairFromMnemonic(mnemonic));
  Uint8List get preSecret => Uint8List.fromList(crypto.sha256.convert(bip39.mnemonicToSeed(mnemonic)).bytes);
  Uint8List get publicKeyBytes =>
      Uint8List.fromList([for (var i = 0; i < publicKey.length; i += 2) int.parse(publicKey.substring(i, i + 2), radix: 16)]);
}

Uint8List _randomBytes(int n, [int seed = 7]) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

/// Reads a file the way the app does: block 0 (metadata) with the reader's entry, then the content blocks.
Future<Uint8List> _decryptAs(_Who reader, Map<String, dynamic> encrypted) async {
  final entries = (encrypted['metadataEntries'] as List).cast<Map<String, dynamic>>();
  final blocks = (encrypted['blocks'] as List).cast<Map<String, dynamic>>();
  final entry = entries.firstWhere(
    (e) => CryptoService.normalizePublicKey((e['recipientPubKey'] ?? '') as String) == CryptoService.normalizePublicKey(reader.publicKey),
    orElse: () => entries.first,
  );
  Uint8List blockBytes(String id) => blocks.firstWhere((b) => b['blockId'] == id)['encryptedContent'] as Uint8List;
  final storeMetadata = {
    'fileId': entry['fileId'],
    'ownerPubKey': entry['ownerPubKey'] ?? '',
    'encryptedKey': entry['encryptedKey'] ?? '',
    'recipientPubKey': entry['recipientPubKey'] ?? '',
  };
  final meta = await FileCryptoService.decryptMetadataBlock(
    storeMetadata: storeMetadata,
    encryptedMetadataBlock: blockBytes(entry['firstBlockId'] as String),
    userPublicKey: (entry['recipientPubKey'] ?? reader.publicKey) as String,
    mnemonic: reader.mnemonic,
  );
  final ids = (meta['contentBlockIds'] as List).cast<String>();
  return FileCryptoService.decryptFile(
    fileMetadata: {...storeMetadata, 'fileSize': int.parse(meta['fileSize'].toString())},
    encryptedBlocks: [for (final id in ids) blockBytes(id)],
    userPublicKey: CryptoService.normalizePublicKey(reader.publicKey),
    mnemonic: reader.mnemonic,
  );
}

void main() {
  final nativeCrypto = Platform.environment['DELTANIUM_NATIVE_CRYPTO'] == '1';
  final umbral = Platform.environment['DELTANIUM_UMBRAL'] == '1';
  final a = _Who(bip39.generateMnemonic());
  final b = _Who(bip39.generateMnemonic());
  final c = _Who(bip39.generateMnemonic());

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('file encryption', () {
    test('a private image (several blocks) decrypts back to the same bytes for its owner', () async {
      final image = _randomBytes(9 * 1024 * 1024); // more than two 4 MB blocks
      final enc = await FileCryptoService.encryptAndSplitFile(
        fileData: image,
        fileName: 'qa-photo.jpg',
        ownerPublicKey: a.publicKey,
        mnemonic: a.mnemonic,
        fileType: 'file',
        shareType: 'me',
      );
      expect((enc['blocks'] as List).length, greaterThan(2), reason: 'metadata block + content blocks');
      final back = await _decryptAs(a, enc);
      expect(crypto.sha256.convert(back), crypto.sha256.convert(image));
    });

    test('a file shared with B decrypts for B, and not for C', () async {
      final doc = _randomBytes(48 * 1024, 11);
      final enc = await FileCryptoService.encryptAndSplitFile(
        fileData: doc,
        fileName: 'qa-doc.pdf',
        ownerPublicKey: a.publicKey,
        mnemonic: a.mnemonic,
        sharedWithPublicKeys: [b.publicKey],
        fileType: 'file',
        shareType: 'shared',
      );
      expect(crypto.sha256.convert(await _decryptAs(b, enc)), crypto.sha256.convert(doc));
      await expectLater(_decryptAs(c, enc), throwsA(anything));
    });

    test('a public file is readable without the owner key', () async {
      final pic = _randomBytes(64 * 1024, 3);
      final enc = await FileCryptoService.createPublicFile(
        fileData: pic,
        fileName: 'qa-public.png',
        ownerPublicKey: a.publicKey,
        fileType: 'file',
        encryptedType: 'public',
        shareType: 'public',
      );
      final blocks = (enc['blocks'] as List).cast<Map<String, dynamic>>();
      final meta = json.decode(utf8.decode(blocks.firstWhere((x) => x['isMetadataBlock'] == true)['encryptedContent'] as Uint8List)) as Map;
      expect(meta['isPublic'], isTrue);
      final ids = (meta['contentBlockIds'] as List).cast<String>();
      final joined = BytesBuilder();
      for (final id in ids) {
        joined.add(blocks.firstWhere((x) => x['blockId'] == id)['encryptedContent'] as Uint8List);
      }
      expect(crypto.sha256.convert(joined.toBytes()), crypto.sha256.convert(pic));
    });
  }, skip: nativeCrypto ? false : 'needs the webcrypto native library (dart run webcrypto:setup)');

  group('Umbral PRE (followers posts)', () {
    const tag = 'followers:2026';

    test('a follower with a rekey recovers the post key; others cannot', () {
      final pre = PreFfi.instance();
      final postKey = _randomBytes(32, 5);
      final capsule = pre.encapsulateWithTag(pkAuthor: a.publicKeyBytes, tag: tag, key: postKey);

      final rkAB = pre.generateRekey(skAuthor: a.preSecret, pkRecipient: b.publicKeyBytes, tag: tag);
      final forB = pre.reencrypt(encapsulatedForAuthor: capsule, rekey: rkAB);
      expect(pre.decapsulateForRecipient(encapsulatedForRecipient: forB, skRecipient: b.preSecret, tag: tag), postKey);

      // C holds B's transformed capsule but not B's key.
      List<int> asC() => pre.decapsulateForRecipient(encapsulatedForRecipient: forB, skRecipient: c.preSecret, tag: tag);
      expect(() {
        final k = asC();
        if (k.isEmpty || !_same(k, postKey)) throw StateError('no key');
      }, throwsA(anything));
    });

    // KNOWN GAP: native/umbral_pre ignores the tag in all three calls, so any rekey A->B opens every PRE post
    // of A whatever its tag (followers / subscribers month). Access is enforced only by who Central gives
    // rekeys to. Kept as a skipped test until per-tag author keys are introduced.
    test('a rekey for another tag does not open this post', () {
      final pre = PreFfi.instance();
      final postKey = _randomBytes(32, 9);
      final capsule = pre.encapsulateWithTag(pkAuthor: a.publicKeyBytes, tag: tag, key: postKey);
      final otherTag = pre.generateRekey(skAuthor: a.preSecret, pkRecipient: b.publicKeyBytes, tag: 'subscribers:2026-11');
      expect(() {
        final forB = pre.reencrypt(encapsulatedForAuthor: capsule, rekey: otherTag);
        final k = pre.decapsulateForRecipient(encapsulatedForRecipient: forB, skRecipient: b.preSecret, tag: tag);
        if (k.isEmpty || !_same(k, postKey)) throw StateError('no key');
      }, throwsA(anything));
    }, skip: 'known gap: the Umbral wrapper does not bind the tag (see comment above)');

    test('the author reads their own followers post through rk A->A', () {
      final pre = PreFfi.instance();
      final postKey = _randomBytes(32, 13);
      final capsule = pre.encapsulateWithTag(pkAuthor: a.publicKeyBytes, tag: tag, key: postKey);
      final rkAA = pre.generateRekey(skAuthor: a.preSecret, pkRecipient: a.publicKeyBytes, tag: tag);
      final forA = pre.reencrypt(encapsulatedForAuthor: capsule, rekey: rkAA);
      expect(pre.decapsulateForRecipient(encapsulatedForRecipient: forA, skRecipient: a.preSecret, tag: tag), postKey);
    });
  }, skip: umbral ? false : 'needs libumbral_pre (DELTANIUM_UMBRAL=1)');
}

bool _same(List<int> x, List<int> y) {
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
