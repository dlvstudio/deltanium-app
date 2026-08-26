import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/data/mock/mock_auth_service.dart';
import 'package:deltanium_app/data/mock/mock_data.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:deltanium_app/config/constants.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:deltanium_app/services/user_service.dart';
import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/features/local_user/local_user_home_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/rekey_sync_service.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mockAuthService = MockAuthService();
  final _authService = AuthService();
  bool _isLoading = false;
  String? _errorMessage;

  // Add registration form controllers
  final _registerFormKey = GlobalKey<FormState>();
  String? _mnemonic;
  String? _publicKey;
  bool _isRegistering = false;
  String? _registerErrorMessage;

  // Local users state
  List<Map<String, dynamic>> _localUsers = [];

  @override
  void initState() {
    super.initState();
    // Print mock users for debugging
    AppLogger.log("Login Screen initialized");
    AppLogger.log("Mock users count: ${MockData.users.length}");
    for (var user in MockData.users) {
      AppLogger.log("Available user: ${user.email}");
    }
    _loadLocalUsers();
  }

  Future<void> _loadLocalUsers() async {
    final users = await CryptoService.getSavedUsers();
    if (mounted) {
      setState(() {
        _localUsers = users;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        // For debugging purposes
        final email = _emailController.text.trim();
        AppLogger.log("Login attempt with: $email");
        
        // Use direct login method for testing
        final user = await _mockAuthService.directLogin(email);
        
        if (user != null) {
          AppLogger.log("Login successful, navigating to home screen");
          if (mounted) {
            context.go(AppRoutes.home);
          }
        } else {
          AppLogger.log("Login failed: user not found");
          setState(() {
            _errorMessage = 'User not found. Please try one of the test accounts.';
          });
        }
      } catch (e) {
        AppLogger.log("Login error: $e");
        setState(() {
          _errorMessage = 'An error occurred: $e';
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

  // Helper function to login with test account
  void _loginWithTestAccount(String email) {
    _emailController.text = email;
    _passwordController.text = 'password'; // Dummy password
    _login();
  }

  Future<void> _showRegistrationDialog() async {
    setState(() {
      _mnemonic = null;
      _publicKey = null;
    });
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final _fullNameController = TextEditingController();
    final _bioController = TextEditingController();
    final _avatarUrlController = TextEditingController();
    DateTime? _selectedDateOfBirth;
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
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Bio (optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Avatar URL field
                        TextFormField(
                          controller: _avatarUrlController,
                          decoration: InputDecoration(
                            labelText: 'Avatar URL (optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Password field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Confirm Password field
                        TextFormField(
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (value != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
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
                                  // 1. Generate mnemonic (using bip39) and key pair (using CryptoService) locally
                                  final mnemonic = bip39.generateMnemonic();
                                  final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
                                  final publicKeyHex = CryptoService.getPublicKeyHex(keyPair);

                                  // 2. Generate timestamp for signature
                                  final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000);

                                  // 3. Build signable data string with timestamp (yyyy-MM-dd)
                                  final dobStr = _selectedDateOfBirth != null
                                      ? '${_selectedDateOfBirth!.year.toString().padLeft(4, '0')}-${_selectedDateOfBirth!.month.toString().padLeft(2, '0')}-${_selectedDateOfBirth!.day.toString().padLeft(2, '0')}'
                                      : '';
                                  final email = _emailController.text.trim();
                                  final fullName = _fullNameController.text.trim();
                                  final signableData = '$email:$fullName:$dobStr:$timestamp';
                                  AppLogger.log('[REGISTER] email=$email, fullName=$fullName, dob=$dobStr, ts=$timestamp');
                                  AppLogger.log('[REGISTER] signableData: ' + signableData);

                                  // 4. Sign the data
                                  final signature = await CryptoService.sign(signableData, kIsWeb ? mnemonic : keyPair);
                                  AppLogger.log('[REGISTER] signature(base64,len=${signature.length}): ' + (signature.length > 32 ? signature.substring(0, 32) + '...' : signature));

                                  // 5. Build the request object
                                  final registerRequest = {
                                    'publicKey': publicKeyHex,
                                    'email': _emailController.text.trim(),
                                    'fullName': _fullNameController.text.trim(),
                                    'dateOfBirth': _selectedDateOfBirth != null ? '${_selectedDateOfBirth!.toIso8601String()}' : null,
                                    'bio': _bioController.text.trim(),
                                    'avatarUrl': _avatarUrlController.text.trim(),
                                    'signature': signature,
                                    'timestamp': timestamp,
                                  };

                                  // 6. Send POST request
                                  final url = AppConstants.apiBaseUrl + '/user/register';
                                  final bodyJson = json.encode(registerRequest);
                                  AppLogger.log('[REGISTER] POST ' + url);
                                  AppLogger.log('[REGISTER] Body: ' + (bodyJson.length > 300 ? bodyJson.substring(0, 300) + '...' : bodyJson));
                                  final response = await http
                                      .post(
                                        Uri.parse(url),
                                        headers: {'Content-Type': 'application/json'},
                                        body: bodyJson,
                                      )
                                      .timeout(const Duration(seconds: 20));
                                  AppLogger.log('[REGISTER] Status: ${response.statusCode}');
                                  AppLogger.log('[REGISTER] Body  : ${response.body}');

                                  if (response.statusCode == 200) {
                                    setState(() {
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
                                      message = raw.isEmpty ? 'Registration failed. Please try again.' : raw;
                                    }
                                    setState(() {
                                      _registerErrorMessage = message;
                                      _isRegistering = false;
                                    });
                                  }
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
                      'Your Recovery Phrase',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Write down these 12 words in order and keep them safe. You\'ll need them to recover your account.',
                      style: TextStyle(
                        color: isDarkMode ? DeltaniumTheme.darkTextSecondaryColor : DeltaniumTheme.lightTextSecondaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDarkMode ? DeltaniumTheme.darkDividerColor : DeltaniumTheme.lightDividerColor,
                        ),
                      ),
                      child: Column(
                        children: [
                          SelectableText(
                            _mnemonic!,
                            style: TextStyle(
                              fontSize: 16,
                              color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _mnemonic!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Recovery phrase copied to clipboard')),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy to Clipboard'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Your Public Key',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDarkMode ? DeltaniumTheme.darkDividerColor : DeltaniumTheme.lightDividerColor,
                        ),
                      ),
                      child: Column(
                        children: [
                          SelectableText(
                            _publicKey!,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _publicKey!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Public key copied to clipboard')),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy to Clipboard'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () async {
                        await CryptoService.saveUser(
                          _emailController.text.trim(),
                          _mnemonic!,
                          _publicKey!,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('User saved locally.')),
                        );
                      },
                      child: const Text('Save User Locally'),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Account created successfully! Please save your recovery phrase.')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
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

  // Add this new method for local user login
  Future<void> _loginWithLocalUser(Map<String, dynamic> user) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = user['email'];
      final mnemonic = user['mnemonic'];
      final pubkey = user['pubkey'];
      
      AppLogger.log("Logging in with local user: $email");
      
      // Save as current user
      await _authService.saveAuthInfo(email, mnemonic, pubkey);
      
      // 🔄 PRE: Trigger rekey sync after successful login
      _syncRekeysAfterLogin(mnemonic, pubkey);
      
      // Create an instance of UserService
      final userService = UserService();
      
      // Try to get the user profile
      final profileResult = await userService.getUserProfile(pubkey);
      
      if (profileResult != null) {
        AppLogger.log("Profile retrieved successfully, navigating to local user home");
        if (mounted) {
          context.go(
            AppRoutes.localUserHome,
            extra: profileResult,
          );
        }
      } else {
        // If profile retrieval fails, try authenticating
        AppLogger.log("Profile retrieval failed, trying authentication");
        final authResult = await userService.authenticateLocalUser(email, mnemonic, pubkey);
        
        if (authResult != null) {
          // Create a UserProfile from authentication result
          final userProfile = UserProfile(
            email: email,
            publicKey: pubkey,
            fullName: authResult['fullName'],
            avatarUrl: authResult['avatarUrl'],
            bio: authResult['bio'],
          );
          
          AppLogger.log("Authentication successful, navigating to local user home");
          if (mounted) {
            context.go(
              AppRoutes.localUserHome,
              extra: userProfile,
            );
          }
        } else {
          AppLogger.log("Authentication failed");
        setState(() {
            _errorMessage = 'Failed to authenticate local user. API may be unavailable.';
        });
        }
      }
    } catch (e) {
      AppLogger.log("Local user login error: $e");
      setState(() {
        _errorMessage = 'An error occurred: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
      backgroundColor: isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  Icon(
                    Icons.diamond_outlined,
                    size: 60,
                    color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Log in to Deltanium',
                    style: TextStyle(
                      color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              style: TextStyle(
                                color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor
                              ),
                              decoration: InputDecoration(
                                labelText: 'Email',
                                labelStyle: TextStyle(
                                  color: isDarkMode ? DeltaniumTheme.darkTextSecondaryColor : DeltaniumTheme.lightTextSecondaryColor
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: isDarkMode ? DeltaniumTheme.darkDividerColor : DeltaniumTheme.lightDividerColor
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              style: TextStyle(
                                color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor
                              ),
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                labelStyle: TextStyle(
                                  color: isDarkMode ? DeltaniumTheme.darkTextSecondaryColor : DeltaniumTheme.lightTextSecondaryColor
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: isDarkMode ? DeltaniumTheme.darkDividerColor : DeltaniumTheme.lightDividerColor
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your password';
                                }
                                return null;
                              },
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage!,
                                style: TextStyle(color: DeltaniumTheme.errorColor),
                              ),
                            ],
                            const SizedBox(height: 32),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                ),
                              ),
                              child: _isLoading
                                  ? CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(DeltaniumTheme.white),
                                    )
                                  : Text(
                                      'Log in',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: DeltaniumTheme.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: _showRegistrationDialog,
                              child: Text(
                                'Don\'t have an account? Sign up',
                                style: TextStyle(
                                  color: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Divider(
                              color: isDarkMode ? DeltaniumTheme.darkDividerColor : DeltaniumTheme.lightDividerColor
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: Text(
                                'For testing, tap on an account to login directly:',
                                style: TextStyle(
                                  color: isDarkMode ? DeltaniumTheme.darkTextSecondaryColor : DeltaniumTheme.lightTextSecondaryColor
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final allCards = <Widget>[];
                                // Add local users
                                for (var user in _localUsers) {
                                  allCards.add(_buildLocalUserCard(user, isDarkMode));
                                }
                                // Add mock users
                                allCards.add(_buildTestLoginCard(
                                          'john@example.com',
                                          'John Doe',
                                          'https://randomuser.me/api/portraits/men/1.jpg',
                                          isDarkMode,
                                ));
                                allCards.add(_buildTestLoginCard(
                                          'alice@example.com',
                                          'Alice',
                                          'https://randomuser.me/api/portraits/women/2.jpg',
                                          isDarkMode,
                                ));
                                allCards.add(_buildTestLoginCard(
                                          'bob@example.com',
                                          'Bob',
                                          'https://randomuser.me/api/portraits/men/3.jpg',
                                          isDarkMode,
                                ));
                                
                                // Calculate appropriate width based on constraints
                                final cardWidth = (constraints.maxWidth / 3) - 16;
                                
                                // Use Wrap for responsive layout
                                return Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: allCards.map((card) => SizedBox(
                                    width: cardWidth,
                                    child: card
                                  )).toList(),
                                );
                              },
                            ),
                          ],
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
  }

  Widget _buildTestLoginCard(String email, String name, String imageUrl, bool isDarkMode) {
    return Card(
      color: isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
          backgroundImage: NetworkImage(imageUrl),
        ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
          name,
          style: TextStyle(
                          fontWeight: FontWeight.bold,
            color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        email,
                        style: TextStyle(
                          color: isDarkMode ? DeltaniumTheme.darkTextSecondaryColor : DeltaniumTheme.lightTextSecondaryColor,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _loginWithTestAccount(email),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                minimumSize: const Size.fromHeight(30),
                padding: const EdgeInsets.symmetric(vertical: 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Login', 
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold
                )
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Modify the _buildLocalUserCard method to use the new login method
  Widget _buildLocalUserCard(Map<String, dynamic> user, bool isDarkMode) {
    final email = user['email'] ?? '';
    final pubkey = user['pubkey'] ?? '';
    return Card(
      color: isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isDarkMode ? DeltaniumTheme.surfaceLight : DeltaniumTheme.surfaceDark,
                  child: const Icon(Icons.person, color: Colors.grey),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Local User',
                              style: TextStyle(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Local',
                              style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      Text(
          email,
          style: TextStyle(
                          color: isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              pubkey,
              style: TextStyle(
                color: isDarkMode ? DeltaniumTheme.darkTextSecondaryColor : DeltaniumTheme.lightTextSecondaryColor,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            ElevatedButton(
              onPressed: () => _loginWithLocalUser(user),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown,
                minimumSize: const Size.fromHeight(30),
                padding: const EdgeInsets.symmetric(vertical: 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Login', 
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold
                )
              ),
            ),
          ],
        ),
      ),
    );
  }
} 
