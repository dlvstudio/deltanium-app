import 'package:bip39/bip39.dart' as bip39;
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/pre_keys.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final m = bip39.generateMnemonic();

  test('v1 tags use the wallet key, so old posts keep working', () {
    final walletPk = CryptoService.getPublicKeyHex(CryptoService.generateKeyPairFromMnemonic(m));
    expect(_hex(PreKeys.authorPublic(m, 'followers:2026')), walletPk);
    expect(PreKeys.schemeFor('followers:2026'), 'CPRE');
  });

  test('v2 tags each get their own stable author key', () {
    final nov = PreKeys.authorPublic(m, 'followers-v2:2026-11');
    expect(PreKeys.authorPublic(m, 'followers-v2:2026-11'), nov, reason: 'deterministic');
    expect(PreKeys.authorPublic(m, 'followers-v2:2026-12'), isNot(nov));
    expect(PreKeys.authorPublic(m, 'subscribers-v2:2026-11'), isNot(nov));
    expect(PreKeys.authorPublic(bip39.generateMnemonic(), 'followers-v2:2026-11'), isNot(nov));
    expect(nov.length, 33);
    expect(PreKeys.authorSecret(m, 'followers-v2:2026-11').length, 32);
    expect(PreKeys.schemeFor('subscribers-v2:2026-11'), 'CPRE2');
  });

  test('monthly tag names, and a new follower gets the last 12 months across a year change', () {
    expect(PreKeys.followersTag(DateTime.utc(2026, 11, 20)), 'followers-v2:2026-11');
    expect(PreKeys.subscribersTag(DateTime.utc(2027, 1, 3)), 'subscribers-v2:2027-01');
    final tags = PreKeys.recentFollowersTags(at: DateTime.utc(2027, 2, 10));
    expect(tags.length, 12);
    expect(tags.first, 'followers-v2:2027-02');
    expect(tags, contains('followers-v2:2026-12'));
    expect(tags.last, 'followers-v2:2026-03');
  });
}
