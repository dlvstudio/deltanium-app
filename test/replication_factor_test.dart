import 'package:deltanium_app/config/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('N-of-M replicationFactor', () {
    test('defaults to at least 2 full replicas', () {
      expect(AppConstants.replicationFactor, greaterThanOrEqualTo(2));
    });

    test('node selection picks min(factor, available) nodes', () {
      final nodes = [
        {'id': 'a', 'endpoint': 'http://a'},
        {'id': 'b', 'endpoint': 'http://b'},
        {'id': 'c', 'endpoint': 'http://c'},
      ];
      final factor = AppConstants.replicationFactor;
      final n = factor.clamp(1, nodes.length);
      final selected = (List<Map<String, dynamic>>.from(nodes)..shuffle()).take(n).toList();
      expect(selected.length, n);
      expect(selected.length, lessThanOrEqualTo(nodes.length));
      expect(selected.map((e) => e['id']).toSet().length, selected.length);
    });
  });
}
