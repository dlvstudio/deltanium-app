import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/utils/d_format.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tip and subscribe flows (TOKENOMICS_V2 §9). Creators receive 90% of every payment.
class CreatorSupport {
  static void _toast(BuildContext context, String msg, {bool error = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Brand.danger : null,
        duration: Duration(seconds: error ? 6 : 3),
      ),
    );
  }

  /// Default tip: 1,000 D, never more than the balance.
  static const double _defaultTip = 1000;

  static Future<void> showTipDialog(
    BuildContext context, {
    required String toPublicKey,
    String? postId,
    String? name,
  }) async {
    final balance = await WalletService.getBalance();
    if (!context.mounted) return;
    if (balance != null && balance <= 0) {
      _toast(context, 'Your wallet is empty. Top up from your profile to send tips.', error: true);
      return;
    }
    final start = balance == null ? _defaultTip : (balance < _defaultTip ? balance.floorToDouble() : _defaultTip);
    final controller = TextEditingController(text: (start < 1 ? 1 : start).toStringAsFixed(0));
    String? fieldError;

    double? parse() => double.tryParse(controller.text.trim().replaceAll(',', ''));
    String? validate() {
      final a = parse();
      if (a == null || a <= 0) return 'Enter an amount above 0';
      if (balance != null && a > balance) return 'More than your balance (${DFormat.d(balance)})';
      return null;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setLocal) => AlertDialog(
                  backgroundColor: Brand.panel,
                  title: Text('Tip ${name ?? 'creator'}', style: GoogleFonts.syne(color: Brand.text)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'The creator receives 90%. 1 D = 1 VND.'
                        '${balance == null ? '' : '\nYour balance: ${DFormat.d(balance)}'}',
                        style: GoogleFonts.manrope(color: Brand.muted, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.manrope(color: Brand.text),
                        onChanged: (_) {
                          if (fieldError != null) setLocal(() => fieldError = validate());
                        },
                        decoration: InputDecoration(
                          labelText: 'Amount (D)',
                          errorText: fieldError,
                          labelStyle: GoogleFonts.manrope(color: Brand.muted),
                          filled: true,
                          fillColor: Brand.inkSoft,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(Brand.radius)),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(
                      onPressed: () {
                        final err = validate();
                        if (err != null) {
                          setLocal(() => fieldError = err);
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      style: FilledButton.styleFrom(backgroundColor: Brand.sand, foregroundColor: Brand.ink),
                      child: const Text('Send tip'),
                    ),
                  ],
                ),
          ),
    );
    if (ok != true || !context.mounted) return;
    final amount = parse();
    if (amount == null || amount <= 0) return;
    final r = await WalletService.tip(toPublicKey, amount, postId: postId);
    if (!context.mounted) return;
    if (r.ok) {
      _toast(context, 'Sent ${DFormat.d(amount)}');
    } else {
      _toast(context, 'Tip failed: ${r.error}', error: true);
    }
  }

  static Future<void> showSubscribeDialog(BuildContext context, {required String creatorPublicKey, String? name}) async {
    final planResp = await WalletService.getPlan(creatorPublicKey);
    if (!context.mounted) return;
    final plan = planResp?['plan'] as Map<String, dynamic>?;
    final price = (plan?['pricePerMonthD'] as num?)?.toDouble() ?? 0;
    if (plan == null || plan['active'] != true || price <= 0) {
      _toast(context, '${name ?? 'This creator'} has no subscription plan yet');
      return;
    }
    final subscribed = await WalletService.isSubscribed(creatorPublicKey);
    if (!context.mounted) return;
    var months = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Brand.panel,
          title: Text('Subscribe to ${name ?? 'creator'}', style: GoogleFonts.syne(color: Brand.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${DFormat.d(price)} / month · unlocks subscribers-only posts.'
                '${subscribed ? '\nYou are already subscribed this month; this extends it.' : ''}',
                style: GoogleFonts.manrope(color: Brand.muted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in const [1, 3, 6, 12])
                    ChoiceChip(
                      selected: months == m,
                      onSelected: (_) => setLocal(() => months = m),
                      label: Text('$m mo'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Total ${DFormat.full(price * months)}',
                  style: GoogleFonts.manrope(color: Brand.sand, fontWeight: FontWeight.w700)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Brand.sand, foregroundColor: Brand.ink),
              child: const Text('Subscribe'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final r = await WalletService.subscribe(creatorPublicKey, months: months);
    if (!context.mounted) return;
    final through = (r.map?['subscription'] as Map<String, dynamic>?)?['paidThroughEpoch'];
    _toast(context, r.ok ? 'Subscribed through $through' : 'Subscription failed: ${r.error}');
  }
}
