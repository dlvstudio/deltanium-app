import 'dart:async';

import 'package:deltanium_app/app/router.dart';
import 'package:deltanium_app/config/brand.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/features/messages/screens/chat_conversation_screen.dart';
import 'package:deltanium_app/features/messages/widgets/conversation_tile.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

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
                  // The create response has no display name; the conversation list does.
                  final listed = await ChatService.getConversations();
                  if (!mounted) return;
                  final match = listed.firstWhere(
                    (c) => (c['conversationId'] ?? c['ConversationId']) == convId,
                    orElse: () => {'conversationId': convId},
                  );
                  _openConversation({...match, 'otherParticipantPubKey': recipientPubKey});
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
    return Scaffold(
      backgroundColor: Brand.ink,
      appBar: AppBar(
        backgroundColor: Brand.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Brand.text),
          onPressed: () => context.go(AppRoutes.localUserHome),
        ),
        title: Text(
          'Messages',
          style: GoogleFonts.syne(
            color: Brand.text,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_square, color: Brand.sand),
            onPressed: _startNewConversation,
            tooltip: 'New message',
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: DeltaniumTheme.dividerDark),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Brand.sand))
          : _conversations.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Brand.panel,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Brand.line),
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 32,
                            color: Brand.sand,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'No messages yet',
                          style: GoogleFonts.syne(
                            color: Brand.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start an encrypted conversation with someone’s public key.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            color: Brand.muted,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _startNewConversation,
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('New message'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Brand.sand,
                            foregroundColor: Brand.ink,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadConversations,
                  color: Brand.sand,
                  child: ListView.separated(
                    itemCount: _conversations.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      thickness: 1,
                      color: DeltaniumTheme.dividerDark,
                    ),
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
