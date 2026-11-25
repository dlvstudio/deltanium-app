import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/features/wallet/wallet_transaction.dart';
import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/utils/d_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

enum _Filter { all, received, sent }

/// D received and sent by the signed-in wallet (top-ups, transfers, fees, refunds...), newest first.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<WalletTransaction> _items = const [];
  double? _balance;
  String? _error;
  bool _loading = true;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = await AuthService().getCurrentAuthInfo();
    final me = auth?['publicKey'] ?? '';
    final results = await Future.wait([WalletService.ledger(), WalletService.getBalance()]);
    if (!mounted) return;
    final r = results[0] as WalletResult;
    setState(() {
      _loading = false;
      _balance = results[1] as double?;
      if (!r.ok) {
        _error = r.error;
        return;
      }
      final rows = (r.data is List ? r.data as List : const []).whereType<Map>();
      _items = rows.map((m) => WalletTransaction.fromJson(m.cast<String, dynamic>(), me)).toList();
    });
  }

  List<WalletTransaction> get _visible => switch (_filter) {
        _Filter.all => _items,
        _Filter.received => _items.where((t) => t.incoming).toList(),
        _Filter.sent => _items.where((t) => !t.incoming).toList(),
      };

  @override
  Widget build(BuildContext context) {
    return AppLangBuilder(
      builder: (context) => Scaffold(
        backgroundColor: Brand.ink,
        appBar: AppBar(
          backgroundColor: Brand.ink,
          foregroundColor: Brand.text,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.localUserHome),
          ),
          title: Text(tr('tx.title'), style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: tr('tx.refresh'),
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: RefreshIndicator(
              onRefresh: _load,
              color: Brand.sand,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _summary(),
                  const SizedBox(height: 16),
                  _filters(),
                  const SizedBox(height: 12),
                  ..._body(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary() {
    final inSum = _items.where((t) => t.incoming).fold<double>(0, (a, t) => a + t.amount);
    final outSum = _items.where((t) => !t.incoming).fold<double>(0, (a, t) => a + t.amount);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Brand.panel,
        borderRadius: BorderRadius.circular(Brand.radius + 6),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('tx.balance'), style: GoogleFonts.manrope(color: Brand.muted, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            _balance == null ? '—' : DFormat.exact(_balance!),
            style: GoogleFonts.syne(color: Brand.sand, fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 6,
            children: [
              _stat(tr('tx.totalIn'), '+${DFormat.exact(inSum)}', Brand.moss),
              _stat(tr('tx.totalOut'), '−${DFormat.exact(outSum)}', Brand.danger),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.manrope(color: Brand.muted, fontSize: 12)),
          Text(value, style: GoogleFonts.manrope(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _filters() => Wrap(
        spacing: 8,
        children: [
          for (final f in _Filter.values)
            ChoiceChip(
              label: Text(tr('tx.filter.${f.name}')),
              selected: _filter == f,
              onSelected: (_) => setState(() => _filter = f),
              selectedColor: Brand.sand.withValues(alpha: 0.18),
              backgroundColor: Brand.inkSoft,
              side: const BorderSide(color: Brand.line),
              labelStyle: GoogleFonts.manrope(
                color: _filter == f ? Brand.sand : Brand.muted,
                fontWeight: FontWeight.w600,
              ),
              showCheckmark: false,
            ),
        ],
      );

  List<Widget> _body() {
    if (_loading && _items.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(child: CircularProgressIndicator(color: Brand.sand)),
        ),
      ];
    }
    if (_error != null) {
      return [_message(tr('tx.error', {'e': _error!}), Brand.danger)];
    }
    final rows = _visible;
    if (rows.isEmpty) return [_message(tr('tx.empty'), Brand.muted)];
    return [for (final t in rows) _TxTile(t)];
  }

  Widget _message(String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Text(text, textAlign: TextAlign.center, style: GoogleFonts.manrope(color: color, fontSize: 14)),
        ),
      );
}

class _TxTile extends StatelessWidget {
  final WalletTransaction t;
  const _TxTile(this.t);

  @override
  Widget build(BuildContext context) {
    final color = t.incoming ? Brand.moss : Brand.danger;
    final when = t.createdAt == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(t.createdAt!);
    final party = WalletTransaction.accountLabel(t.counterparty);
    final direction = tr(t.incoming ? 'tx.from' : 'tx.to', {'who': party});
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Brand.inkSoft,
        borderRadius: BorderRadius.circular(Brand.radius + 4),
        border: Border.all(color: Brand.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Brand.radius + 4),
        onTap: () => _details(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(
                  t.incoming ? Icons.south_west_rounded : Icons.north_east_rounded,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.kindLabel,
                        style: GoogleFonts.manrope(color: Brand.text, fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('$direction · $when',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(color: Brand.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${t.incoming ? '+' : '−'}${DFormat.exact(t.amount)}',
                style: GoogleFonts.manrope(color: color, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _details(BuildContext context) {
    final when = t.createdAt == null ? '—' : DateFormat('dd/MM/yyyy HH:mm:ss').format(t.createdAt!);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.panel,
        title: Text(t.kindLabel, style: GoogleFonts.syne(color: Brand.text)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row(ctx, tr('tx.d.amount'), '${t.incoming ? '+' : '−'}${DFormat.exact(t.amount)}'),
              _row(ctx, tr('tx.d.time'), when),
              _row(ctx, tr('tx.d.from'), WalletTransaction.accountLabel(t.from), copy: t.from),
              _row(ctx, tr('tx.d.to'), WalletTransaction.accountLabel(t.to), copy: t.to),
              if (t.memo != null) _row(ctx, tr('tx.d.memo'), t.memo!),
              if (t.onChainTxId != null)
                _row(ctx, tr('tx.d.chain'), WalletTransaction.shortKey(t.onChainTxId!), copy: t.onChainTxId)
              else if (t.refId != null)
                _row(ctx, tr('tx.d.ref'), WalletTransaction.shortKey(t.refId!), copy: t.refId),
              _row(ctx, tr('tx.d.id'), WalletTransaction.shortKey(t.id), copy: t.id),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('topup.pay.done'), style: const TextStyle(color: Brand.sand)),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext ctx, String label, String value, {String? copy}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label, style: GoogleFonts.manrope(color: Brand.muted, fontSize: 13)),
            ),
            Expanded(
              child: SelectableText(value, style: GoogleFonts.manrope(color: Brand.text, fontSize: 13.5)),
            ),
            if (copy != null && copy.isNotEmpty)
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: copy));
                  ScaffoldMessenger.maybeOf(ctx)
                      ?.showSnackBar(SnackBar(content: Text(tr('topup.pay.copied', {'v': label}))));
                },
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.copy_rounded, size: 16, color: Brand.muted),
                ),
              ),
          ],
        ),
      );
}
