import 'dart:typed_data';

import 'package:deltanium_app/features/create_post/post_publisher.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/utils/d_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact D shows the billed amount to 0.0001 D, never rounded to whole D', () {
    expect(DFormat.exact(37.3028), '37,3028 D');
    expect(DFormat.exact(1), '1 D');
    expect(DFormat.exact(0.0377), '0,0377 D');
    expect(DFormat.exact(96952.6972), '96.952,6972 D');
  });

  test('total of charges is summed in 0.0001 D steps', () {
    final items = [
      const StorageChargeItem('Image', 2086124, 37.3028),
      const StorageChargeItem('Post', 2108, 1),
      const StorageChargeItem('Other', 10, 0.1),
    ];
    expect(StorageChargeItem.total(items), 38.4028);
    expect(StorageChargeItem.total(const []), 0);
    expect(
      StorageChargeItem.totalMonthly(const [
        StorageChargeItem('Image', 2086124, 0.7771, monthly: 0.7771),
        StorageChargeItem('Post', 2108, 0.1, monthly: 0.0008),
      ]),
      0.7779,
    );
  });

  test('post size quoted before the contract equals the size paid once the contract id is set', () {
    final entries = [
      {'fileId': 'f1', 'recipientPubKey': 'a', 'encryptedKey': 'k1'},
      {'fileId': 'f2', 'recipientPubKey': 'b', 'encryptedKey': 'k2', 'type': 'post'},
    ];
    final blocks = [
      {'blockId': 'b0', 'encryptedContent': Uint8List(300)},
      {'blockId': 'b1', 'encryptedContent': Uint8List(1500)},
    ];
    final quoted = postStoredBytes(entries, blocks, contractIdLength: 32, shareType: 'me');

    // What the publisher does after the Store returns the contract id (32 hex chars).
    for (final e in entries) {
      e['contractId'] = 'b1c5f86ddede48babef09f10178d3137';
      e['type'] ??= 'post';
      e['shareType'] ??= 'me';
    }
    expect(WalletService.storedBytes(entries, blocks), quoted);
  });
}
