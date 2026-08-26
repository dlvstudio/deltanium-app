import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/models/register_request.dart';
import 'package:deltanium_app/models/signed_register_request.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:go_router/go_router.dart';
import 'package:deltanium_app/app/router.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/rekey_sync_service.dart';
import 'package:deltanium_app/services/auth_service.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  // Registration form controllers
  final _registerFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _bioController = TextEditingController();
  DateTime? _selectedDateOfBirth;
  String? _mnemonic;
  String? _publicKey;
  bool _isRegistering = false;
  String? _registerErrorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _fullNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _showRegistrationDialog() async {
    setState(() {
      _mnemonic = null;
      _publicKey = null;
    });
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _registerFormKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Create Account',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: isDarkMode ? DeltaniumTheme.darkTextSecondaryColor : DeltaniumTheme.lightTextSecondaryColor,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (_mnemonic == null) ...[
                        // Email field
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!value.contains('@')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Full Name field
                        TextFormField(
                          controller: _fullNameController,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your full name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Date of Birth field
                        InkWell(
                          onTap: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
                              firstDate: DateTime(1900),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() {
                                _selectedDateOfBirth = picked;
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Date of Birth',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              _selectedDateOfBirth != null
                                  ? '${_selectedDateOfBirth!.day}/${_selectedDateOfBirth!.month}/${_selectedDateOfBirth!.year}'
                                  : 'Select date',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Bio field
                        TextFormField(
                          controller: _bioController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Bio',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_registerErrorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              _registerErrorMessage!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isRegistering ? null : () async {
                              if (_registerFormKey.currentState!.validate()) {
                                setState(() {
                                  _isRegistering = true;
                                  _registerErrorMessage = null;
                                });
                                try {
                                  await _register();
                                } catch (e) {
                                  setState(() {
                                    _registerErrorMessage = 'An error occurred: $e';
                                    _isRegistering = false;
                                  });
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isRegistering
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text('Create Account'),
                          ),
                        ),
                      ] else ...[
                        // Display mnemonic and public key
                        Text(
                          'Please save your mnemonic phrase securely:',
                          style: TextStyle(
                            color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _mnemonic!,
                                  style: TextStyle(
                                    color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _mnemonic!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Mnemonic copied to clipboard')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Your public key:',
                          style: TextStyle(
                            color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _publicKey!,
                                  style: TextStyle(
                                    color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _publicKey!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Public key copied to clipboard')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              
                              // 🔄 PRE: Trigger rekey sync after successful login
                              _syncRekeysAfterLogin(_mnemonic!, _publicKey!);
                              
                              context.go(AppRoutes.home);
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Continue to App'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _register() async {
    if (_registerFormKey.currentState!.validate()) {
      setState(() {
        _isRegistering = true;
        _registerErrorMessage = null;
      });

      try {
        // 🔧 CLIENT-SIDE KEY GENERATION - Generate mnemonic and key pair locally
        AppLogger.log('Generating keys client-side...');
        final mnemonic = bip39.generateMnemonic();
        final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
        final publicKeyHex = CryptoService.getPublicKeyHex(keyPair);
        
        AppLogger.log('Generated mnemonic: ${mnemonic.substring(0, 20)}...');
        AppLogger.log('Generated public key: ${publicKeyHex.substring(0, 20)}...');

        // Generate timestamp for signature
        final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000);
        AppLogger.log('Generated timestamp: $timestamp');

        // Create signable data with timestamp
        final request = SignedRegisterRequest(
          publicKey: publicKeyHex,
          email: _emailController.text.trim(),
          fullName: _fullNameController.text.trim(),
          dateOfBirth: _selectedDateOfBirth,
          bio: _bioController.text.trim(),
          signature: '',  // Will be set after signing
          timestamp: timestamp,
        );
        // DEBUG: show components for server verification
        final dbgDob = _selectedDateOfBirth != null
            ? '${_selectedDateOfBirth!.year.toString().padLeft(4, '0')}-${_selectedDateOfBirth!.month.toString().padLeft(2, '0')}-${_selectedDateOfBirth!.day.toString().padLeft(2, '0')}'
            : '';
        AppLogger.log('[REGISTER] email=${request.email}, fullName=${request.fullName}, dob=${dbgDob}, ts=${timestamp}');

        // Sign the data using client-generated keys (includes timestamp)
        final signable = request.getSignableData();
        AppLogger.log('[REGISTER] signableData (client): ' + signable);
        final signature = await CryptoService.sign(
          signable,
          kIsWeb ? mnemonic : keyPair,
        );
        AppLogger.log('Generated signature (base64, len=' + signature.length.toString() + '): ' + (signature.length > 32 ? signature.substring(0, 32) + '...' : signature));

        // Create final request with signature
        final signedRequest = SignedRegisterRequest(
          publicKey: publicKeyHex,
          email: request.email,
          fullName: request.fullName,
          dateOfBirth: request.dateOfBirth,
          bio: request.bio,
          signature: signature,
          timestamp: timestamp,
        );

        // Send registration request
        final url = AppConstants.apiBaseUrl + '/user/register';
        final bodyJson = json.encode(signedRequest.toJson());
        AppLogger.log('[REGISTER] POST ' + url);
        AppLogger.log('[REGISTER] Body JSON: ' + (bodyJson.length > 300 ? bodyJson.substring(0, 300) + '...' : bodyJson));
        final response = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: bodyJson,
            )
            .timeout(const Duration(seconds: 20));
        AppLogger.log('[REGISTER] Response status: ${response.statusCode}');
        AppLogger.log('[REGISTER] Response body  : ${response.body}');

        if (response.statusCode == 200) {
          setState(() {
            _mnemonic = mnemonic;
            _publicKey = publicKeyHex;
            _isRegistering = false;
          });
          AppLogger.log('Registration successful! Keys generated client-side.');
        } else {
          final raw = response.body;
          String message;
          try {
            final errorData = json.decode(raw);
            message = errorData['message']?.toString() ?? raw;
          } catch (_) {
            message = raw.isEmpty ? 'Registration failed. Please try again.' : raw;
          }
          setState(() {
            _registerErrorMessage = message;
            _isRegistering = false;
          });
        }
      } catch (e) {
        AppLogger.log('Registration error: $e');
        setState(() {
          _registerErrorMessage = 'An error occurred: $e';
          _isRegistering = false;
        });
      }
    }
  }

  void _login() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        // TODO: Implement actual login with blockchain authentication
        await Future.delayed(const Duration(seconds: 2)); // Simulate network delay
        
        if (!mounted) return;
        
        // 🔄 PRE: Get auth info and trigger rekey sync
        final authService = AuthService();
        final authInfo = await authService.getCurrentAuthInfo();
        if (authInfo != null) {
          final mnemonic = authInfo['mnemonic'];
          final publicKey = authInfo['publicKey'];
          if (mnemonic is String && publicKey is String) {
            _syncRekeysAfterLogin(mnemonic, publicKey);
          }
        }
        
        // Navigate to feed screen on success
        AppLogger.log('Validation successful! Redirecting...');
        if (mounted) {
          context.go(AppRoutes.home);
        }
      } catch (e) {
        if (!mounted) return;
        
        setState(() {
          _errorMessage = 'Login failed: ${e.toString()}';
        });
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }
  
  /// Trigger background rekey sync after successful login
  void _syncRekeysAfterLogin(String mnemonic, String publicKey) {
    AppLogger.log('🔄 LOGIN: Starting background rekey sync...');
    
    // Run sync in background (don't await to avoid blocking navigation)
    RekeySyncService.syncFollowersAndGenerateRekeys(
      mnemonic: mnemonic,
      userPublicKey: publicKey,
    ).catchError((e) {
      AppLogger.log('❌ LOGIN: Background rekey sync error: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: DeltaniumTheme.spacingLarge,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Center(
                    child: Icon(
                      Icons.bubble_chart,  // Placeholder for X logo
                      size: 40,
                      color: isDarkMode 
                          ? DeltaniumTheme.primaryTan 
                          : DeltaniumTheme.primaryBrown,
                    ),
                  ),
                  
                  const SizedBox(height: DeltaniumTheme.spacingXLarge),
                  
                  // Title
                  Text(
                    'Sign in to Deltanium',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: isDarkMode 
                          ? DeltaniumTheme.primaryTan 
                          : DeltaniumTheme.primaryBrown,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.left,
                  ),
                  
                  const SizedBox(height: DeltaniumTheme.spacingLarge),
                  
                  // Username field
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Username, phone, or email',
                      labelStyle: TextStyle(
                        color: isDarkMode 
                            ? DeltaniumTheme.darkTextSecondaryColor 
                            : DeltaniumTheme.lightTextSecondaryColor,
                      ),
                      filled: true,
                      fillColor: isDarkMode 
                          ? DeltaniumTheme.surfaceDark 
                          : DeltaniumTheme.surfaceLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDarkMode 
                              ? DeltaniumTheme.primaryTan 
                              : DeltaniumTheme.primaryBrown,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDarkMode 
                              ? DeltaniumTheme.primaryTan 
                              : DeltaniumTheme.primaryBrown,
                          width: 2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDarkMode 
                              ? DeltaniumTheme.darkDividerColor 
                              : DeltaniumTheme.lightDividerColor,
                        ),
                      ),
                    ),
                    style: TextStyle(
                      color: isDarkMode 
                          ? DeltaniumTheme.darkTextPrimaryColor 
                          : DeltaniumTheme.lightTextPrimaryColor,
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your username';
                      }
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: DeltaniumTheme.spacingMedium),
                  
                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: TextStyle(
                        color: isDarkMode 
                            ? DeltaniumTheme.darkTextSecondaryColor 
                            : DeltaniumTheme.lightTextSecondaryColor,
                      ),
                      filled: true,
                      fillColor: isDarkMode 
                          ? DeltaniumTheme.surfaceDark 
                          : DeltaniumTheme.surfaceLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDarkMode 
                              ? DeltaniumTheme.primaryTan 
                              : DeltaniumTheme.primaryBrown,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDarkMode 
                              ? DeltaniumTheme.primaryTan 
                              : DeltaniumTheme.primaryBrown,
                          width: 2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDarkMode 
                              ? DeltaniumTheme.darkDividerColor 
                              : DeltaniumTheme.lightDividerColor,
                        ),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: isDarkMode 
                              ? DeltaniumTheme.darkTextSecondaryColor 
                              : DeltaniumTheme.lightTextSecondaryColor,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    style: TextStyle(
                      color: isDarkMode 
                          ? DeltaniumTheme.darkTextPrimaryColor 
                          : DeltaniumTheme.lightTextPrimaryColor,
                    ),
                    obscureText: _obscurePassword,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _login(),
                  ),
                  
                  const SizedBox(height: DeltaniumTheme.spacingLarge),
                  
                  // Login button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                      foregroundColor: DeltaniumTheme.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                      disabledBackgroundColor: isDarkMode 
                          ? DeltaniumTheme.darkTextDisabledColor 
                          : DeltaniumTheme.lightTextDisabledColor,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: DeltaniumTheme.white,
                            ),
                          )
                        : const Text(
                            'Log in',
                            style: TextStyle(
                              fontSize: DeltaniumTheme.fontSizeMedium,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  
                  const SizedBox(height: DeltaniumTheme.spacingMedium),
                  
                  // Forgot password
                  TextButton(
                    onPressed: null, // TODO: Implement forgot password route
                    style: TextButton.styleFrom(
                      foregroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                    ),
                    child: const Text('Forgot password?'),
                  ),
                  
                  const SizedBox(height: DeltaniumTheme.spacingLarge),
                  
                  // Divider with "or" text
                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: isDarkMode 
                              ? DeltaniumTheme.darkDividerColor 
                              : DeltaniumTheme.lightDividerColor,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DeltaniumTheme.spacingMedium,
                        ),
                        child: Text(
                          'or',
                          style: TextStyle(
                            color: isDarkMode 
                                ? DeltaniumTheme.darkTextSecondaryColor 
                                : DeltaniumTheme.lightTextSecondaryColor,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: isDarkMode 
                              ? DeltaniumTheme.darkDividerColor 
                              : DeltaniumTheme.lightDividerColor,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: DeltaniumTheme.spacingLarge),
                  
                  // Sign up button
                  TextButton(
                    onPressed: _showRegistrationDialog,
                    child: Text(
                      'Don\'t have an account? Sign up',
                      style: TextStyle(
                        color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown
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
  }
} 
