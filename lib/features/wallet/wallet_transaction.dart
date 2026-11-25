import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:deltanium_app/utils/server_time.dart';

/// One row of the signed-in wallet's D ledger (`GET /api/wallet/ledger`), seen from [me]'s side.
class WalletTransaction {
  final String id;
  final String? from;
  final String? to;
  final double amount;
  final String kind;
  final String? refId;
  final String? memo;
  final DateTime? createdAt;

  /// True when D came into the wallet, false when it went out.
  final bool incoming;

  const WalletTransaction({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.kind,
    required this.refId,
    required this.memo,
    required this.createdAt,
    required this.incoming,
  });

  static const treasury = 'deltanium-treasury';

  static WalletTransaction fromJson(Map<String, dynamic> j, String me) {
    String? s(String k) {
      final v = j[k] ?? j[k[0].toUpperCase() + k.substring(1)];
      final t = v?.toString().trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final from = s('fromPublicKey');
    final to = s('toPublicKey');
    final amountRaw = j['amount'] ?? j['Amount'];
    final amount = amountRaw is num ? amountRaw.toDouble() : double.tryParse('$amountRaw') ?? 0;
    return WalletTransaction(
      id: s('id') ?? '',
      from: from,
      to: to,
      amount: amount,
      kind: s('kind') ?? 'transfer',
      refId: s('refId'),
      memo: s('memo'),
      createdAt: ServerTime.tryParse(s('createdAt')),
      incoming: sameKey(to, me) && !sameKey(from, me),
    );
  }

  static bool sameKey(String? a, String? b) =>
      a != null && b != null && a.trim().toLowerCase() == b.trim().toLowerCase();

  /// The other side of the movement: who sent it (incoming) or where it went (outgoing).
  String? get counterparty => incoming ? from : to;

  /// Signed amount from the wallet's point of view.
  double get signedAmount => incoming ? amount : -amount;

  /// Top-ups are mirrored on chain with the order id as tx id.
  String? get onChainTxId => kind == 'topup' ? refId : null;

  /// Short label for [kind], e.g. "Top-up", "Storage fee".
  String get kindLabel {
    final key = 'tx.kind.${kind.replaceAll(':', '.')}';
    final t = tr(key);
    if (t != key) return t;
    final root = 'tx.kind.${kind.split(':').first}';
    final r = tr(root);
    return r != root ? r : kind;
  }

  /// Readable name for a ledger account: system accounts by role, wallets as a shortened key.
  static String accountLabel(String? account) {
    if (account == null || account.isEmpty) return tr('tx.acct.network');
    if (account == treasury) return tr('tx.acct.treasury');
    if (account.startsWith('escrow:')) return tr('tx.acct.escrow');
    if (account.startsWith('bond:')) return tr('tx.acct.bond');
    if (account == 'treasury:network-fund') return tr('tx.acct.fund');
    if (account == 'treasury:protocol-ops') return tr('tx.acct.ops');
    if (account == 'treasury:redemption-hold') return tr('tx.acct.redeem');
    if (account.startsWith('pool:') || account.startsWith('treasury:')) return tr('tx.acct.network');
    return shortKey(account);
  }

  static String shortKey(String k) => k.length <= 16 ? k : '${k.substring(0, 8)}…${k.substring(k.length - 6)}';
}
