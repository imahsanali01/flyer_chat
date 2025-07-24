import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_bubble/bubble_type.dart';
import 'package:flutter_chat_bubble/clippers/chat_bubble_clipper_5.dart';
import 'package:flutter_chat_bubble/chat_bubble.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:convert'; // Added for base64Decode
import 'dart:typed_data'; // Added for Uint8List
import 'package:just_audio/just_audio.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async'; // Added for Timer
import '../../../models/message_model.dart';
import 'media_preview.dart'; // Contains CachedMessageImage
import '../media_gallery_screen.dart'; // Correct path for MediaGalleryScreen

class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final Function(String?, [bool?]) onReply;
  final Map<String, MessageModel> allMessages;
  final String? otherUserName;
  final MessageModel? previousMessage;
  final List<MessageModel>? mediaMessages;
  final int? mediaIndex;
  // Multi-select
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onSelect;
  final VoidCallback? onStartSelection;
  final void Function(String repliedMessageId)? onTapRepliedMessage;
  final bool highlight;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.onReply,
    required this.allMessages,
    this.otherUserName,
    this.previousMessage,
    this.mediaMessages,
    this.mediaIndex,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onSelect,
    this.onStartSelection,
    this.onTapRepliedMessage,
    this.highlight = false,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> with SingleTickerProviderStateMixin {
  double _swipeOffset = 0;
  bool _showReplyHighlight = false;
  late AnimationController _controller;
  Timer? _seekTimer;
  bool _isSeeking = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _controller.dispose();
    _seekTimer?.cancel();
    super.dispose();
  }

  void _handleSwipeReply() {
    setState(() {
      _showReplyHighlight = true;
      _swipeOffset = 32;
    });
    _controller.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 350), () {
      setState(() {
        _showReplyHighlight = false;
        _swipeOffset = 0;
      });
    });
    widget.onReply(widget.message.id);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMe = widget.isMe;
    final onReply = widget.onReply;
    final allMessages = widget.allMessages;
    String? replyContent;
    String? replySender;
    if (message.replyTo != null && allMessages[message.replyTo!] != null) {
      replyContent = allMessages[message.replyTo!]!.content;
      replySender = allMessages[message.replyTo!]!.senderId == message.senderId
          ? (isMe ? 'You' : 'Sender')
          : (allMessages[message.replyTo!]!.senderId == (isMe ? message.receiverId : message.senderId)
              ? 'Other'
              : '');
    }

    // System message: centered, gray, no bubble, no avatar, no tail, no timeago
    if (message.type == MessageType.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  message.content,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontStyle: FontStyle.italic,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Secret tap counter for recovery
    final ValueNotifier<int> tapCount = ValueNotifier<int>(0);
    final ValueNotifier<bool> showRecovered = ValueNotifier<bool>(false);

    Widget messageContentWidget() {
      if (message.isDeleted) {
        return ValueListenableBuilder<bool>(
          valueListenable: showRecovered,
          builder: (context, recovered, _) {
            if (recovered && message.originalContent != null) {
              return Text(
                message.originalContent!,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black,
                  fontStyle: FontStyle.italic,
                  fontSize: 16,
                ),
              );
            }
            return Text(
              'This message was deleted',
              style: TextStyle(
                color: Colors.grey,
                fontStyle: FontStyle.italic,
                fontSize: 16,
              ),
            );
          },
        );
      }
      // AUDIO BUBBLE
      if (message.type == MessageType.audio && message.content.isNotEmpty) {
        return _AudioBubble(
          audioUrl: message.content,
          isMe: isMe,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.type != MessageType.text)
            MediaPreview(
              message: message,
              mediaMessages: widget.mediaMessages,
              mediaIndex: widget.mediaIndex,
            ),
          if (message.type == MessageType.text && message.content.isNotEmpty)
            Row(
              children: [
                Flexible(
                  child: Text(
                    message.content,
                    style: TextStyle(
                      color: isMe 
                          ? Colors.white 
                          : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
                      fontSize: 16,
                    ),
                  ),
                ),
                if (message.isEdited)
                  Padding(
                    padding: const EdgeInsets.only(left: 4.0),
                    child: Text(
                      '(edited)',
                      style: TextStyle(
                        color: isMe ? Colors.white70 : Colors.black54,
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timeago.format(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: isMe 
                      ? Colors.white70 
                      : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54),
                ),
              ),
              const SizedBox(width: 4),
              if (isMe)
                Icon(
                  message.isRead
                      ? Icons.done_all
                      : Icons.done,
                  size: 12,
                  color: message.isRead
                      ? Colors.blue
                      : Colors.white70,
                ),
            ],
          ),
        ],
      );
    }

    Widget replyPreview() {
      if (message.replyTo != null && replyContent != null) {
        final repliedMessage = allMessages[message.replyTo!];
        Widget contentWidget;
        if (repliedMessage != null && repliedMessage.type == MessageType.image) {
          contentWidget = GestureDetector(
            onTap: () {
              final mediaList = widget.allMessages.values
                  .where((m) => m.type == MessageType.image || m.type == MessageType.video)
                  .toList();
              final index = mediaList.indexWhere((m) => m.id == repliedMessage.id);
              if (index != -1) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MediaGalleryScreen(
                      mediaMessages: mediaList,
                      initialIndex: index,
                    ),
                  ),
                );
              }
            },
            child: CachedMessageImage(
              base64: repliedMessage.content.isNotEmpty
                  ? repliedMessage.content
                  : (repliedMessage.metadata?['base64'] ?? ''),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(6),
            ),
          );
        } else if (repliedMessage != null && repliedMessage.type == MessageType.video) {
          contentWidget = Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(
              child: Icon(Icons.play_circle_fill, color: Colors.white, size: 32),
            ),
          );
        } else if (repliedMessage != null && repliedMessage.type == MessageType.audio) {
          contentWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.audiotrack, size: 24, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.white,),
              const SizedBox(width: 6),
              Text(
                'Audio message',
                style: TextStyle(
                  fontSize: 13,
                  color: isMe
                      ? Colors.white70
                      : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                ),
              ),
            ],
          );
        } else if (repliedMessage != null && repliedMessage.type == MessageType.file) {
          final fileName = repliedMessage.metadata?['name'] ?? 'File';
          contentWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file, size: 24),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isMe
                        ? Colors.white70
                        : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                  ),
                ),
              ),
            ],
          );
        } else {
          contentWidget = Text(
            replyContent!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13, 
              color: isMe 
                  ? Colors.white70 
                  : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
            ),
          );
        }
        return GestureDetector(
          onTap: () {
            if (widget.onTapRepliedMessage != null) {
              widget.onTapRepliedMessage!(message.replyTo!);
            }
          },
          child: Container(
          // No margin, so it's inside the bubble
          padding: const EdgeInsets.only(top: 4, bottom: 4, left: 12, right: 0),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
            ),
            border: Border(
              left: BorderSide(
                color: isMe ? Colors.blue : Colors.green,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                allMessages[message.replyTo!]!.senderId == message.senderId
                    ? (isMe ? 'You' : 'Sender')
                    : (allMessages[message.replyTo!]!.senderId == (isMe ? message.receiverId : message.senderId)
                        ? (widget.otherUserName ?? 'Other')
                        : 'Other'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isMe ? Colors.blue : Colors.green,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              contentWidget,
              const SizedBox(height: 4),
              Container(
                height: 1,
                color: (isMe ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black12)).withOpacity(0.15),
                margin: const EdgeInsets.only(top: 2, bottom: 2),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

    return Padding(
      padding: EdgeInsets.only(
        bottom: 1.0,
        // Add extra top padding if previous message was from different sender or time gap > 2 minutes
        top: (widget.previousMessage != null && (
          widget.previousMessage!.senderId != message.senderId ||
          message.timestamp.difference(widget.previousMessage!.timestamp).inMinutes > 2
        )) ? 8.0 : 1.0,
        left: widget.isMe ? 48.0 : 8.0,
        right: widget.isMe ? 8.0 : 48.0,
      ),
      child: Container(
        decoration: widget.isSelected
            ? BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF223344).withOpacity(0.7)
                    : const Color(0xFFD2E3FC),
                borderRadius: BorderRadius.circular(18),
              )
            : widget.highlight
                ? BoxDecoration(
                    color: Colors.yellow.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.amber, width: 2),
                  )
                : null,
        child: Column(
          crossAxisAlignment:
              widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment:
                  widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Avatar removed for one-to-one chat
                //     if (!isMe) ...[
                //   const CircleAvatar(
                //     radius: 16,
                //     child: Icon(Icons.person),
                //   ),
                //   const SizedBox(width: 8),
                // ],
                Flexible(
                  child: GestureDetector(
                    onLongPress: () {
                      if (widget.isSelectionMode) {
                        widget.onSelect?.call();
                      } else {
                        widget.onStartSelection?.call();
                      }
                    },
                    onTap: () {
                      if (widget.isSelectionMode) {
                        widget.onSelect?.call();
                      } else {
                        if (widget.message.isDeleted && widget.isMe) {
                          tapCount.value++;
                          if (tapCount.value >= 15) {
                            showRecovered.value = true;
                          }
                        }
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      // WhatsApp-style swipe to reply
                      if (!widget.isSelectionMode && details.primaryVelocity != null &&
                          details.primaryVelocity!.abs() > 250) {
                        _handleSwipeReply();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      transform: Matrix4.translationValues(_showReplyHighlight ? _swipeOffset : 0, 0, 0),
                      curve: Curves.easeOut,
                      decoration: null, // Remove highlight from inner container
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final maxWidth = constraints.maxWidth * 0.65;
                          return ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: maxWidth,
                            ),
                            child: Container(
                              padding: const EdgeInsets.only(
                                left: 12.0,
                                right: 12.0,
                                top: 10.0,
                                bottom: 10.0,
                              ),
                              decoration: BoxDecoration(
                                color: widget.isMe 
                                    ? (Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.green[600] 
                                        : Theme.of(context).primaryColor)
                                    : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[200]),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(18),
                                  topRight: const Radius.circular(18),
                                  bottomLeft: Radius.circular(widget.isMe ? 18 : 0),
                                  bottomRight: Radius.circular(widget.isMe ? 0 : 18),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              constraints: const BoxConstraints(
                                minHeight: 40,
                                minWidth: 40,
                              ),
                              child: Stack(
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (message.isForwarded == true)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 2.0),
                                          child: Text(
                                            'Forwarded',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                      if (message.replyTo != null && replyContent != null) replyPreview(),
                                      if (message.replyTo != null && replyContent != null) const SizedBox(height: 8),
                                      messageContentWidget(),
                                      const SizedBox(height: 6),
                                    ],
                                  ),
                                  // Bubble tail
                                  Positioned(
                                    bottom: 0,
                                    left: widget.isMe ? null : 0,
                                    right: widget.isMe ? 0 : null,
                                    child: CustomPaint(
                                      painter: _BubbleTailPainter(
                                        color: widget.isMe 
                                            ? (Theme.of(context).brightness == Brightness.dark 
                                                ? Colors.green[600]! 
                                                : Theme.of(context).primaryColor)
                                            : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[800]! : Colors.grey[200]!),
                                        isMe: widget.isMe,
                                      ),
                                      size: const Size(16, 10),
                                    ),
                                  ),
                                  if (_showReplyHighlight)
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 4,
                                        decoration: BoxDecoration(
                                          color: widget.isMe ? Colors.blue : Colors.green,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (isMe) ...[
                  // Avatar removed for one-to-one chat
                  /**
                   *   const SizedBox(width: 8),
                  const CircleAvatar(
                    radius: 16,
                    child: Icon(Icons.person),
                  ),
                   */
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isMe;
  _BubbleTailPainter({required this.color, required this.isMe});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (isMe) {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width - 10, size.height);
      path.close();
    } else {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(10, size.height);
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 

class AudioBubbleManager {
  static final ValueNotifier<String?> currentlyPlayingId = ValueNotifier<String?>(null);
}

class _AudioBubble extends StatefulWidget {
  final String audioUrl; // This may be a base64 string
  final bool isMe;
  final VoidCallback? onDelete;
  const _AudioBubble({required this.audioUrl, required this.isMe, this.onDelete});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> with SingleTickerProviderStateMixin {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  late final PlayerController _waveController;
  bool _waveformLoaded = false;
  double _playbackSpeed = 1.0;
  String? _localPath;
  Timer? _seekTimer;
  bool _isSeeking = false;
  late final String _bubbleId;
  late final VoidCallback _pauseListener;

  @override
  void initState() {
    super.initState();
    _bubbleId = UniqueKey().toString();
    _player = AudioPlayer();
    _waveController = PlayerController();
    _initAudio();
    _pauseListener = () {
      if (AudioBubbleManager.currentlyPlayingId.value != _bubbleId && _isPlaying) {
        _player.pause();
      }
    };
    AudioBubbleManager.currentlyPlayingId.addListener(_pauseListener);
  }

  Future<void> _initAudio() async {
    try {
      String sourcePath;
      if (_isBase64(widget.audioUrl)) {
        final bytes = base64Decode(widget.audioUrl);
        final tempDir = await getTemporaryDirectory();
        final tempFile = await File('${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a').create();
        await tempFile.writeAsBytes(bytes, flush: true);
        sourcePath = tempFile.path;
        _localPath = sourcePath;
      } else {
        sourcePath = widget.audioUrl;
      }
      await _player.setFilePath(sourcePath);
      _duration = _player.duration ?? Duration.zero;
      setState(() {});
      _player.positionStream.listen((pos) {
        setState(() => _position = pos);
      });
      _player.playerStateStream.listen((state) {
        setState(() => _isPlaying = state.playing);
        if (state.processingState == ProcessingState.completed) {
          _player.seek(Duration.zero);
          setState(() => _isPlaying = false);
        }
      });
      await _waveController.preparePlayer(path: sourcePath);
      setState(() => _waveformLoaded = true);
    } catch (_) {}
  }

  bool _isBase64(String str) {
    // Simple check: base64 strings are long and contain only base64 chars
    return str.length > 100 && !str.startsWith('http');
  }

  Future<String> _getLocalFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = widget.audioUrl.split('/').last.split('?').first;
    return '${dir.path}/$fileName';
  }

  void _seekRelative(int seconds) {
    final newPos = _position + Duration(seconds: seconds);
    _player.seek(newPos < Duration.zero ? Duration.zero : (newPos > _duration ? _duration : newPos));
  }

  void _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      AudioBubbleManager.currentlyPlayingId.value = _bubbleId;
      await _player.setSpeed(_playbackSpeed);
      await _player.play();
    }
  }

  void _toggleSpeed() async {
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else {
        _playbackSpeed = 1.0;
      }
    });
    await _player.setSpeed(_playbackSpeed);
  }

  void _handleDelete() {
    if (widget.onDelete != null) {
      widget.onDelete!();
    }
  }

  void _startSeek(bool forward) {
    _isSeeking = true;
    _seekTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!_isSeeking) return;
      _seekRelative(forward ? 1 : -1);
    });
  }
  void _stopSeek() {
    _isSeeking = false;
    _seekTimer?.cancel();
  }

  @override
  void dispose() {
    _player.dispose();
    _waveController.dispose();
    _seekTimer?.cancel();
    AudioBubbleManager.currentlyPlayingId.removeListener(_pauseListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bubbleBg = widget.isMe
        ? (isDark ? theme.colorScheme.primary.withOpacity(0.85) : theme.primaryColor)
        : (isDark ? theme.cardColor : Colors.grey[200]);
    // Always use high-contrast icon/text colors
    final iconColor = isDark || (bubbleBg != null && bubbleBg.computeLuminance() < 0.5) ? Colors.white : Colors.black;
    final textColor = isDark || (bubbleBg != null && bubbleBg.computeLuminance() < 0.5) ? Colors.white : Colors.black;
    final progressColor = widget.isMe
        ? (isDark ? Colors.white : theme.primaryColor)
        : (isDark ? theme.primaryColor : Colors.blue);
    final inactiveProgressColor = isDark ? Colors.grey[700] : Colors.grey[400];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _togglePlay,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: bubbleBg,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: iconColor,
                  size: 24,
                  shadows: [
                    Shadow(
                      blurRadius: 2,
                      color: Colors.black.withOpacity(0.5),
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (_) => _startSeek(false),
              onLongPressEnd: (_) => _stopSeek(),
              onLongPressUp: _stopSeek,
              child: Container(
                width: 32,
                height: 40,
                alignment: Alignment.center,
                child: Icon(Icons.arrow_left, size: 20, color: inactiveProgressColor),
              ),
            ),
            Expanded(
              child: _waveformLoaded
                  ? AudioFileWaveforms(
                      size: Size(80, 32),
                      playerController: _waveController,
                      enableSeekGesture: true,
                      waveformType: WaveformType.fitWidth,
                      waveformData: const [],
                      playerWaveStyle: PlayerWaveStyle(
                        fixedWaveColor: widget.isMe ? Colors.white : (isDark ? Colors.blue[200]! : Colors.blue[200]!),
                        liveWaveColor: progressColor,
                        spacing: 3,
                        waveThickness: 2,
                      ),
                    )
                  : Container(
                      width: 80,
                      height: 32,
                      alignment: Alignment.centerLeft,
                      child: LinearProgressIndicator(minHeight: 2, color: progressColor, backgroundColor: inactiveProgressColor),
                    ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (_) => _startSeek(true),
              onLongPressEnd: (_) => _stopSeek(),
              onLongPressUp: _stopSeek,
              child: Container(
                width: 32,
                height: 40,
                alignment: Alignment.center,
                child: Icon(Icons.arrow_right, size: 20, color: inactiveProgressColor),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _toggleSpeed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_playbackSpeed}x',
                  style: TextStyle(
                    color: iconColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    shadows: [
                      Shadow(
                        blurRadius: 2,
                        color: Colors.black.withOpacity(0.5),
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // Removed the progress bar and time row below the audio message
      ],
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
} 