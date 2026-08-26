import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';

class ConversationTile extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final String currentUserPubKey;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.currentUserPubKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown;
    final textPrimary = isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor;
    final textSecondary = isDarkMode ? DeltaniumTheme.darkTextSecondaryColor : DeltaniumTheme.lightTextSecondaryColor;
    final dividerColor = isDarkMode ? DeltaniumTheme.darkDividerColor : DeltaniumTheme.lightDividerColor;

    final otherName = conversation['otherParticipantName'] ?? '';
    final otherPubKey = conversation['otherParticipantPubKey'] ?? '';
    final unreadCount = conversation['unreadCount'] ?? 0;
    final lastMessageAt = conversation['lastMessageAt'] ?? conversation['LastMessageAt'] ?? '';

    final displayName = otherName.isNotEmpty ? otherName : _truncatePubKey(otherPubKey);
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final timeStr = _formatTime(lastMessageAt);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: dividerColor, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: primaryColor,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name and last message preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: TextStyle(
                            color: unreadCount > 0 ? primaryColor : textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tap to open chat',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _truncatePubKey(String pubKey) {
    if (pubKey.length <= 12) return pubKey;
    return '${pubKey.substring(0, 6)}...${pubKey.substring(pubKey.length - 4)}';
  }

  String _formatTime(String isoTime) {
    if (isoTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTime);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return 'now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}d';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }
}
