import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../../models/message_model.dart';

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
    _videoController = VideoPlayerController.network(widget.message.content);
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
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: widget.message.content,
            placeholder: (context, url) => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => const Icon(Icons.error),
            fit: BoxFit.cover,
            width: double.infinity,
            height: 200,
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
                      metadata['name'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${metadata['size']} bytes',
                      style: const TextStyle(fontSize: 12),
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