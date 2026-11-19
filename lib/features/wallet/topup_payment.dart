import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/utils/d_format.dart';
import 'package:deltanium_app/utils/server_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// VietQR image (SVG) for a bank transfer with amount and transfer content pre-filled (img.vietqr.io).
/// Only the receiving account, amount and order reference are sent — nothing about the user.
String vietQrImageUrl({
  required String bin,
  required String accountNo,
  required String accountName,
  required num amountVnd,
  required String transferContent,
}) =>
    Uri.https('img.vietqr.io', '/image/$bin-$accountNo-compact2.svg', {
      'amount': amountVnd.round().toString(),
      'addInfo': transferContent,
      'accountName': accountName,
    }).toString();

/// After a top-up order is created: QR + account details (bank) or the PayPal.me link (paypal).
Future<void> showTopUpPaymentDialog(BuildContext context, Map<String, dynamic> result) {
  if (result['paypal'] is Map) return _showPayPalDialog(context, result);
  final order = (result['order'] as Map?)?.cast<String, dynamic>() ?? const {};
  final bank = (result['bank'] as Map?)?.cast<String, dynamic>();
  final content = result['transferContent']?.toString() ?? '';
  final amount = (order['fiatAmountVnd'] as num?) ?? 0;
  final credited = order['dCredited'] as num?;

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Brand.panel,
      title: Text(tr('topup.pay.title'), style: GoogleFonts.syne(color: Brand.text)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bank == null)
              Text(tr('topup.pay.noBank'), style: _muted)
            else ...[
              Text(tr('topup.pay.scan'), style: _muted),
              const SizedBox(height: 12),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Brand.radius),
                  child: Container(
                    color: Colors.white,
                    width: 240,
                    height: 240,
                    child: SvgPicture.network(
                      vietQrImageUrl(
                        bin: '${bank['bin']}',
                        accountNo: '${bank['accountNo']}',
                        accountName: '${bank['accountName']}',
                        amountVnd: amount,
                        transferContent: content,
                      ),
                      fit: BoxFit.contain,
                      placeholderBuilder: (_) => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Brand.sand)),
                      errorBuilder: (_, __, ___) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(tr('topup.pay.qrFailed'),
                              textAlign: TextAlign.center, style: _muted.copyWith(color: Brand.ink)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _row(ctx, tr('topup.pay.bank'), '${bank['bankName']}'),
              _row(ctx, tr('topup.pay.account'), '${bank['accountNo']}', copy: true),
              _row(ctx, tr('topup.pay.holder'), '${bank['accountName']}'),
              _row(ctx, tr('topup.pay.amount'), DFormat.vnd(amount), copyValue: amount.round().toString()),
              _row(ctx, tr('topup.pay.content'), content, copy: true, strong: true),
            ],
            const SizedBox(height: 10),
            if (credited != null)
              Text(tr('topup.pay.youGet', {'d': DFormat.full(credited)}),
                  style: GoogleFonts.manrope(color: Brand.sand, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(tr('topup.pay.note'), style: _muted.copyWith(fontSize: 12)),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          style: FilledButton.styleFrom(backgroundColor: Brand.sand, foregroundColor: Brand.ink),
          child: Text(tr('topup.pay.done')),
        ),
      ],
    ),
  );
}

/// The signed-in user's top-up orders and their status.
Future<void> showMyTopUps(BuildContext context) async {
  final r = await WalletService.myTopUps();
  if (!context.mounted) return;
  final orders = ((r.map?['orders'] as List?) ?? const []).cast<Map>();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Brand.panel,
      title: Text(tr('topup.list.title'), style: GoogleFonts.syne(color: Brand.text)),
      content: SizedBox(
        width: 420,
        child: !r.ok
            ? Text(tr('topup.list.error', {'e': r.error ?? ''}), style: _muted)
            : orders.isEmpty
                ? Text(tr('topup.list.empty'), style: _muted)
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const Divider(color: Brand.line, height: 16),
                    itemBuilder: (_, i) {
                      final o = orders[i].cast<String, dynamic>();
                      final status = '${o['status']}';
                      final created = ServerTime.tryParse(o['createdAt']?.toString());
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(DFormat.vnd((o['fiatAmountVnd'] as num?) ?? 0),
                                    style: GoogleFonts.manrope(color: Brand.text, fontWeight: FontWeight.w700)),
                              ),
                              _statusChip(status),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${o['transferContent'] ?? ''}'
                            '${created != null ? ' · ${_two(created.day)}/${_two(created.month)} ${_two(created.hour)}:${_two(created.minute)}' : ''}',
                            style: _muted.copyWith(fontSize: 12),
                          ),
                        ],
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('topup.pay.done'), style: GoogleFonts.manrope(color: Brand.sand)),
        ),
      ],
    ),
  );
}

final TextStyle _muted = GoogleFonts.manrope(color: Brand.muted, height: 1.4, fontSize: 13);

String _two(int n) => n.toString().padLeft(2, '0');

Widget _statusChip(String status) {
  final (label, color) = switch (status) {
    'completed' => (tr('topup.status.completed'), Brand.moss),
    'pending' => (tr('topup.status.pending'), Brand.sand),
    _ => (status, Brand.muted),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Brand.radius),
      border: Border.all(color: color),
    ),
    child: Text(label, style: GoogleFonts.manrope(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
  );
}

Widget _row(BuildContext context, String label, String value, {bool copy = false, String? copyValue, bool strong = false}) {
  final canCopy = copy || copyValue != null;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(width: 92, child: Text(label, style: _muted)),
        Expanded(
          child: SelectableText(
            value,
            style: GoogleFonts.manrope(
              color: strong ? Brand.sandBright : Brand.text,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        if (canCopy)
          IconButton(
            tooltip: tr('topup.pay.copy'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 16, color: Brand.sand),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copyValue ?? value));
              ScaffoldMessenger.maybeOf(context)
                  ?.showSnackBar(SnackBar(content: Text(tr('topup.pay.copied', {'v': label}))));
            },
          ),
      ],
    ),
  );
}

Future<void> _showPayPalDialog(BuildContext context, Map<String, dynamic> result) {
  final order = (result['order'] as Map?)?.cast<String, dynamic>() ?? const {};
  final pp = (result['paypal'] as Map).cast<String, dynamic>();
  final content = result['transferContent']?.toString() ?? '';
  final usd = (pp['amountUsd'] as num?) ?? 0;
  final credited = order['dCredited'] as num?;
  final url = Uri.tryParse('${pp['url']}');

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Brand.panel,
      title: Text(tr('topup.pp.title'), style: GoogleFonts.syne(color: Brand.text)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('topup.pp.steps'), style: _muted),
            const SizedBox(height: 12),
            _row(ctx, tr('topup.pp.amount'), '${usd.toStringAsFixed(2)} USD', copyValue: usd.toStringAsFixed(2)),
            _row(ctx, tr('topup.pp.note'), content, copy: true, strong: true),
            _row(ctx, tr('topup.pp.rate'), '1 USD = ${DFormat.vnd((pp['vndPerUsd'] as num?) ?? 0)}'),
            const SizedBox(height: 10),
            if (credited != null)
              Text(tr('topup.pay.youGet', {'d': DFormat.full(credited)}),
                  style: GoogleFonts.manrope(color: Brand.sand, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(tr('topup.pp.warn'), style: _muted.copyWith(fontSize: 12)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('topup.pay.done'), style: GoogleFonts.manrope(color: Brand.muted)),
        ),
        FilledButton.icon(
          onPressed: url == null ? null : () => launchUrl(url, mode: LaunchMode.externalApplication),
          style: FilledButton.styleFrom(backgroundColor: Brand.sand, foregroundColor: Brand.ink),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: Text(tr('topup.pp.open')),
        ),
      ],
    ),
  );
}
