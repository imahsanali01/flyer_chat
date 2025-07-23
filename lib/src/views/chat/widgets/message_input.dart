import 'package:flutter/material.dart';

class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSendMessage;
  final VoidCallback onAttachmentPressed;
  final VoidCallback onEmojiPressed;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFieldFocus;

  const MessageInput({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.onSendMessage,
    required this.onAttachmentPressed,
    required this.onEmojiPressed,
    this.onChanged,
    this.onFieldFocus,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && widget.onFieldFocus != null) {
        widget.onFieldFocus!();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8.0,
        vertical: 4.0,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -2),
            blurRadius: 4,
            color: Colors.black.withOpacity(0.1),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined),
              onPressed: widget.onEmojiPressed,
            ),
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: widget.onAttachmentPressed,
            ),
            Expanded(
              child: TextField(
                focusNode: _focusNode,
                controller: widget.controller,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => widget.onSendMessage(),
                onChanged: widget.onChanged,
              ),
            ),
            IconButton(
              icon: widget.isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              onPressed: widget.isLoading ? null : widget.onSendMessage,
            ),
          ],
        ),
      ),
    );
  }
} 