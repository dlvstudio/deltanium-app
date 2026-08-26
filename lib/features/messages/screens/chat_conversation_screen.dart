import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:deltanium_app/services/chat_service.dart';
import 'package:deltanium_app/services/webrtc_service.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/config/theme.dart';
import 'package:deltanium_app/features/messages/widgets/message_bubble.dart';
import 'package:deltanium_app/features/messages/widgets/chat_input.dart';
import 'package:deltanium_app/widgets/confirm_storage_cost_dialog.dart';

class ChatConversationScreen extends StatefulWidget {
  final String conversationId;
  final String otherPubKey;
  final String otherName;

  const ChatConversationScreen({
    super.key,
    required this.conversationId,
    required this.otherPubKey,
    required this.otherName,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  // File-based messages from API
  final List<Map<String, dynamic>> _apiMessages = [];
  final Map<String, Map<String, dynamic>?> _decryptedMessages = {};

  // P2P messages (local, real-time)
  final List<Map<String, dynamic>> _p2pMessages = [];

  bool _isLoading = true;
  bool _isSending = false;
  bool _isOtherOnline = false;
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  String? _currentUserPubKey;
  String? _currentUserMnemonic;
  final ScrollController _scrollController = ScrollController();

  // P2P WebRTC
  WebRTCService? _webrtcService;
  P2PState _p2pState = P2PState.disconnected;
  bool _p2pAttempted = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _webrtcService?.dispose();
    ChatService.setOffline();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final auth = await AuthService().getCurrentAuthInfo();
    if (auth != null) {
      _currentUserPubKey = auth['publicKey'];
      _currentUserMnemonic = auth['mnemonic'];
    }

    // Set current user online immediately
    await ChatService.setOnline();

    await _loadMessages();
    await _checkOnlineStatus();

    // Try P2P connection if both are online
    if (_isOtherOnline && _currentUserPubKey != null && _currentUserMnemonic != null) {
      _initP2P();
    }

    // Poll for new messages and online status
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadMessages();
      _checkOnlineStatusAndP2P();
    });

    // Send heartbeat every 30 seconds to stay online
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ChatService.setOnline();
    });
  }

  // ========== P2P CONNECTION ==========

  void _initP2P() {
    if (_p2pAttempted || _currentUserPubKey == null || _currentUserMnemonic == null) return;
    _p2pAttempted = true;

    AppLogger.log('ChatConversation: Initializing P2P connection');

    _webrtcService = WebRTCService(
      myPubKey: _currentUserPubKey!,
      myMnemonic: _currentUserMnemonic!,
      remotePubKey: widget.otherPubKey,
    );

    _webrtcService!.onStateChanged = (state) {
      if (mounted) {
        setState(() => _p2pState = state);
        AppLogger.log('ChatConversation: P2P state -> $state');
      }
    };

    _webrtcService!.onMessageReceived = (messageData) {
      if (mounted) {
        _onP2PMessageReceived(messageData);
      }
    };

    // Determine who initiates: the user with the "smaller" pubkey initiates
    // This ensures only one side creates the offer
    final myNormalized = _currentUserPubKey!.toLowerCase();
    final otherNormalized = widget.otherPubKey.toLowerCase();

    if (myNormalized.compareTo(otherNormalized) < 0) {
      AppLogger.log('ChatConversation: I am initiator (my key is smaller)');
      _webrtcService!.connect();
    } else {
      AppLogger.log('ChatConversation: I am listener (my key is larger)');
      _webrtcService!.listen();
    }
  }

  void _onP2PMessageReceived(Map<String, dynamic> messageData) {
    AppLogger.log('ChatConversation: Received P2P message: ${messageData['text']}');
    setState(() {
      _p2pMessages.add({
        ...messageData,
        '_isP2P': true,
        '_receivedAt': DateTime.now().toUtc().toIso8601String(),
      });
    });
    _scrollToBottom();
  }

  Future<void> _checkOnlineStatusAndP2P() async {
    await _checkOnlineStatus();

    // If other user just came online and we haven't tried P2P yet, initiate
    if (_isOtherOnline && !_p2pAttempted) {
      _initP2P();
    }

    // If other user went offline and P2P was connected, it will naturally fail
    // via ICE connection state changes
  }

  // ========== ONLINE STATUS ==========

  Future<void> _checkOnlineStatus() async {
    try {
      final isOnline = await ChatService.isUserOnline(widget.otherPubKey);
      if (mounted) {
        setState(() => _isOtherOnline = isOnline);
      }
    } catch (e) {
      AppLogger.log('ChatConversation: checkOnline error: $e');
    }
  }

  // ========== FILE-BASED MESSAGES ==========

  Future<void> _loadMessages() async {
    try {
      final messages = await ChatService.getMessages(
        conversationId: widget.conversationId,
      );

      if (mounted) {
        setState(() {
          _apiMessages
            ..clear()
            ..addAll(messages.reversed); // API returns desc, we want asc
          _isLoading = false;
        });
      }

      // Decrypt messages that haven't been decrypted yet
      for (final msg in _apiMessages) {
        final msgId = msg['messageId'] ?? msg['MessageId'] ?? '';
        if (!_decryptedMessages.containsKey(msgId)) {
          _decryptMessage(msg);
        }
      }
    } catch (e) {
      AppLogger.log('ChatConversation: loadMessages error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _decryptMessage(Map<String, dynamic> msg) async {
    final msgId = msg['messageId'] ?? msg['MessageId'] ?? '';
    final blockId = msg['blockId'] ?? msg['BlockId'] ?? '';
    final senderFileId = msg['fileId'] ?? msg['FileId'] ?? '';
    final recipientFileId = msg['recipientFileId'] ?? msg['RecipientFileId'] ?? '';
    final senderPubKey = msg['senderPubKey'] ?? msg['SenderPubKey'] ?? '';
    final storeNodeId = msg['storeNodeId'] ?? msg['StoreNodeId'] ?? '';

    final bool isMe = senderPubKey == _currentUserPubKey;
    final fileId = isMe ? senderFileId : (recipientFileId.isNotEmpty ? recipientFileId : senderFileId);

    if (blockId.isEmpty && fileId.isEmpty) return;

    try {
      final decrypted = await ChatService.decryptMessageFromStore(
        blockId: blockId,
        fileId: fileId,
        storeNodeId: storeNodeId,
      );

      if (mounted) {
        setState(() {
          _decryptedMessages[msgId] = decrypted;
        });
      }
    } catch (e) {
      AppLogger.log('ChatConversation: decrypt error for $msgId: $e');
      if (mounted) {
        setState(() {
          _decryptedMessages[msgId] = null;
        });
      }
    }
  }

  // ========== SEND MESSAGE ==========

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      final trimmed = text.trim();
      final isP2PConnected = _p2pState == P2PState.connected && _webrtcService != null;

      if (isP2PConnected) {
        // ========== P2P SEND (instant) ==========
        final clientMsgId = const Uuid().v4();
        final messageData = {
          'text': trimmed,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'senderPubKey': _currentUserPubKey,
          'conversationId': widget.conversationId,
          'clientMessageId': clientMsgId,
        };

        final sent = await _webrtcService!.sendMessage(messageData);

        if (sent) {
          AppLogger.log('ChatConversation: Message sent via P2P (clientMsgId=$clientMsgId)');
          // Add to local P2P messages for instant display
          setState(() {
            _p2pMessages.add({
              ...messageData,
              '_isP2P': true,
              '_sentByMe': true,
            });
          });
          _scrollToBottom();

          // Also send via file-based in background for persistence (with same clientMessageId)
          _sendFileBasedInBackground(trimmed, clientMsgId);
        } else {
          // P2P send failed, fall back to file-based
          AppLogger.log('ChatConversation: P2P send failed, falling back to file-based');
          await _sendFileBased(trimmed);
        }
      } else {
        // ========== FILE-BASED SEND ==========
        await _sendFileBased(trimmed);
      }
    } catch (e) {
      AppLogger.log('ChatConversation: send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<bool> _confirmStorageCost(Map<String, dynamic> storageInfo) async {
    if (!mounted) return false;
    final completer = Completer<bool>();
    ConfirmStorageCostDialog.show(
      context: context,
      totalFee: (storageInfo['totalFee'] as num?)?.toDouble() ?? 0.0,
      durationDays: storageInfo['durationDays'] as int? ?? 0,
      costPerDay: (storageInfo['estimatedCostPerDay'] as num?)?.toDouble() ?? 0.0,
      estimatedSizeBytes: storageInfo['estimatedSize'] as int? ?? 0,
      feeBasis: storageInfo['feeBasis'] as String? ?? 'Storage fee calculated by node',
      onConfirm: () => completer.complete(true),
      onCancel: () => completer.complete(false),
    );
    return completer.future;
  }

  Future<void> _sendFileBased(String text) async {
    final success = await ChatService.sendMessage(
      conversationId: widget.conversationId,
      recipientPubKey: widget.otherPubKey,
      text: text,
      onConfirmFee: _confirmStorageCost,
    );

    if (success) {
      AppLogger.log('ChatConversation: Message sent via file-based');
      await _loadMessages();
      _scrollToBottom();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Send file-based in background (for P2P message persistence)
  void _sendFileBasedInBackground(String text, String clientMessageId) {
    ChatService.sendMessage(
      conversationId: widget.conversationId,
      recipientPubKey: widget.otherPubKey,
      text: text,
      clientMessageId: clientMessageId,
      onConfirmFee: _confirmStorageCost,
    ).then((success) {
      if (success) {
        AppLogger.log('ChatConversation: Background file-based save completed');
      } else {
        AppLogger.log('ChatConversation: Background file-based save failed (P2P message still delivered)');
      }
    }).catchError((e) {
      AppLogger.log('ChatConversation: Background file-based error: $e');
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ========== BUILD COMBINED MESSAGE LIST ==========

  List<_DisplayMessage> _buildDisplayMessages() {
    final List<_DisplayMessage> result = [];

    // 1. Collect clientMessageIds from P2P messages for dedup
    final Set<String> p2pClientIds = {};
    for (final msg in _p2pMessages) {
      final cid = msg['clientMessageId'] ?? '';
      if (cid.isNotEmpty) {
        p2pClientIds.add(cid);
      }
    }

    // 2. Add file-based messages, skipping those already shown via P2P (by clientMessageId)
    for (final msg in _apiMessages) {
      final msgId = msg['messageId'] ?? msg['MessageId'] ?? '';
      final clientMsgId = msg['clientMessageId'] ?? msg['ClientMessageId'] ?? '';
      final senderPubKey = msg['senderPubKey'] ?? msg['SenderPubKey'] ?? '';
      final isMe = senderPubKey == _currentUserPubKey;
      final createdAt = msg['createdAt'] ?? msg['CreatedAt'] ?? '';
      final decrypted = _decryptedMessages[msgId];

      // If this file-based message has a clientMessageId that matches a P2P message, skip it
      if (clientMsgId.isNotEmpty && p2pClientIds.contains(clientMsgId)) {
        continue; // Already shown as P2P message
      }

      final decryptedText = decrypted?['text'] ?? '';
      result.add(_DisplayMessage(
        text: decryptedText,
        isMe: isMe,
        timestamp: createdAt,
        isDecrypting: !_decryptedMessages.containsKey(msgId),
        decryptFailed: _decryptedMessages.containsKey(msgId) && decrypted == null,
        isP2P: false,
      ));
    }

    // 3. Add P2P messages
    for (final msg in _p2pMessages) {
      final senderPubKey = msg['senderPubKey'] ?? '';
      final isMe = senderPubKey == _currentUserPubKey || msg['_sentByMe'] == true;
      final createdAt = msg['createdAt'] ?? msg['_receivedAt'] ?? '';

      result.add(_DisplayMessage(
        text: msg['text'] ?? '',
        isMe: isMe,
        timestamp: createdAt,
        isDecrypting: false,
        decryptFailed: false,
        isP2P: true,
      ));
    }

    // 4. Sort by timestamp
    result.sort((a, b) {
      try {
        final aTime = DateTime.parse(a.timestamp);
        final bTime = DateTime.parse(b.timestamp);
        return aTime.compareTo(bTime);
      } catch (_) {
        return 0;
      }
    });

    return result;
  }

  // ========== BUILD UI ==========

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown;
    final bgColor = isDarkMode ? DeltaniumTheme.backgroundDark : DeltaniumTheme.backgroundLight;
    final surfaceColor = isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white;
    final textPrimary = isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor;
    final textSecondary = isDarkMode ? DeltaniumTheme.darkTextSecondaryColor : DeltaniumTheme.lightTextSecondaryColor;

    final displayMessages = _buildDisplayMessages();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: primaryColor,
              child: Text(
                widget.otherName.isNotEmpty ? widget.otherName[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherName,
                    style: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  _buildStatusRow(textSecondary),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // P2P connection banner
          if (_p2pState == P2PState.connecting)
            _buildP2PBanner('Establishing P2P connection...', Colors.orange, Icons.sync),
          if (_p2pState == P2PState.connected)
            _buildP2PBanner('Connected P2P - Messages are direct & encrypted', Colors.green, Icons.bolt),

          // Messages list
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : displayMessages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.waving_hand_outlined, size: 48, color: primaryColor),
                            const SizedBox(height: 12),
                            Text(
                              'No messages yet',
                              style: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Say hello to start the conversation!',
                              style: TextStyle(color: textSecondary, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: displayMessages.length,
                        itemBuilder: (context, index) {
                          final dm = displayMessages[index];
                          return MessageBubble(
                            text: dm.text,
                            isMe: dm.isMe,
                            timestamp: dm.timestamp,
                            isDecrypting: dm.isDecrypting,
                            decryptFailed: dm.decryptFailed,
                            isP2P: dm.isP2P,
                          );
                        },
                      ),
          ),
          // Input
          ChatInput(
            onSend: _sendMessage,
            isSending: _isSending,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(Color textSecondary) {
    final List<Widget> items = [];

    // Online/offline indicator
    items.add(Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _isOtherOnline ? Colors.green : textSecondary,
      ),
    ));
    items.add(const SizedBox(width: 4));

    String statusText;
    Color statusColor;

    if (_p2pState == P2PState.connected) {
      statusText = 'P2P Connected';
      statusColor = Colors.green;
    } else if (_p2pState == P2PState.connecting) {
      statusText = 'Connecting P2P...';
      statusColor = Colors.orange;
    } else if (_isOtherOnline) {
      statusText = 'Online';
      statusColor = Colors.green;
    } else {
      statusText = 'Offline';
      statusColor = textSecondary;
    }

    items.add(Text(
      statusText,
      style: TextStyle(color: statusColor, fontSize: 12),
    ));

    return Row(children: items);
  }

  Widget _buildP2PBanner(String text, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: color.withOpacity(0.15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Internal model for displaying messages from both API and P2P sources
class _DisplayMessage {
  final String text;
  final bool isMe;
  final String timestamp;
  final bool isDecrypting;
  final bool decryptFailed;
  final bool isP2P;

  _DisplayMessage({
    required this.text,
    required this.isMe,
    required this.timestamp,
    required this.isDecrypting,
    required this.decryptFailed,
    required this.isP2P,
  });
}
