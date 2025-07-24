import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/message_model.dart';
import 'widgets/media_preview.dart'; // For CachedMessageImage

class MediaGalleryScreen extends StatefulWidget {
  final List<MessageModel> mediaMessages;
  final int initialIndex;

  const MediaGalleryScreen({
    super.key,
    required this.mediaMessages,
    required this.initialIndex,
  });

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  late PageController _pageController;
  late int _currentIndex;
  late List<Uint8List?> _imageBytesList;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _imageBytesList = widget.mediaMessages.map((message) {
      if (message.type == MessageType.image) {
        String? base64;
        if (message.content.isNotEmpty) {
          base64 = message.content;
        } else if (message.metadata != null && message.metadata?['base64'] != null) {
          base64 = message.metadata?['base64'];
        }
        if (base64 != null && base64.isNotEmpty) {
          try {
            return base64Decode(base64);
          } catch (_) {}
        }
      }
      return null;
    }).toList();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.mediaMessages.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (context, index) {
                final message = widget.mediaMessages[index];
                if (message.type == MessageType.image) {
                  final imageBytes = _imageBytesList[index];
                  if (imageBytes == null) return const Center(child: Icon(Icons.broken_image, color: Colors.white, size: 64));
                  return PhotoView(
                    imageProvider: MemoryImage(imageBytes),
                    backgroundDecoration: const BoxDecoration(color: Colors.black),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3.0,
                    loadingBuilder: (context, event) => Center(
                      child: CachedMessageImage(
                        base64: widget.mediaMessages[index].content.isNotEmpty
                            ? widget.mediaMessages[index].content
                            : (widget.mediaMessages[index].metadata?['base64'] ?? ''),
                        fit: BoxFit.contain,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  );
                } else if (message.type == MessageType.video) {
                  return _GalleryVideoPlayer(message: message);
                } else {
                  return const Center(child: Icon(Icons.insert_drive_file, color: Colors.white, size: 64));
                }
              },
            ),
            Positioned(
              top: 16,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (widget.mediaMessages.length > 1)
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '${_currentIndex + 1} / ${widget.mediaMessages.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GalleryVideoPlayer extends StatefulWidget {
  final MessageModel message;
  const _GalleryVideoPlayer({required this.message});

  @override
  State<_GalleryVideoPlayer> createState() => _GalleryVideoPlayerState();
}

class _GalleryVideoPlayerState extends State<_GalleryVideoPlayer> {
  ChewieController? _chewieController;
  VideoPlayerController? _videoController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    Uint8List? videoBytes;
    if (widget.message.content.isNotEmpty) {
      videoBytes = base64Decode(widget.message.content);
    } else if (widget.message.metadata != null && widget.message.metadata?['base64'] != null) {
      videoBytes = base64Decode(widget.message.metadata?['base64']);
    }
    if (videoBytes == null) return;
    final tempDir = await getTemporaryDirectory();
    final tempFile = await File('${tempDir.path}/${widget.message.metadata?['name'] ?? 'video.mp4'}').create();
    await tempFile.writeAsBytes(videoBytes, flush: true);
    _videoController = VideoPlayerController.file(tempFile);
    await _videoController!.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoController!,
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      allowMuting: true,
      showControlsOnInitialize: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: Theme.of(context).primaryColor,
        handleColor: Theme.of(context).primaryColor,
        backgroundColor: Colors.grey,
        bufferedColor: Colors.grey[400]!,
      ),
    );
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _chewieController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Chewie(controller: _chewieController!);
  }
} 