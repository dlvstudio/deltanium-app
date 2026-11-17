import 'package:deltanium_app/services/egress_receipt_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('origin matches Central normalisation', () {
    expect(EgressReceipts.originOf(Uri.parse('HTTP://Store-A:80/api/file/block/b1')), 'http://store-a');
    expect(EgressReceipts.originOf(Uri.parse('https://s.example:8443/x')), 'https://s.example:8443');
  });

  test('block key from both download routes', () {
    expect(EgressReceipts.blockKeyOf(Uri.parse('http://s/api/file/block/abc')), 'abc');
    expect(EgressReceipts.blockKeyOf(Uri.parse('http://s/api/file/block/f1/0')), 'f1/0');
    expect(EgressReceipts.blockKeyOf(Uri.parse('http://s/api/file/list')), isNull);
  });

  test('signed message format', () {
    final m = EgressReceipts.message('http://s', 'pk', 5, const [MapEntry('b1', 10), MapEntry('f/1', 3)]);
    // sha256("b1:10;f/1:3")
    expect(m.startsWith('EGRESS|http://s|pk|5|'), isTrue);
    expect(m.split('|').last.length, 64);
  });
}
