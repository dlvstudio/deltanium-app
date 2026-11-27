import 'dart:convert';
import 'dart:typed_data';

import 'package:deltanium_app/services/store_placement.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorePlacement.splitCharge', () {
    test('parts add up to exactly what the user confirmed', () {
      for (final total in [0.0, 0.1, 0.7771, 1.0, 0.0003, 12345.6789]) {
        for (final n in [1, 2, 3, 5]) {
          final parts = StorePlacement.splitCharge(total, n);
          expect(parts.length, n);
          final units = parts.fold<int>(0, (a, p) => a + (p * 10000).round());
          expect(units, (total * 10000).round(), reason: '$total over $n Stores');
          expect(parts.every((p) => p >= 0), isTrue);
        }
      }
    });

    test('the first Store takes the remainder', () {
      expect(StorePlacement.splitCharge(0.7771, 2), [0.3886, 0.3885]);
      expect(StorePlacement.splitCharge(0.1, 3), [0.0334, 0.0333, 0.0333]);
    });
  });

  test('billableBytes counts each metadata entry as uploaded, with its 32-character Store contract id', () {
    final entries = [
      {'fileId': 'f1', 'firstBlockId': 'b0', 'type': 'post'},
      {'fileId': 'f2', 'firstBlockId': 'b1', 'type': 'post'},
    ];
    final blocks = [
      {'blockId': 'b0', 'blockIndex': 0, 'encryptedContent': Uint8List(100)},
      {'blockId': 'c1', 'blockIndex': 1, 'encryptedContent': Uint8List(1000)},
    ];
    final asUploaded = [for (final e in entries) {...e, 'contractId': 'a' * 32}];
    expect(StorePlacement.billableBytes(entries, blocks), WalletService.storedBytes(asUploaded, blocks));
    expect(StorePlacement.billableBytes(entries, blocks),
        asUploaded.fold<int>(0, (a, e) => a + utf8.encode(jsonEncode(e)).length) + 1100);
  });
}
