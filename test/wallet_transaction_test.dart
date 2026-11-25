import 'package:deltanium_app/features/wallet/wallet_transaction.dart';
import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const me = '02a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';
  const other = '03699b56070f41068ca1166169547a4bd05022c41e184069352163dfe21553a14c';

  setUp(() => appLang.value = AppLang.en);

  test('a top-up from the treasury is incoming and points at its on-chain tx', () {
    final t = WalletTransaction.fromJson({
      'id': 'l1',
      'fromPublicKey': 'deltanium-treasury',
      'toPublicKey': me,
      'amount': 97000.0,
      'kind': 'topup',
      'refId': '0123456789abcdef0123456789abcdef',
      'createdAt': '2026-11-25T10:50:00',
    }, me.toUpperCase());

    expect(t.incoming, isTrue);
    expect(t.signedAmount, 97000);
    expect(t.kindLabel, 'Top-up');
    expect(WalletTransaction.accountLabel(t.counterparty), 'Deltanium treasury');
    expect(t.onChainTxId, '0123456789abcdef0123456789abcdef');
    expect(t.createdAt!.toUtc(), DateTime.utc(2026, 11, 25, 10, 50));
  });

  test('storage escrow and transfers out are outgoing', () {
    final escrow = WalletTransaction.fromJson(
        {'id': 'l2', 'fromPublicKey': me, 'toPublicKey': 'escrow:abc', 'amount': '12.5', 'kind': 'escrow:fund'}, me);
    expect(escrow.incoming, isFalse);
    expect(escrow.signedAmount, -12.5);
    expect(escrow.kindLabel, 'Storage escrow');
    expect(WalletTransaction.accountLabel(escrow.counterparty), 'Storage escrow');
    expect(escrow.onChainTxId, isNull);

    final sent = WalletTransaction.fromJson(
        {'Id': 'l3', 'FromPublicKey': me, 'ToPublicKey': other, 'Amount': 5, 'Kind': 'transfer'}, me);
    expect(sent.incoming, isFalse);
    expect(WalletTransaction.accountLabel(sent.counterparty), '03699b56…53a14c');
  });

  test('unknown sub-kinds fall back to their family, then to the raw kind', () {
    final a = WalletTransaction.fromJson({'fromPublicKey': me, 'toPublicKey': other, 'amount': 1, 'kind': 'fee:new'}, me);
    expect(a.kindLabel, 'Fee');
    final b = WalletTransaction.fromJson({'fromPublicKey': me, 'toPublicKey': other, 'amount': 1, 'kind': 'mystery'}, me);
    expect(b.kindLabel, 'mystery');
    appLang.value = AppLang.vi;
    expect(a.kindLabel, 'Phí');
  });
}
