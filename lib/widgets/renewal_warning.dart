import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/utils/d_format.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// What the wallet must cover to keep the user's stored items (`GET /api/storedfile/renewals`).
class RenewalStatus {
  final double balance;
  final int graceCount;
  final double graceFee;
  final DateTime? graceUntil;
  final int dueCount;
  final double dueFee;
  final DateTime? firstDue;
  final double shortfall;
  final int deleteAfterDays;

  const RenewalStatus({
    this.balance = 0,
    this.graceCount = 0,
    this.graceFee = 0,
    this.graceUntil,
    this.dueCount = 0,
    this.dueFee = 0,
    this.firstDue,
    this.shortfall = 0,
    this.deleteAfterDays = 7,
  });

  static double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  static DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

  factory RenewalStatus.fromJson(Map<String, dynamic> j) => RenewalStatus(
        balance: _d(j['balance']),
        graceCount: (j['graceCount'] as num?)?.toInt() ?? 0,
        graceFee: _d(j['graceFee']),
        graceUntil: _t(j['graceUntil']),
        dueCount: (j['dueCount'] as num?)?.toInt() ?? 0,
        dueFee: _d(j['dueFee']),
        firstDue: _t(j['firstDue']),
        shortfall: _d(j['shortfall']),
        deleteAfterDays: (j['deleteAfterDays'] as num?)?.toInt() ?? 7,
      );

  /// Items in grace always warn; renewals due soon warn only when the balance will not cover them.
  bool get needsAttention => graceCount > 0 || (dueCount > 0 && shortfall > 0);

  /// Grace items are deleted when grace ends: red. Due renewals short of balance: orange.
  bool get urgent => graceCount > 0;

  String message() {
    final date = DateFormat('dd/MM/yyyy');
    if (graceCount > 0) {
      return tr('renew.grace', {
        'n': '$graceCount',
        'fee': DFormat.exact(graceFee),
        'need': DFormat.exact(shortfall),
        'date': graceUntil == null ? '—' : date.format(graceUntil!),
        'days': '$deleteAfterDays',
      });
    }
    return tr('renew.due', {
      'n': '$dueCount',
      'fee': DFormat.exact(dueFee),
      'need': DFormat.exact(shortfall),
      'date': firstDue == null ? '—' : date.format(firstDue!),
    });
  }
}

/// Banner shown while stored items risk expiring: renewal failed (grace) or the balance will not cover the
/// renewals due this week. Amounts are the exact fees renewal takes. Shows nothing otherwise.
class RenewalWarning extends StatefulWidget {
  const RenewalWarning({super.key, this.margin = const EdgeInsets.fromLTRB(12, 10, 12, 0), this.onTopUp});

  final EdgeInsets margin;

  /// Opens the top-up; defaults to the profile page (where the wallet is).
  final VoidCallback? onTopUp;

  @override
  State<RenewalWarning> createState() => _RenewalWarningState();
}

class _RenewalWarningState extends State<RenewalWarning> {
  RenewalStatus? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await WalletService.renewals();
    if (mounted) setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null || !s.needsAttention) return const SizedBox.shrink();
    final color = s.urgent ? Brand.danger : Colors.orange;
    return AppLangBuilder(
      builder: (context) => Container(
        margin: widget.margin,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Brand.radius + 4),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.message(),
                  style: GoogleFonts.manrope(color: Brand.text, fontSize: 13, height: 1.4)),
            ),
            TextButton(
              onPressed: widget.onTopUp ?? () => context.push(AppRoutes.localUserProfile),
              child: Text(tr('renew.topup'), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
