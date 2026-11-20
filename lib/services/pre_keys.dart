import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

/// Author key material for Umbral PRE posts (followers / subscribers).
///
/// v1, policyScheme "CPRE", tags `followers:YYYY` and `subscribers:YYYY-MM`: the capsule is made for the author's
/// wallet key. The Umbral wrapper ignores the tag, so a single rekey A->B opens every v1 PRE post of A, whatever
/// its tag. Kept only to read and extend old posts.
///
/// v2, policyScheme "CPRE2", tags `followers-v2:YYYY-MM` and `subscribers-v2:YYYY-MM`: every tag has its own author
/// key, derived from the wallet key: sk_tag = HMAC-SHA256(sk_wallet, "deltanium-pre-v2|" + tag) mod (n-1) + 1.
/// A rekey made for one tag opens only that tag's posts, so a subscriber of one month cannot read another month's
/// posts, and someone who unfollows gets no key for the months after. Followers decrypt with their usual wallet
/// key; Central and the Stores only see opaque rekeys, as before.
class PreKeys {
  PreKeys._();

  static const schemeV1 = 'CPRE';
  static const schemeV2 = 'CPRE2';

  static final _domain = pc.ECDomainParameters('secp256k1');

  static String _month(DateTime t) => '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}';

  /// Tag for a new followers post, e.g. `followers-v2:2026-11`.
  static String followersTag([DateTime? at]) => 'followers-v2:${_month((at ?? DateTime.now()).toUtc())}';

  /// Tag for a new subscribers-only post, e.g. `subscribers-v2:2026-11`.
  static String subscribersTag([DateTime? at]) => 'subscribers-v2:${_month((at ?? DateTime.now()).toUtc())}';

  /// Followers tags of this month and the [months] - 1 before it: what a new follower is given so they can read
  /// recent followers posts too.
  static List<String> recentFollowersTags({int months = 12, DateTime? at}) {
    final now = (at ?? DateTime.now()).toUtc();
    return [for (var i = 0; i < months; i++) followersTag(DateTime.utc(now.year, now.month - i, 1))];
  }

  static bool isV2Tag(String tag) => tag.startsWith('followers-v2:') || tag.startsWith('subscribers-v2:');

  static String schemeFor(String tag) => isV2Tag(tag) ? schemeV2 : schemeV1;

  /// The wallet secret key (same derivation as the signing key: sha256 of the BIP39 seed).
  static Uint8List walletSecret(String mnemonic) =>
      Uint8List.fromList(sha256.convert(bip39.mnemonicToSeed(mnemonic)).bytes);

  /// The author's PRE secret for [tag]: the wallet key for v1 tags, a per-tag key for v2 tags.
  static Uint8List authorSecret(String mnemonic, String tag) {
    final wallet = walletSecret(mnemonic);
    if (!isV2Tag(tag)) return wallet;
    final mac = Hmac(sha256, wallet).convert(utf8.encode('deltanium-pre-v2|$tag')).bytes;
    final d = (_toBigInt(mac) % (_domain.n - BigInt.one)) + BigInt.one;
    return _to32(d);
  }

  /// Compressed public key (33 bytes) matching [authorSecret].
  static Uint8List authorPublic(String mnemonic, String tag) {
    final d = _toBigInt(authorSecret(mnemonic, tag));
    return Uint8List.fromList((_domain.G * d)!.getEncoded(true));
  }

  static BigInt _toBigInt(List<int> b) => b.fold(BigInt.zero, (a, x) => (a << 8) | BigInt.from(x));

  static Uint8List _to32(BigInt v) {
    final out = Uint8List(32);
    var x = v;
    for (var i = 31; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }
}
