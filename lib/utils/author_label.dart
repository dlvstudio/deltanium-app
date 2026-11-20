import 'package:deltanium_app/l10n/app_lang.dart';
import 'package:deltanium_app/services/crypto_service.dart';

/// How an author is shown on posts and comments: their own name when it was shared with the item,
/// "You" for the signed-in user, otherwise a short form of the public key (names are private).
String authorLabel(String? authorPubKey, String? currentPubKey, {String? name}) {
  if (name != null && name.trim().isNotEmpty) return name.trim();
  if (authorPubKey == null || authorPubKey.isEmpty) return tr('author.unknown');
  try {
    final author = CryptoService.normalizePublicKey(authorPubKey);
    if (currentPubKey != null && currentPubKey.isNotEmpty && author == CryptoService.normalizePublicKey(currentPubKey)) {
      return tr('author.you');
    }
    return author.length > 16 ? '${author.substring(0, 8)}...${author.substring(author.length - 6)}' : author;
  } catch (_) {
    return authorPubKey.length > 16 ? '${authorPubKey.substring(0, 8)}...${authorPubKey.substring(authorPubKey.length - 6)}' : authorPubKey;
  }
}
