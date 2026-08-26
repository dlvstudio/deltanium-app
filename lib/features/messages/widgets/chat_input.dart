import 'package:flutter/material.dart';
import 'package:deltanium_app/config/theme.dart';

class ChatInput extends StatefulWidget {
  final Function(String) onSend;
  final bool isSending;

  const ChatInput({
    super.key,
    required this.onSend,
    this.isSending = false,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isSending) return;
    widget.onSend(text);
    _controller.clear();
    setState(() => _hasText = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDarkMode ? DeltaniumTheme.primaryTan : DeltaniumTheme.primaryBrown;
    final surfaceColor = isDarkMode ? DeltaniumTheme.black : DeltaniumTheme.white;
    final inputBgColor = isDarkMode ? DeltaniumTheme.surfaceDark : DeltaniumTheme.surfaceLight;
    final textColor = isDarkMode ? DeltaniumTheme.darkTextPrimaryColor : DeltaniumTheme.lightTextPrimaryColor;
    final hintColor = isDarkMode ? DeltaniumTheme.darkTextSecondaryColor : DeltaniumTheme.lightTextSecondaryColor;
    final dividerColor = isDarkMode ? DeltaniumTheme.darkDividerColor : DeltaniumTheme.lightDividerColor;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          top: BorderSide(color: dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Text field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: inputBgColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _controller,
                style: TextStyle(color: textColor, fontSize: 15),
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message...',
                  hintStyle: TextStyle(color: hintColor),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  final has = val.trim().isNotEmpty;
                  if (has != _hasText) {
                    setState(() => _hasText = has);
                  }
                },
                onSubmitted: (_) => _handleSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          AnimatedOpacity(
            opacity: _hasText ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 150),
            child: widget.isSending
                ? Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
                    ),
                  )
                : IconButton(
                    onPressed: _hasText ? _handleSend : null,
                    icon: Icon(Icons.send_rounded, color: primaryColor),
                    iconSize: 28,
                  ),
          ),
        ],
      ),
    );
  }
}
