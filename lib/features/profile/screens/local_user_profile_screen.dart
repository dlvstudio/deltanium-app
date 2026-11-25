import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/features/wallet/topup_payment.dart';
import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/user_service.dart';
import 'package:deltanium_app/services/wallet_service.dart';
import 'package:deltanium_app/utils/d_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class LocalUserProfileScreen extends StatefulWidget {
  final UserProfile userProfile;
  
  const LocalUserProfileScreen({
    super.key,
    required this.userProfile,
  });

  @override
  State<LocalUserProfileScreen> createState() => _LocalUserProfileScreenState();
}

class _LocalUserProfileScreenState extends State<LocalUserProfileScreen> {
  final _authService = AuthService();
  final _userService = UserService();
  late UserProfile _profile;
  double? _dBalance;
  Map<String, dynamic>? _economics;
  Map<String, dynamic>? _usage;
  bool _walletLoading = true;

  @override
  void initState() {
    super.initState();
    _profile = widget.userProfile;
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    setState(() => _walletLoading = true);
    final results = await Future.wait([
      WalletService.getBalance(),
      WalletService.getEconomics(),
      WalletService.getUsage(),
    ]);
    if (!mounted) return;
    setState(() {
      _dBalance = results[0] as double?;
      _economics = results[1] as Map<String, dynamic>?;
      _usage = results[2] as Map<String, dynamic>?;
      _walletLoading = false;
    });
  }

  double _channelFee(String channel) {
    final byChannel = _economics?['onRampFeeByChannel'] as Map<String, dynamic>?;
    final v = byChannel?[channel] as num?;
    if (v != null) return v.toDouble();
    return switch (channel) { 'card' => 5, 'paypal' => 6, _ => 3 };
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showTopUpDialog() async {
    final controller = TextEditingController(text: '100000');
    final vndPerD = (_economics?['vndPerD'] as num?)?.toDouble() ?? AppConstants.vndPerD;
    final minTopUp = (_economics?['minTopUpVnd'] as num?)?.toDouble() ?? 10000;
    var channel = 'transfer';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final fee = _channelFee(channel);
          final amount = double.tryParse(controller.text.trim()) ?? 0;
          final credited = amount * (100 - fee) / 100 / vndPerD;
          return AlertDialog(
            backgroundColor: Brand.panel,
            title: Text(tr('topup.title'), style: GoogleFonts.syne(color: Brand.text)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('topup.rate', {
                    'rate': vndPerD.toStringAsFixed(0),
                    'dlt': DFormat.d(AppConstants.dPerDlt),
                    'min': DFormat.vnd(minTopUp),
                    'fee': _channelFee('transfer').toStringAsFixed(0),
                  }),
                  style: GoogleFonts.manrope(color: Brand.muted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final c in const ['transfer', 'paypal'])
                      ChoiceChip(
                        selected: channel == c,
                        onSelected: (_) => setLocal(() => channel = c),
                        label: Text(
                          '${tr(c == 'paypal' ? 'topup.ch.paypal' : 'topup.ch.transfer')} · ${_channelFee(c).toStringAsFixed(0)}%',
                          style: GoogleFonts.manrope(fontSize: 13),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setLocal(() {}),
                  style: GoogleFonts.manrope(color: Brand.text),
                  decoration: InputDecoration(
                    labelText: tr('topup.amount'),
                    labelStyle: GoogleFonts.manrope(color: Brand.muted),
                    filled: true,
                    fillColor: Brand.inkSoft,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(Brand.radius)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('topup.youGet', {'d': DFormat.full(credited < 0 ? 0 : credited)}),
                  style: GoogleFonts.manrope(color: Brand.sand, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('topup.cancel'), style: GoogleFonts.manrope(color: Brand.muted)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Brand.sand, foregroundColor: Brand.ink),
                child: Text(tr('topup.create')),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;
    final amount = double.tryParse(controller.text.trim());
    if (amount == null || amount <= 0) return;

    final result = await WalletService.createTopUpResult(fiatAmountVnd: amount, channel: channel);
    if (!mounted) return;
    if (!result.ok || result.map == null) {
      _toast(tr('topup.failed', {'e': result.error ?? ''}));
      return;
    }
    await showTopUpPaymentDialog(context, result.map!);
    await _loadWallet();
  }

  Future<double?> _askAmount({required String title, required String hint, required String label, String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.panel,
        title: Text(title, style: GoogleFonts.syne(color: Brand.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hint, style: GoogleFonts.manrope(color: Brand.muted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: GoogleFonts.manrope(color: Brand.text),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: GoogleFonts.manrope(color: Brand.muted),
                filled: true,
                fillColor: Brand.inkSoft,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Brand.radius)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.manrope(color: Brand.muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Brand.sand, foregroundColor: Brand.ink),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    return double.tryParse(controller.text.trim());
  }

  Future<void> _showRedeemDialog() async {
    final amount = await _askAmount(
      title: 'Redeem D to VND',
      hint: 'For KYC-verified creators and node operators. Fee 1%, minimum 100.000 D, paid weekly to your verified bank account.',
      label: 'Amount (D)',
    );
    if (amount == null || amount <= 0) return;
    final r = await WalletService.redeem(amount);
    _toast(r.ok ? 'Redemption requested (${r.map?['status']})' : 'Redemption failed: ${r.error}');
    await _loadWallet();
  }

  Future<void> _showPlanDialog() async {
    final current = (_usage?['plan'] as Map<String, dynamic>?)?['pricePerMonthD'] as num?;
    final price = await _askAmount(
      title: 'Subscription price',
      hint: 'Monthly price in D for your subscribers-only posts (0 disables). You receive 90%.',
      label: 'Price per month (D)',
      initial: current?.toStringAsFixed(0) ?? '',
    );
    if (price == null || price < 0) return;
    final r = await WalletService.setPlan(price);
    _toast(r.ok ? 'Subscription price saved' : 'Could not save: ${r.error}');
    await _loadWallet();
  }

  Future<void> _showEgressCapDialog() async {
    final cap = await _askAmount(
      title: 'Monthly bandwidth cap',
      hint: 'Maximum D per month charged for reads beyond your included quota (0 = no cap). '
          'When reached, your content is served to subscribers only.',
      label: 'Cap (D / month)',
    );
    if (cap == null || cap < 0) return;
    final r = await WalletService.setEgressCap(cap);
    _toast(r.ok ? 'Bandwidth cap saved' : 'Could not save: ${r.error}');
    await _loadWallet();
  }

  /// Human-readable size. Posts and reactions are a few KB, so a fixed "x.x MB" would show 0.0 MB for them.
  String _mb(num? bytes) {
    final b = (bytes ?? 0).toDouble();
    if (b < 1024) return '${b.round()} B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Two steps: send a code to the address, then type it in. One verified address unlocks one account.
  Future<void> _verifyEmail() async {
    final emailCtrl = TextEditingController(text: _profile.email ?? '');
    final codeCtrl = TextEditingController();
    var codeSent = false;
    var busy = false;
    String? error;
    final verified = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> run(Future<WalletResult> Function() call, void Function() onOk) async {
            setLocal(() { busy = true; error = null; });
            final r = await call();
            setLocal(() {
              busy = false;
              if (r.ok) { onOk(); } else { error = r.error ?? 'Something went wrong'; }
            });
          }
          return AlertDialog(
            title: const Text('Verify your email'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailCtrl,
                  enabled: !codeSent && !busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                if (codeSent)
                  TextField(
                    controller: codeCtrl,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: '6-digit code from the email'),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              if (codeSent)
                TextButton(
                  onPressed: busy ? null : () => run(() => WalletService.sendEmailCode(emailCtrl.text), () {}),
                  child: const Text('Resend'),
                ),
              FilledButton(
                onPressed: busy
                    ? null
                    : codeSent
                        ? () => run(() => WalletService.verifyEmailCode(codeCtrl.text), () => Navigator.pop(ctx, true))
                        : () => run(() => WalletService.sendEmailCode(emailCtrl.text), () => codeSent = true),
                child: Text(codeSent ? 'Verify' : 'Send code'),
              ),
            ],
          );
        },
      ),
    );
    emailCtrl.dispose();
    codeCtrl.dispose();
    if (verified == true) {
      _toast('Email verified');
      await _loadWallet();
    }
  }

  Widget _usageSummary() {
    final free = _usage?['freeTier'] as Map<String, dynamic>?;
    final egress = _usage?['egress'] as Map<String, dynamic>?;
    final storage = _usage?['storage'] as Map<String, dynamic>?;
    final plan = _usage?['plan'] as Map<String, dynamic>?;
    if (free == null) return const SizedBox.shrink();
    final style = GoogleFonts.manrope(color: Brand.muted, fontSize: 12, height: 1.5);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The network may offer no free storage (quota 0): then say nothing about it.
          if (((free['storageQuotaBytes'] as num?) ?? 0) > 0)
            Text(
              free['eligible'] == true
                  ? 'Free storage: ${_mb(free['storageUsedBytes'])} / ${_mb(free['storageQuotaBytes'])}'
                  : 'Free tier: verify your email to get ${_mb(free['storageQuotaBytes'])} free storage',
              style: style,
            ),
          if (free['emailVerified'] != true)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                onPressed: _verifyEmail,
                child: Text(
                  free['requiresVerifiedEmail'] == true && ((free['storageQuotaBytes'] as num?) ?? 0) > 0
                      ? 'Verify email to keep free storage'
                      : 'Verify email',
                  style: GoogleFonts.manrope(color: Brand.sand, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          Text(
            'Paid storage: ${_mb(storage?['paidBytes'])} · ${storage?['pricePerGbMonth'] ?? 800} D/GB/month per replica',
            style: style,
          ),
          Text(
            'Reads this month: ${_mb(egress?['bytes'])} · over-quota charged ${DFormat.exact((egress?['chargedD'] as num?) ?? 0)}',
            style: style,
          ),
          if (plan != null && plan['active'] == true)
            Text('Your subscription: ${DFormat.d(plan['pricePerMonthD'] as num)} / month', style: style),
        ],
      ),
    );
  }

  // Get compressed public key (always use compressed format)
  String _getCompressedPublicKey(String uncompressedKey) {
    return CryptoService.convertToCompressedPublicKey(uncompressedKey);
  }

  InputDecoration _fieldDecoration({required String label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.manrope(color: Brand.muted),
      filled: true,
      fillColor: Brand.inkSoft,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        borderSide: const BorderSide(color: Brand.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        borderSide: const BorderSide(color: Brand.sand),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        borderSide: BorderSide(color: Brand.danger.withValues(alpha: 0.7)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        borderSide: const BorderSide(color: Brand.danger),
      ),
    );
  }

  DateTime? _parseBirthday(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _showEditProfileDialog() async {
    final formKey = GlobalKey<FormState>();
    final emailController = TextEditingController(text: _profile.email ?? '');
    final fullNameController =
        TextEditingController(text: _profile.fullName ?? '');
    final bioController = TextEditingController(text: _profile.bio ?? '');
    final avatarUrlController =
        TextEditingController(text: _profile.avatarUrl ?? '');
    DateTime? selectedDateOfBirth = _parseBirthday(_profile.dateOfBirth);
    var isSaving = false;
    String? errorMessage;

    final bodyStyle = GoogleFonts.manrope(color: Brand.text, height: 1.45);
    final mutedStyle = GoogleFonts.manrope(color: Brand.muted, height: 1.4);

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSaving,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Material(
                  color: Brand.panel,
                  borderRadius: BorderRadius.circular(Brand.radius + 4),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Edit profile',
                                  style: GoogleFonts.syne(
                                    color: Brand.text,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 22,
                                    letterSpacing: -1.1,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                icon: const Icon(Icons.close, color: Brand.muted),
                                onPressed: isSaving
                                    ? null
                                    : () => Navigator.pop(dialogContext),
                              ),
                            ],
                          ),
                          Text(
                            'Update how others see you. Changes are signed with your key.',
                            style: mutedStyle,
                          ),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: bodyStyle,
                            decoration: _fieldDecoration(label: 'Email'),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Enter your email';
                              }
                              if (!value.contains('@')) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: fullNameController,
                            style: bodyStyle,
                            decoration: _fieldDecoration(label: 'Full name'),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter your full name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            borderRadius: BorderRadius.circular(Brand.radius),
                            onTap: isSaving
                                ? null
                                : () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: selectedDateOfBirth ??
                                          DateTime.now().subtract(
                                            const Duration(days: 365 * 18),
                                          ),
                                      firstDate: DateTime(1900),
                                      lastDate: DateTime.now(),
                                    );
                                    if (picked != null) {
                                      setDialogState(
                                        () => selectedDateOfBirth = picked,
                                      );
                                    }
                                  },
                            child: InputDecorator(
                              decoration:
                                  _fieldDecoration(label: 'Date of birth'),
                              child: Text(
                                selectedDateOfBirth != null
                                    ? '${selectedDateOfBirth!.day.toString().padLeft(2, '0')}/'
                                        '${selectedDateOfBirth!.month.toString().padLeft(2, '0')}/'
                                        '${selectedDateOfBirth!.year}'
                                    : 'Select date',
                                style: selectedDateOfBirth != null
                                    ? bodyStyle
                                    : mutedStyle,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: bioController,
                            maxLines: 2,
                            style: bodyStyle,
                            decoration:
                                _fieldDecoration(label: 'Bio (optional)'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: avatarUrlController,
                            style: bodyStyle,
                            decoration: _fieldDecoration(
                              label: 'Avatar URL (optional)',
                            ),
                          ),
                          if (errorMessage != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Brand.danger.withValues(alpha: 0.14),
                                borderRadius:
                                    BorderRadius.circular(Brand.radius),
                                border: Border.all(
                                  color: Brand.danger.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                errorMessage!,
                                style: GoogleFonts.manrope(
                                  color: Brand.sandBright,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (selectedDateOfBirth == null) {
                                        setDialogState(() {
                                          errorMessage =
                                              'Please select your date of birth.';
                                        });
                                        return;
                                      }
                                      if (!formKey.currentState!.validate()) {
                                        return;
                                      }

                                      setDialogState(() {
                                        isSaving = true;
                                        errorMessage = null;
                                      });

                                      try {
                                        final auth =
                                            await _authService.getCurrentAuthInfo();
                                        final mnemonic = auth?['mnemonic'];
                                        if (mnemonic == null ||
                                            mnemonic.isEmpty) {
                                          setDialogState(() {
                                            errorMessage =
                                                'Missing signing key. Please log in again.';
                                            isSaving = false;
                                          });
                                          return;
                                        }

                                        final email =
                                            emailController.text.trim();
                                        final fullName =
                                            fullNameController.text.trim();
                                        final updated =
                                            await _userService.updateProfile(
                                          publicKey: _profile.publicKey,
                                          mnemonic: mnemonic,
                                          email: email,
                                          fullName: fullName,
                                          dateOfBirth: selectedDateOfBirth!,
                                          bio: bioController.text.trim(),
                                          avatarUrl:
                                              avatarUrlController.text.trim(),
                                        );

                                        // Keep local auth email in sync if changed
                                        if (email != (auth?['email'] ?? '')) {
                                          await _authService.saveAuthInfo(
                                            email,
                                            mnemonic,
                                            auth?['publicKey'] ??
                                                _profile.publicKey,
                                          );
                                        }

                                        if (!mounted) return;
                                        setState(() => _profile = updated);
                                        if (dialogContext.mounted) {
                                          Navigator.pop(dialogContext);
                                        }
                                        ScaffoldMessenger.of(this.context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text('Profile updated'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      } catch (e) {
                                        setDialogState(() {
                                          errorMessage = e
                                              .toString()
                                              .replaceFirst('Exception: ', '');
                                          isSaving = false;
                                        });
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: Brand.sand,
                                foregroundColor: Brand.ink,
                                disabledBackgroundColor:
                                    Brand.sand.withValues(alpha: 0.4),
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Brand.ink,
                                      ),
                                    )
                                  : Text(
                                      'Save changes',
                                      style: GoogleFonts.manrope(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      emailController.dispose();
      fullNameController.dispose();
      bioController.dispose();
      avatarUrlController.dispose();
    });
  }
  
  // Copy public key to clipboard (always compressed)
  Future<void> _copyPublicKey(BuildContext context) async {
    final keyToCopy = _getCompressedPublicKey(_profile.publicKey);
    
    await Clipboard.setData(ClipboardData(text: keyToCopy));
    
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Public Key Copied!',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Share this with others to receive files',
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
  
  // Handle logout process
  Future<void> _handleLogout() async {
    try {
      // Show logout options dialog
      final logoutChoice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Logout Options'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose logout type:'),
              SizedBox(height: 12),
              Text('• Logout: Switch accounts (keep saved credentials)'),
              Text('• Complete Logout: Remove all data (delete all saved accounts)'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('normal'),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('Logout'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('complete'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Complete Logout'),
            ),
          ],
        ),
      );

      if (logoutChoice == null || !mounted) return;

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Perform logout using AuthService
      final success = logoutChoice == 'complete' 
          ? await _authService.completeLogout()
          : await _authService.logout();
      
      if (!mounted) return;
      
      // Close loading dialog
      Navigator.of(context).pop();
      
      if (success) {
        // Show success message
        final message = logoutChoice == 'complete'
            ? 'Completely logged out - all data cleared'
            : 'Logged out successfully';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        
        // Navigate to login screen
        context.go(AppRoutes.login);
      } else {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Failed to logout. Please try again.'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      
      // Close loading dialog if still showing
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Error during logout: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  String _formatBirthday(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    try {
      final date = DateTime.parse(raw);
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return raw.split('T').first;
    }
  }

  @override
  Widget build(BuildContext context) => AppLangBuilder(builder: _build);

  Widget _build(BuildContext context) {
    final displayName =
        _profile.fullName ?? _profile.email ?? 'Local User';
    final initial = displayName.trim().isNotEmpty
        ? displayName.trim()[0].toUpperCase()
        : 'D';

    return Scaffold(
      backgroundColor: Brand.ink,
      appBar: AppBar(
        backgroundColor: Brand.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          tr('nav.profile'),
          style: GoogleFonts.syne(
            color: Brand.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: LangSwitch(color: Brand.muted, activeColor: Brand.sand),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Brand.text),
          onPressed: () =>
              context.go(AppRoutes.localUserHome, extra: _profile),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: DeltaniumTheme.dividerDark),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Brand.mossDeep.withValues(alpha: 0.85),
                            Brand.inkSoft,
                            Brand.panel,
                          ],
                        ),
                        border: Border.all(color: Brand.line),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      bottom: -36,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Brand.ink, width: 4),
                        ),
                        child: CircleAvatar(
                          radius: 42,
                          backgroundImage: _profile.avatarUrl != null &&
                                  _profile.avatarUrl!.isNotEmpty
                              ? NetworkImage(_profile.avatarUrl!)
                              : null,
                          backgroundColor: Brand.panel,
                          child: _profile.avatarUrl == null ||
                                  _profile.avatarUrl!.isEmpty
                              ? Text(
                                  initial,
                                  style: GoogleFonts.syne(
                                    color: Brand.sand,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 12,
                      child: OutlinedButton(
                        onPressed: _showEditProfileDialog,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Brand.text,
                          side: const BorderSide(color: Brand.line),
                          backgroundColor: Brand.ink.withValues(alpha: 0.55),
                        ),
                        child: const Text('Edit profile'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 52),
                Text(
                  displayName,
                  style: GoogleFonts.syne(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Brand.text,
                  ),
                ),
                if ((_profile.email ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _profile.email!,
                      style: GoogleFonts.manrope(color: Brand.muted, fontSize: 14),
                    ),
                  ),
                if ((_profile.bio ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _profile.bio!,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      height: 1.45,
                      color: Brand.text,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Brand.panel,
                    borderRadius: BorderRadius.circular(Brand.radius + 6),
                    border: Border.all(color: Brand.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.key_rounded, size: 18, color: Brand.sand),
                          const SizedBox(width: 8),
                          Text(
                            'Public key',
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Brand.text,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => _copyPublicKey(context),
                            icon: const Icon(Icons.copy_rounded, size: 18, color: Brand.sand),
                            tooltip: 'Copy public key',
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Brand.moss.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(Brand.radius),
                          border: Border.all(color: Brand.moss.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          'Compressed · 66 chars',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Brand.moss,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Brand.inkSoft,
                          borderRadius: BorderRadius.circular(Brand.radius),
                        ),
                        child: Text(
                          _getCompressedPublicKey(_profile.publicKey),
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            height: 1.4,
                            color: Brand.text,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Share this key so others can send you encrypted files and messages.',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          height: 1.4,
                          color: Brand.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Wallet',
                  style: GoogleFonts.syne(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Brand.text,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Brand.panel,
                    borderRadius: BorderRadius.circular(Brand.radius + 6),
                    border: Border.all(color: Brand.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _walletLoading
                            ? 'Loading…'
                            : DFormat.exact(_dBalance ?? 0),
                        style: GoogleFonts.syne(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Brand.sand,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Service credit: 1 D = 1 VND · 1 DLT = 1.000.000 D, backed 1:1 by VND. '
                        'Top up by bank transfer / VietQR (3% fee).',
                        style: GoogleFonts.manrope(color: Brand.muted, fontSize: 12, height: 1.4),
                      ),
                      _usageSummary(),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _showTopUpDialog,
                            style: FilledButton.styleFrom(
                              backgroundColor: Brand.sand,
                              foregroundColor: Brand.ink,
                            ),
                            child: const Text('Top up'),
                          ),
                          OutlinedButton(
                            onPressed: _loadWallet,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Brand.text,
                              side: const BorderSide(color: Brand.line),
                            ),
                            child: const Text('Refresh'),
                          ),
                          OutlinedButton(
                            onPressed: () => showMyTopUps(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Brand.text,
                              side: const BorderSide(color: Brand.line),
                            ),
                            child: Text(tr('topup.list.title')),
                          ),
                          OutlinedButton(
                            onPressed: _showPlanDialog,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Brand.text,
                              side: const BorderSide(color: Brand.line),
                            ),
                            child: const Text('Subscription price'),
                          ),
                          OutlinedButton(
                            onPressed: _showEgressCapDialog,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Brand.text,
                              side: const BorderSide(color: Brand.line),
                            ),
                            child: const Text('Bandwidth cap'),
                          ),
                          OutlinedButton(
                            onPressed: _showRedeemDialog,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Brand.text,
                              side: const BorderSide(color: Brand.line),
                            ),
                            child: const Text('Redeem'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Account',
                  style: GoogleFonts.syne(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Brand.text,
                  ),
                ),
                const SizedBox(height: 12),
                _infoRow(Icons.badge_outlined, 'Name', _profile.fullName ?? '—'),
                _infoRow(Icons.cake_outlined, 'Birthday', _formatBirthday(_profile.dateOfBirth)),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: _handleLogout,
                  icon: const Icon(Icons.logout_rounded, color: Brand.danger),
                  label: Text(
                    'Logout',
                    style: GoogleFonts.manrope(
                      color: Brand.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Brand.danger.withValues(alpha: 0.35)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Brand.muted),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.manrope(
              color: Brand.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.manrope(
                color: Brand.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
} 