import 'dart:convert';

import 'package:bip39/bip39.dart' as bip39;
import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/rekey_sync_service.dart';
import 'package:deltanium_app/services/user_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  String? _errorMessage;

  final _registerFormKey = GlobalKey<FormState>();
  String? _mnemonic;
  String? _publicKey;
  bool _isRegistering = false;
  String? _registerErrorMessage;

  List<Map<String, dynamic>> _localUsers = [];

  TextStyle get _body => GoogleFonts.manrope(color: Brand.text, height: 1.45);
  TextStyle get _muted => GoogleFonts.manrope(color: Brand.muted, height: 1.4);
  TextStyle get _display => GoogleFonts.syne(
        color: Brand.text,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
      );

  @override
  void initState() {
    super.initState();
    AppLogger.log('Login Screen initialized');
    _loadLocalUsers();
  }

  Future<void> _loadLocalUsers() async {
    final users = await CryptoService.getSavedUsers();
    if (mounted) setState(() => _localUsers = users);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({required String label, String? hint}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Brand.radius),
      borderSide: const BorderSide(color: Brand.line),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: _muted,
      hintStyle: _muted,
      filled: true,
      fillColor: Brand.inkSoft,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Brand.sand, width: 1.4),
      ),
      errorBorder: border.copyWith(borderSide: const BorderSide(color: Brand.danger)),
      focusedErrorBorder: border.copyWith(borderSide: const BorderSide(color: Brand.danger)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  ButtonStyle get _primaryButton => FilledButton.styleFrom(
        backgroundColor: Brand.sand,
        foregroundColor: Brand.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.radius)),
      );

  ButtonStyle get _ghostButton => OutlinedButton.styleFrom(
        foregroundColor: Brand.text,
        side: const BorderSide(color: Brand.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.radius)),
      );

  Future<void> _showRestoreDialog() async {
    final phraseController = TextEditingController();
    String? localError;
    var restoring = false;

    await showDialog(
      context: context,
      barrierDismissible: !restoring,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Material(
                  color: Brand.panel,
                  borderRadius: BorderRadius.circular(Brand.radius + 4),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Restore identity', style: _display.copyWith(fontSize: 22)),
                            ),
                            IconButton(
                              onPressed: restoring ? null : () => Navigator.pop(dialogContext),
                              icon: const Icon(Icons.close, color: Brand.muted),
                            ),
                          ],
                        ),
                        Text(
                          'Enter the 12-word recovery phrase from when you created the account. No password is stored on the network.',
                          style: _muted,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: phraseController,
                          minLines: 3,
                          maxLines: 4,
                          enabled: !restoring,
                          style: _body,
                          decoration: _fieldDecoration(
                            label: 'Recovery phrase',
                            hint: 'word1 word2 word3 …',
                          ),
                        ),
                        if (localError != null) ...[
                          const SizedBox(height: 12),
                          Text(localError!, style: GoogleFonts.manrope(color: Brand.danger, height: 1.35)),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: restoring
                                ? null
                                : () async {
                                    final phrase = phraseController.text
                                        .trim()
                                        .toLowerCase()
                                        .replaceAll(RegExp(r'\s+'), ' ');
                                    if (!bip39.validateMnemonic(phrase)) {
                                      setDialogState(() => localError = 'Invalid recovery phrase.');
                                      return;
                                    }
                                    setDialogState(() {
                                      restoring = true;
                                      localError = null;
                                    });
                                    try {
                                      final keyPair = CryptoService.generateKeyPairFromMnemonic(phrase);
                                      final pubkey = CryptoService.getPublicKeyHex(keyPair);
                                      final profile = await UserService().getUserProfile(pubkey);
                                      if (profile == null || (profile.email ?? '').isEmpty) {
                                        setDialogState(() {
                                          restoring = false;
                                          localError = 'No registered account found for this phrase.';
                                        });
                                        return;
                                      }
                                      await CryptoService.saveUser(profile.email!, phrase, pubkey);
                                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                                      await _loginWithLocalUser({
                                        'email': profile.email,
                                        'mnemonic': phrase,
                                        'pubkey': pubkey,
                                      });
                                    } catch (e) {
                                      setDialogState(() {
                                        restoring = false;
                                        localError = 'Restore failed: $e';
                                      });
                                    }
                                  },
                            style: _primaryButton,
                            child: restoring
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Brand.ink),
                                  )
                                : Text(
                                    'Restore & continue',
                                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    phraseController.dispose();
  }

  Future<void> _showRegistrationDialog() async {
    setState(() {
      _mnemonic = null;
      _publicKey = null;
      _registerErrorMessage = null;
      _isRegistering = false;
    });

    final fullNameController = TextEditingController();
    final bioController = TextEditingController();
    final avatarUrlController = TextEditingController();
    DateTime? selectedDateOfBirth;

    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Material(
                  color: Brand.panel,
                  borderRadius: BorderRadius.circular(Brand.radius + 4),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                    child: Form(
                      key: _registerFormKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _mnemonic == null ? 'Create account' : 'Save your keys',
                                  style: _display.copyWith(fontSize: 22),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                icon: const Icon(Icons.close, color: Brand.muted),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                          Text(
                            _mnemonic == null
                                ? 'Your identity starts on this device. We never store a password — keep your recovery phrase safe.'
                                : 'Write these words down offline. Anyone with them can control this identity.',
                            style: _muted,
                          ),
                          const SizedBox(height: 22),
                          if (_mnemonic == null) ...[
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: _body,
                              decoration: _fieldDecoration(label: 'Email'),
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'Enter your email';
                                if (!value.contains('@')) return 'Enter a valid email';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: fullNameController,
                              style: _body,
                              decoration: _fieldDecoration(label: 'Full name'),
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'Enter your full name';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            InkWell(
                              borderRadius: BorderRadius.circular(Brand.radius),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setDialogState(() => selectedDateOfBirth = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: _fieldDecoration(label: 'Date of birth'),
                                child: Text(
                                  selectedDateOfBirth != null
                                      ? '${selectedDateOfBirth!.day.toString().padLeft(2, '0')}/'
                                          '${selectedDateOfBirth!.month.toString().padLeft(2, '0')}/'
                                          '${selectedDateOfBirth!.year}'
                                      : 'Select date',
                                  style: selectedDateOfBirth != null ? _body : _muted,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: bioController,
                              maxLines: 2,
                              style: _body,
                              decoration: _fieldDecoration(label: 'Bio (optional)'),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: avatarUrlController,
                              style: _body,
                              decoration: _fieldDecoration(label: 'Avatar URL (optional)'),
                            ),
                            if (_registerErrorMessage != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Brand.danger.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(Brand.radius),
                                  border: Border.all(color: Brand.danger.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  _registerErrorMessage!,
                                  style: GoogleFonts.manrope(color: Brand.sandBright, height: 1.35),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 48,
                              child: FilledButton(
                                onPressed: _isRegistering
                                    ? null
                                    : () async {
                                        if (selectedDateOfBirth == null) {
                                          setDialogState(() {
                                            _registerErrorMessage = 'Please select your date of birth.';
                                          });
                                          return;
                                        }
                                        if (!_registerFormKey.currentState!.validate()) return;
                                        setDialogState(() {
                                          _isRegistering = true;
                                          _registerErrorMessage = null;
                                        });
                                        try {
                                          final mnemonic = bip39.generateMnemonic();
                                          final keyPair =
                                              CryptoService.generateKeyPairFromMnemonic(mnemonic);
                                          final publicKeyHex = CryptoService.getPublicKeyHex(keyPair);
                                          final timestamp =
                                              DateTime.now().millisecondsSinceEpoch ~/ 1000;
                                          final dobStr =
                                              '${selectedDateOfBirth!.year.toString().padLeft(4, '0')}-'
                                              '${selectedDateOfBirth!.month.toString().padLeft(2, '0')}-'
                                              '${selectedDateOfBirth!.day.toString().padLeft(2, '0')}';
                                          final email = _emailController.text.trim();
                                          final fullName = fullNameController.text.trim();
                                          final signableData = '$email:$fullName:$dobStr:$timestamp';
                                          final signature = await CryptoService.sign(
                                            signableData,
                                            kIsWeb ? mnemonic : keyPair,
                                          );
                                          final registerRequest = {
                                            'publicKey': publicKeyHex,
                                            'email': email,
                                            'fullName': fullName,
                                            'dateOfBirth': selectedDateOfBirth!.toIso8601String(),
                                            'bio': bioController.text.trim(),
                                            'avatarUrl': avatarUrlController.text.trim(),
                                            'signature': signature,
                                            'timestamp': timestamp,
                                          };
                                          final url = '${AppConstants.apiBaseUrl}/user/register';
                                          final bodyJson = json.encode(registerRequest);
                                          AppLogger.log('[REGISTER] POST $url');
                                          final response = await http
                                              .post(
                                                Uri.parse(url),
                                                headers: {'Content-Type': 'application/json'},
                                                body: bodyJson,
                                              )
                                              .timeout(const Duration(seconds: 20));
                                          AppLogger.log('[REGISTER] Status: ${response.statusCode}');
                                          if (response.statusCode == 200) {
                                            setDialogState(() {
                                              _mnemonic = mnemonic;
                                              _publicKey = publicKeyHex;
                                              _isRegistering = false;
                                            });
                                          } else {
                                            final raw = response.body;
                                            String message;
                                            try {
                                              final errorData = json.decode(raw);
                                              message = errorData['message']?.toString() ?? raw;
                                            } catch (_) {
                                              message = raw.isEmpty
                                                  ? 'Registration failed. Please try again.'
                                                  : raw;
                                            }
                                            setDialogState(() {
                                              _registerErrorMessage = message;
                                              _isRegistering = false;
                                            });
                                          }
                                        } catch (e) {
                                          setDialogState(() {
                                            _registerErrorMessage = 'An error occurred: $e';
                                            _isRegistering = false;
                                          });
                                        }
                                      },
                                style: _primaryButton,
                                child: _isRegistering
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Brand.ink),
                                      )
                                    : Text(
                                        'Create account',
                                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15),
                                      ),
                              ),
                            ),
                          ] else ...[
                            Text('Recovery phrase', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Brand.text)),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Brand.inkSoft,
                                borderRadius: BorderRadius.circular(Brand.radius + 2),
                                border: Border.all(color: Brand.line),
                              ),
                              child: SelectableText(_mnemonic!, style: _body.copyWith(fontSize: 15, height: 1.55)),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _mnemonic!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Recovery phrase copied')),
                                  );
                                },
                                style: _ghostButton,
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copy phrase'),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text('Public key', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Brand.text)),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Brand.inkSoft,
                                borderRadius: BorderRadius.circular(Brand.radius + 2),
                                border: Border.all(color: Brand.line),
                              ),
                              child: SelectableText(_publicKey!, style: _muted.copyWith(fontSize: 12)),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 44,
                              child: OutlinedButton(
                                onPressed: () async {
                                  await CryptoService.saveUser(
                                    _emailController.text.trim(),
                                    _mnemonic!,
                                    _publicKey!,
                                  );
                                  await _loadLocalUsers();
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Saved on this device')),
                                  );
                                },
                                style: _ghostButton,
                                child: const Text('Save on this device'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 48,
                              child: FilledButton(
                                // Sign straight in with the new identity (it used to only close the dialog,
                                // leaving the user on the login screen with no session).
                                onPressed: () async {
                                  final user = {
                                    'email': _emailController.text.trim(),
                                    'mnemonic': _mnemonic!,
                                    'pubkey': _publicKey!,
                                  };
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Account created. Keep your recovery phrase safe.'),
                                    ),
                                  );
                                  await _loginWithLocalUser(user);
                                },
                                style: _primaryButton,
                                child: Text('Continue to the app',
                                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
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
      fullNameController.dispose();
      bioController.dispose();
      avatarUrlController.dispose();
    });
  }

  Future<void> _loginWithLocalUser(Map<String, dynamic> user) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = user['email'];
      final mnemonic = user['mnemonic'];
      final pubkey = user['pubkey'];
      AppLogger.log('Logging in with local user: $email');
      await _authService.saveAuthInfo(email, mnemonic, pubkey);
      _syncRekeysAfterLogin(mnemonic, pubkey);
      final userService = UserService();
      final profileResult = await userService.getUserProfile(pubkey);

      if (profileResult != null) {
        if (mounted) context.go(AppRoutes.localUserHome, extra: profileResult);
      } else {
        final authResult = await userService.authenticateLocalUser(email, mnemonic, pubkey);
        if (authResult != null) {
          final userProfile = UserProfile(
            email: email,
            publicKey: pubkey,
            fullName: authResult['fullName'],
            avatarUrl: authResult['avatarUrl'],
            bio: authResult['bio'],
          );
          if (mounted) context.go(AppRoutes.localUserHome, extra: userProfile);
        } else {
          setState(() {
            _errorMessage = 'Failed to authenticate. API may be unavailable.';
          });
        }
      }
    } catch (e) {
      AppLogger.log('Local user login error: $e');
      setState(() => _errorMessage = 'An error occurred: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _syncRekeysAfterLogin(String mnemonic, String publicKey) {
    RekeySyncService.syncFollowersAndGenerateRekeys(
      mnemonic: mnemonic,
      userPublicKey: publicKey,
    ).catchError((e) {
      AppLogger.log('Background rekey sync error: $e');
    });
    RekeySyncService.syncSubscriberRekeys(mnemonic: mnemonic, userPublicKey: publicKey);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 960;

    return Scaffold(
      backgroundColor: Brand.ink,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0xFF0C1210),
                    Color(0xFF15201B),
                    Color(0xFF0A100E),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Brand.moss.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Brand.sand.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Brand.maxWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 32 : 20,
                    vertical: isWide ? 36 : 20,
                  ),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Expanded(flex: 5, child: _BrandPanel()),
                            const SizedBox(width: 28),
                            Expanded(flex: 4, child: _buildAuthCard()),
                          ],
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              const _BrandPanel(compact: true),
                              const SizedBox(height: 20),
                              _buildAuthCard(),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard() {
    final hasSaved = _localUsers.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      decoration: BoxDecoration(
        color: Brand.panel,
        borderRadius: BorderRadius.circular(Brand.radius + 4),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasSaved ? 'Welcome back' : 'Join the network',
            style: _display.copyWith(fontSize: 28, letterSpacing: -0.6),
          ),
          const SizedBox(height: 8),
          Text(
            hasSaved
                ? 'Continue with an identity saved on this device, or restore with your recovery phrase.'
                : 'Create your identity on this device. Your keys stay with you — we never read your private content.',
            style: _muted,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(_errorMessage!, style: GoogleFonts.manrope(color: Brand.danger, height: 1.35)),
          ],
          if (hasSaved) ...[
            const SizedBox(height: 20),
            Text('On this device', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Brand.text)),
            const SizedBox(height: 10),
            ..._localUsers.map(
              (user) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildLocalUserRow(user),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(color: Brand.line),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 22),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _isLoading ? null : _showRegistrationDialog,
              style: _primaryButton,
              child: Text(
                hasSaved ? 'Create another account' : 'Become a user',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: _isLoading ? null : _showRestoreDialog,
              style: _ghostButton,
              child: Text(
                'Restore with recovery phrase',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ),
          if (_isLoading) ...[
            const SizedBox(height: 16),
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Brand.sand),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocalUserRow(Map<String, dynamic> user) {
    final email = user['email'] ?? '';
    final pubkey = user['pubkey'] ?? '';
    return Material(
      color: Brand.inkSoft,
      borderRadius: BorderRadius.circular(Brand.radius + 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(Brand.radius + 2),
        onTap: _isLoading ? null : () => _loginWithLocalUser(user),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: Brand.panel,
                child: Icon(Icons.person, size: 18, color: Brand.muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      email,
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: Brand.text),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      pubkey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _muted.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Brand.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 24 : 36),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.radius + 4),
        border: Border.all(color: Brand.line),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2822), Color(0xFF121A16)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Never wrap the wordmark mid-word on narrow screens; shrink it instead.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Deltanium',
                  style: GoogleFonts.syne(
                    fontSize: compact ? 34 : 48,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                    color: Brand.text,
                  ),
                ),
                TextSpan(
                  text: '.',
                  style: GoogleFonts.syne(
                    fontSize: compact ? 34 : 48,
                    fontWeight: FontWeight.w800,
                    color: Brand.sand,
                  ),
                ),
              ],
            ),
          ),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Your social life — without selling your privacy.',
              style: GoogleFonts.manrope(
                fontSize: compact ? 16 : 18,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Brand.sandBright,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Post, follow friends, and chat on a network you actually own. Your keys stay with you.',
              style: GoogleFonts.manrope(
                fontSize: compact ? 14 : 15,
                height: 1.5,
                color: Brand.muted,
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 28),
            const _BrandPoint(text: 'You hold the keys'),
            const SizedBox(height: 10),
            const _BrandPoint(text: 'Private means private'),
            const SizedBox(height: 10),
            const _BrandPoint(text: 'A network you help grow'),
          ],
        ],
      ),
    );
  }
}

class _BrandPoint extends StatelessWidget {
  const _BrandPoint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle_outline, size: 18, color: Brand.moss),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.manrope(color: Brand.text, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
