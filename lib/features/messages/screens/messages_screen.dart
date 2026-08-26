import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:deltanium_app/services/chat_service.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/features/messages/screens/chat_conversation_screen.dart';
import 'package:deltanium_app/features/messages/widgets/conversation_tile.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  String? _currentUserPubKey;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadConversations();
    // Set user online when entering messages
    ChatService.setOnline();
    // Poll every 15 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadConversations());
    // Heartbeat every 30 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ChatService.setOnline();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final auth = await AuthService().getCurrentAuthInfo();
    if (auth != null && mounted) {
      setState(() {
        _currentUserPubKey = auth['publicKey'];
      });
    }
  }

  Future<void> _loadConversations() async {
    try {
      final conversations = await ChatService.getConversations();
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.log('MessagesScreen: Error loading conversations: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openConversation(Map<String, dynamic> conversation) {
    final conversationId = conversation['conversationId'] ?? conversation['ConversationId'] ?? '';
    final otherPubKey = conversation['otherParticipantPubKey'] ?? '';
    final otherName = conversation['otherParticipantName'] ?? '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatConversationScreen(
          conversationId: conversationId,
          otherPubKey: otherPubKey,
          otherName: otherName.isNotEmpty ? otherName : 'User',
        ),
      ),
    ).then((_) => _loadConversations());
  }

  void _startNewConversation() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: isDarkMode
              ? DeltaniumTheme.surfaceDark
              : DeltaniumTheme.white,
          title: Text(
            'New Message',
            style: TextStyle(
              color: isDarkMode
                  ? DeltaniumTheme.darkTextPrimaryColor
                  : DeltaniumTheme.lightTextPrimaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the public key of the person you want to message:',
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode
                      ? DeltaniumTheme.darkTextSecondaryColor
                      : DeltaniumTheme.lightTextSecondaryColor,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                style: TextStyle(
                  color: isDarkMode
                      ? DeltaniumTheme.darkTextPrimaryColor
                      : DeltaniumTheme.lightTextPrimaryColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Paste public key here...',
                  hintStyle: TextStyle(
                    color: isDarkMode
                        ? DeltaniumTheme.darkTextSecondaryColor
                        : DeltaniumTheme.lightTextSecondaryColor,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDarkMode
                          ? DeltaniumTheme.darkDividerColor
                          : DeltaniumTheme.lightDividerColor,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDarkMode
                          ? DeltaniumTheme.primaryTan
                          : DeltaniumTheme.primaryBrown,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDarkMode
                      ? DeltaniumTheme.darkTextSecondaryColor
                      : DeltaniumTheme.lightTextSecondaryColor,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final recipientPubKey = controller.text.trim();
                if (recipientPubKey.isEmpty) return;
                Navigator.pop(ctx);

                final conv = await ChatService.createOrGetConversation(
                  recipientPubKey: recipientPubKey,
                );
                if (conv != null && mounted) {
                  final convId = conv['conversationId'] ?? conv['ConversationId'] ?? '';
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatConversationScreen(
                        conversationId: convId,
                        otherPubKey: recipientPubKey,
                        otherName: 'User',
                      ),
                    ),
                  ).then((_) => _loadConversations());
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isDarkMode
                    ? DeltaniumTheme.primaryTan
                    : DeltaniumTheme.primaryBrown,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Start Chat'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown;
    final bgColor = isDarkMode ? DeltaniumTheme.backgroundDark : DeltaniumTheme.backgroundLight;
    final surfaceColor = isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white;
    final textPrimary = isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor;
    final textSecondary = isDarkMode ? DeltaniumTheme.darkTextSecondaryColor : DeltaniumTheme.lightTextSecondaryColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => context.go(AppRoutes.localUserHome),
        ),
        title: Text(
          'Messages',
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(color: textPrimary),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_square, color: primaryColor),
            onPressed: _startNewConversation,
            tooltip: 'New message',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : _conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: textSecondary),
                      const SizedBox(height: 16),
                      Text(
                        'No messages yet',
                        style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start a conversation by tapping the compose button',
                        style: TextStyle(color: textSecondary, fontSize: 14),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _startNewConversation,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('New Message'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadConversations,
                  color: primaryColor,
                  child: ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final conv = _conversations[index];
                      return ConversationTile(
                        conversation: conv,
                        currentUserPubKey: _currentUserPubKey ?? '',
                        onTap: () => _openConversation(conv),
                      );
                    },
                  ),
                ),
    );
  }
}
