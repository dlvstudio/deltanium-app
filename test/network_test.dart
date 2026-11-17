import 'package:deltanium_app/config/network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Built without NETWORK_ID: mainnet, messages signed unchanged.
  test('default build is mainnet and leaves messages unchanged', () {
    expect(Network.isMainnet, isTrue);
    expect(Network.name, 'mainnet');
    expect(Network.scope('POST/api/tip1700000000abc'), 'POST/api/tip1700000000abc');
  });
}
