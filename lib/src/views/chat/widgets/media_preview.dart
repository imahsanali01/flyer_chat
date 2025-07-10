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

class MediaPreview extends StatefulWidget {
  final MessageModel message;

  const MediaPreview({
    super.key,
    required this.message,
  });

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    if (widget.message.type == MessageType.video) {
      _initializeVideo();
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

  @override
  Widget build(BuildContext context) {
    switch (widget.message.type) {
      case MessageType.image:
        Uint8List? imageBytes;
        if (widget.message.content.isNotEmpty) {
          imageBytes = base64Decode(widget.message.content);
        } else if (widget.message.metadata != null && widget.message.metadata?['base64'] != null) {
          imageBytes = base64Decode(widget.message.metadata?['base64']);
        }
        if (imageBytes == null) return const Icon(Icons.error);
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  body: SafeArea(
                    child: Stack(
                      children: [
                        PhotoView(
                          imageProvider: MemoryImage(imageBytes!),
                          backgroundDecoration: const BoxDecoration(color: Colors.black),
                          minScale: PhotoViewComputedScale.contained,
                          maxScale: PhotoViewComputedScale.covered * 3.0,
                        ),
                        Positioned(
                          top: 16,
                          left: 8,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 32),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              imageBytes,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 200,
            ),
          ),
        );

      case MessageType.video:
        if (_chewieController != null) {
          return SizedBox(
            height: 200,
            child: Chewie(controller: _chewieController!),
          );
        }
        return const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        );

      case MessageType.file:
        final metadata = widget.message.metadata;
        if (metadata == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.attach_file),
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
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      metadata['size'] != null ? '${metadata['size']} bytes' : '',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (metadata['base64'] != null)
                      TextButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text('Download'),
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