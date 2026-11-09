import 'dart:typed_data';

/// Web / non-FFI stub. Umbral PRE native library is unavailable on Flutter web.
class PreFfi {
  PreFfi._();

  static PreFfi? _instance;
  static PreFfi instance() {
    _instance ??= PreFfi._();
    return _instance!;
  }

  Never _unsupported() =>
      throw UnsupportedError(
        'Umbral PRE (dart:ffi) is not available on this platform. '
        'Use iOS/Android/desktop for follower-encrypted posts; '
        'public posts and chat still work on web.',
      );

  Uint8List encapsulateWithTag({
    required Uint8List pkAuthor,
    required String tag,
    required Uint8List key,
  }) =>
      _unsupported();

  Uint8List generateRekey({
    required Uint8List skAuthor,
    required Uint8List pkRecipient,
    required String tag,
  }) =>
      _unsupported();

  Uint8List reencrypt({
    required Uint8List encapsulatedForAuthor,
    required Uint8List rekey,
  }) =>
      _unsupported();

  Uint8List decapsulateForRecipient({
    required Uint8List encapsulatedForRecipient,
    required Uint8List skRecipient,
    required String tag,
  }) =>
      _unsupported();
}
