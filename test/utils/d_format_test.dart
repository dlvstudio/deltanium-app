import 'package:deltanium_app/utils/d_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact keeps 4 decimals for normal amounts', () {
    expect(DFormat.exact(37.3028), '37,3028 D');
    expect(DFormat.exact(1), '1 D');
    expect(DFormat.exact(0), '0 D');
  });

  test('exact never shows a tiny bandwidth fee as 0 D', () {
    expect(DFormat.exact(0.000038892), '0,000038892 D');
    expect(DFormat.exact(0.0000777841), '0,0000777841 D');
  });
}
