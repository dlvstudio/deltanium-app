import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';

class MessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final String timestamp;
  final bool isDecrypting;
  final bool decryptFailed;
  final bool isP2P;

  const MessageBubble({
    super.key,
    required this.text,
    required this.isMe,
    required this.timestamp,
    this.isDecrypting = false,
    this.decryptFailed = false,
    this.isP2P = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown;
    final textSecondary = isDarkMode ? DeltaniumTheme.darkTextSecondaryColor : DeltaniumTheme.lightTextSecondaryColor;

    final bubbleColor = isMe
        ? primaryColor
        : (isDarkMode
            ? DeltaniumTheme.surfaceDark
            : DeltaniumTheme.surfaceLight);

    final textColor = isMe
        ? Colors.white
        : (isDarkMode
            ? DeltaniumTheme.darkTextPrimaryColor
            : DeltaniumTheme.lightTextPrimaryColor);

    final timeStr = _formatTime(timestamp);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (isDecrypting)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isMe ? Colors.white70 : textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Decrypting...',
                    style: TextStyle(
                      color: isMe ? Colors.white70 : textSecondary,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              )
            else if (decryptFailed)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 14, color: isMe ? Colors.white54 : textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Unable to decrypt',
                    style: TextStyle(
                      color: isMe ? Colors.white54 : textSecondary,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              )
            else
              Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isP2P) ...[
                  Icon(
                    Icons.bolt,
                    size: 11,
                    color: isMe ? Colors.white60 : textSecondary,
                  ),
                  const SizedBox(width: 2),
                ],
                Text(
                  timeStr,
                  style: TextStyle(
                    color: isMe ? Colors.white60 : textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String isoTime) {
    if (isoTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTime);
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }
}
