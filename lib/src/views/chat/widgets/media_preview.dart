import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../../models/message_model.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_view/photo_view.dart';
import '../media_gallery_screen.dart'; // Corrected import for MediaGalleryScreen
import 'package:video_thumbnail/video_thumbnail.dart';

class MediaPreview extends StatefulWidget {
  final MessageModel message;
  final List<MessageModel>? mediaMessages;
  final int? mediaIndex;

  const MediaPreview({
    super.key,
    required this.message,
    this.mediaMessages,
    this.mediaIndex,
  });

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  Uint8List? _videoThumbnail;
  bool _loadingThumbnail = false;

  @override
  void initState() {
    super.initState();
    if (widget.message.type == MessageType.video) {
      _generateVideoThumbnail();
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    Uint8List? videoBytes;
    if (widget.message.content.isNotEmpty) {
      videoBytes = base64Decode(widget.message.content);
    } else if (widget.message.metadata != null && widget.message.metadata?['base64'] != null) {
      videoBytes = base64Decode(widget.message.metadata?['base64']);
    }
    if (videoBytes == null) return;
    // Write bytes to a temp file
    final tempDir = await getTemporaryDirectory();
    final tempFile = await File('${tempDir.path}/${widget.message.metadata?['name'] ?? 'video.mp4'}').create();
    await tempFile.writeAsBytes(videoBytes, flush: true);
    _videoController = VideoPlayerController.file(tempFile);
    await _videoController!.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoController!,
      autoPlay: false,
      looping: false,
      aspectRatio: _videoController!.value.aspectRatio,
      placeholder: const Center(child: CircularProgressIndicator()),
      materialProgressColors: ChewieProgressColors(
        playedColor: Theme.of(context).primaryColor,
        handleColor: Theme.of(context).primaryColor,
        backgroundColor: Colors.grey,
        bufferedColor: Colors.grey[400]!,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _generateVideoThumbnail() async {
    setState(() => _loadingThumbnail = true);
    Uint8List? videoBytes;
    if (widget.message.content.isNotEmpty) {
      videoBytes = base64Decode(widget.message.content);
    } else if (widget.message.metadata != null && widget.message.metadata?['base64'] != null) {
      videoBytes = base64Decode(widget.message.metadata?['base64']);
    }
    if (videoBytes == null) {
      setState(() => _loadingThumbnail = false);
      return;
    }
    try {
      // Write bytes to a temp file first since thumbnailData expects a file path
      final tempDir = await getTemporaryDirectory();
      final tempFile = await File('${tempDir.path}/temp_thumb.mp4').create();
      await tempFile.writeAsBytes(videoBytes, flush: true);
      
      final thumb = await VideoThumbnail.thumbnailData(
        video: tempFile.path,
        imageFormat: ImageFormat.PNG,
        maxWidth: 400,
        quality: 60,
      );
      if (mounted) setState(() {
        _videoThumbnail = thumb;
        _loadingThumbnail = false;
      });
    } catch (e) {
      setState(() => _loadingThumbnail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.message.type) {
      case MessageType.image:
        String? base64;
        if (widget.message.content.isNotEmpty) {
          base64 = widget.message.content;
        } else if (widget.message.metadata != null && widget.message.metadata?['base64'] != null) {
          base64 = widget.message.metadata?['base64'];
        }
        if (base64 == null || base64.isEmpty) return const Icon(Icons.error);
        return GestureDetector(
          onTap: () {
            final mediaList = widget.mediaMessages ?? [widget.message];
            final index = widget.mediaIndex ?? 0;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MediaGalleryScreen(
                  mediaMessages: mediaList,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: CachedMessageImage(
            base64: base64,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 200,
            borderRadius: BorderRadius.circular(8),
          ),
        );

      case MessageType.video:
        return GestureDetector(
          onTap: () async {
            final mediaList = widget.mediaMessages ?? [widget.message];
            final index = widget.mediaIndex ?? 0;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MediaGalleryScreen(
                  mediaMessages: mediaList,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _loadingThumbnail
                    ? const Center(child: CircularProgressIndicator())
                    : (_videoThumbnail != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              _videoThumbnail!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 200,
                            ),
                          )
                        : const Icon(Icons.videocam, color: Colors.black26, size: 64)),
              ),
              Container(
                height: 200,
                width: double.infinity,
                alignment: Alignment.center,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 48),
                ),
              ),
            ],
          ),
        );

      case MessageType.file:
        final metadata = widget.message.metadata;
        if (metadata == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final bgColor = theme.brightness == Brightness.dark ? theme.colorScheme.surface : theme.colorScheme.background;
        final iconColor = theme.colorScheme.secondary;
        final textColor = theme.brightness == Brightness.dark ? Colors.white : Colors.black87;
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.attach_file, color: iconColor),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      metadata['name'] != null ? metadata['name'] as String : 'File',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                    ),
                    Text(
                      metadata['size'] != null ? '${metadata['size']} bytes' : '',
                      style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.7)),
                    ),
                    if (metadata['base64'] != null)
                      TextButton.icon(
                        icon: Icon(Icons.download, color: iconColor),
                        label: Text('Download', style: TextStyle(color: iconColor)),
                        onPressed: () async {
                          try {
                            final bytes = base64Decode(metadata['base64']);
                            String fileName = metadata['name'] ?? 'file';
                            if (kIsWeb) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('File download not supported on web.')),
                              );
                              return;
                            }
                            Directory? dir;
                            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
                              dir = await getExternalStorageDirectory();
                              if (dir == null) {
                                dir = await getApplicationDocumentsDirectory();
                              }
                            } else {
                              dir = await getDownloadsDirectory();
                              if (dir == null) {
                                dir = await getApplicationDocumentsDirectory();
                              }
                            }
                            final file = File('${dir!.path}/$fileName');
                            await file.writeAsBytes(bytes, flush: true);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('File saved to ${file.path}')),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to save file: $e')),
                            );
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }
} 

class CachedMessageImage extends StatefulWidget {
  final String base64;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  const CachedMessageImage({Key? key, required this.base64, this.width, this.height, this.fit = BoxFit.cover, this.borderRadius = const BorderRadius.all(Radius.circular(8))}) : super(key: key);

  @override
  State<CachedMessageImage> createState() => _CachedMessageImageState();
}

class _CachedMessageImageState extends State<CachedMessageImage> {
  Uint8List? _imageBytes;
  String? _lastBase64;

  @override
  void didUpdateWidget(covariant CachedMessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.base64 != _lastBase64) {
      _decodeImage();
    }
  }

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  void _decodeImage() {
    if (widget.base64.isNotEmpty) {
      _imageBytes = base64Decode(widget.base64);
      _lastBase64 = widget.base64;
    } else {
      _imageBytes = null;
      _lastBase64 = null;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: _imageBytes != null
          ? ClipRRect(
              borderRadius: widget.borderRadius,
              child: Image.memory(
                _imageBytes!,
                fit: widget.fit,
                width: widget.width,
                height: widget.height,
              ),
            )
          : const Icon(Icons.error),
    );
  }
} 