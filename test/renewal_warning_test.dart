import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:deltanium_app/widgets/renewal_warning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appLang.value = AppLang.en);

  test('items in grace warn with the exact top-up and the deadline', () {
    final s = RenewalStatus.fromJson({
      'balance': 0.1229,
      'graceCount': 1,
      'graceFee': 0.7771,
      'graceUntil': '2027-01-25T10:00:00Z',
      'dueCount': 0,
      'dueFee': 0,
      'shortfall': 0.6542,
      'deleteAfterDays': 7,
    });
    expect(s.needsAttention, isTrue);
    expect(s.urgent, isTrue);
    final m = s.message();
    expect(m, contains('1 stored item(s) could not be renewed'));
    expect(m, contains('0,7771 D'));
    expect(m, contains('at least 0,6542 D'));
    expect(m, contains('25/01/2027'));
    expect(m, contains('7 days later'));
    appLang.value = AppLang.vi;
    expect(s.message(), contains('nạp thêm ít nhất 0,6542 D'));
  });

  test('renewals due soon warn only when the balance will not cover them', () {
    final covered = RenewalStatus.fromJson({'balance': 5, 'dueCount': 2, 'dueFee': 0.7779, 'shortfall': 0});
    expect(covered.needsAttention, isFalse);
    final short = RenewalStatus.fromJson(
        {'balance': 0.5, 'dueCount': 2, 'dueFee': 0.7779, 'shortfall': 0.2779, 'firstDue': '2026-12-26T09:00:00Z'});
    expect(short.needsAttention, isTrue);
    expect(short.urgent, isFalse);
    expect(short.message(), contains('2 stored item(s) renew in the next 7 days'));
    expect(short.message(), contains('0,2779 D short'));
    expect(const RenewalStatus().needsAttention, isFalse);
  });
}
