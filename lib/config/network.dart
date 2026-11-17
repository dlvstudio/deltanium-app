/// Which Deltanium network this build talks to. Set at build time with
/// `--dart-define=NETWORK_ID=deltanium-test`; empty (the default) is mainnet.
///
/// Every signature the app makes is over [scope] of the message, exactly like
/// NetworkScope.Scope on Central / Blocker / Store: unchanged on mainnet, "{id}\n{message}"
/// elsewhere. A signature made on testnet is therefore worthless on mainnet even with the same key.
class Network {
  static const String _raw = String.fromEnvironment('NETWORK_ID');

  static String get id {
    final v = _raw.trim().toLowerCase();
    return (v == 'mainnet' || v == 'main') ? '' : v;
  }

  static bool get isMainnet => id.isEmpty;

  static String get name => isMainnet ? 'mainnet' : id;

  static String scope(String message) => isMainnet ? message : '$id\n$message';
}
