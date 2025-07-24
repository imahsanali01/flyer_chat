import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import '../../../utils/audio_util.dart';

class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSendMessage;
  final VoidCallback onAttachmentPressed;
  final VoidCallback onEmojiPressed;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFieldFocus;
  final ValueChanged<String>? onSendAudio;

  const MessageInput({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.onSendMessage,
    required this.onAttachmentPressed,
    required this.onEmojiPressed,
    this.onChanged,
    this.onFieldFocus,
    this.onSendAudio,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final FocusNode _focusNode = FocusNode();
  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();
  bool _isRecorderInitialized = false;
  bool _isRecording = false;
  Timer? _timer;
  int _recordDuration = 0;
  String? _audioPath;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && widget.onFieldFocus != null) {
        widget.onFieldFocus!();
      }
    });
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    await _audioRecorder.openRecorder();
    setState(() {
      _isRecorderInitialized = true;
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _timer?.cancel();
    _audioRecorder.closeRecorder();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) return;
    final filePath = await getTempAudioFilePath();
    await _audioRecorder.startRecorder(
      toFile: filePath,
      codec: Codec.aacADTS,
    );
    setState(() {
      _isRecording = true;
      _recordDuration = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordDuration++;
      });
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _audioRecorder.stopRecorder();
    setState(() {
      _isRecording = false;
      _audioPath = path;
    });
    if (path != null && widget.onSendAudio != null) {
      widget.onSendAudio!(path);
    }
  }

  String _formatDuration(int seconds) {
    return formatDuration(seconds);
  }

  @override
  Widget build(BuildContext context) {
    final isTextEmpty = widget.controller.text.isEmpty;
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
              child: _isRecording
                  ? Row(
                      children: [
                        const Icon(Icons.mic, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(_recordDuration),
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Recording...'),
                      ],
                    )
                  : TextField(
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
            if (_isRecording)
              IconButton(
                icon: const Icon(Icons.stop, color: Colors.red),
                onPressed: _stopRecording,
              )
            else if (isTextEmpty)
              GestureDetector(
                onLongPress: _isRecorderInitialized ? _startRecording : null,
                onLongPressUp: _isRecorderInitialized ? _stopRecording : null,
                child: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.mic, color: Colors.white),
                ),
              )
            else
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