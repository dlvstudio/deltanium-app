import 'dart:convert';

import 'package:bip39/bip39.dart' as bip39;
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/models/signed_register_request.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// A new identity: the recovery phrase stays on this device; only the public key and profile go to Central.
class RegisteredIdentity {
  final String mnemonic;
  final String publicKey;
  const RegisteredIdentity(this.mnemonic, this.publicKey);
}

class RegistrationException implements Exception {
  final String message;
  RegistrationException(this.message);
  @override
  String toString() => message;
}

/// Creates keys on the device and registers the public profile with Central (signed with the new key).
class RegistrationService {
  RegistrationService._();

  static Future<RegisteredIdentity> register({
    required String email,
    required String fullName,
    DateTime? dateOfBirth,
    String bio = '',
    String? apiBaseUrl,
    /// Register an existing recovery phrase instead of a new one (fixed QA identities on testnet).
    String? mnemonic,
  }) async {
    mnemonic ??= bip39.generateMnemonic();
    final keyPair = CryptoService.generateKeyPairFromMnemonic(mnemonic);
    final publicKeyHex = CryptoService.getPublicKeyHex(keyPair);
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final unsigned = SignedRegisterRequest(
      publicKey: publicKeyHex,
      email: email.trim(),
      fullName: fullName.trim(),
      dateOfBirth: dateOfBirth,
      bio: bio.trim(),
      signature: '',
      timestamp: timestamp,
    );
    final signature = await CryptoService.sign(unsigned.getSignableData(), kIsWeb ? mnemonic : keyPair);
    final signed = SignedRegisterRequest(
      publicKey: publicKeyHex,
      email: unsigned.email,
      fullName: unsigned.fullName,
      dateOfBirth: dateOfBirth,
      bio: unsigned.bio,
      signature: signature,
      timestamp: timestamp,
    );

    final url = '${apiBaseUrl ?? AppConstants.apiBaseUrl}/user/register';
    AppLogger.log('[REGISTER] POST $url for ${publicKeyHex.substring(0, 12)}...');
    final response = await http
        .post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: json.encode(signed.toJson()))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 200) return RegisteredIdentity(mnemonic, publicKeyHex);

    final raw = response.body;
    if (response.statusCode == 429) throw RegistrationException('HTTP 429: ${raw.isEmpty ? 'too many new accounts from this network today' : raw}');
    String message;
    try {
      message = (json.decode(raw) as Map)['message']?.toString() ?? raw;
    } catch (_) {
      message = raw.isEmpty ? 'Registration failed (HTTP ${response.statusCode}). Please try again.' : raw;
    }
    throw RegistrationException(message);
  }
}
