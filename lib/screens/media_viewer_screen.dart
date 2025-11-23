import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../services/storage_service.dart';
import '../models/media_item.dart';

class MediaViewerScreen extends StatefulWidget {
  final List<MediaItem> allMedia;
  final int initialIndex;
  final Function(MediaItem) onDelete;

  const MediaViewerScreen({
    super.key,
    required this.allMedia,
    required this.initialIndex,
    required this.onDelete,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleDelete() async {
    final item = widget.allMedia[_currentIndex];
    widget.onDelete(item);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${_currentIndex + 1} / ${widget.allMedia.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _handleDelete,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.allMedia.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          return MediaPage(
            mediaItem: widget.allMedia[index],
            key: ValueKey(widget.allMedia[index].id),
          );
        },
      ),
    );
  }
}

class MediaPage extends StatefulWidget {
  final MediaItem mediaItem;

  const MediaPage({
    super.key,
    required this.mediaItem,
  });

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> with AutomaticKeepAliveClientMixin {
  final StorageService _storageService = StorageService();
  bool _isLoading = true;
  File? _decryptedFile;
  VideoPlayerController? _videoController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    await _storageService.initialize();

    try {
      final bytes = await _storageService.getMediaBytes(widget.mediaItem);

      // Save to temporary file for viewing
      final tempDir = await getTemporaryDirectory();
      final extension = widget.mediaItem.type == MediaType.photo ? 'jpg' : 'mp4';
      final tempFile = File('${tempDir.path}/temp_view_${widget.mediaItem.id}.$extension');

      await tempFile.writeAsBytes(bytes);

      // Initialize video controller for videos
      if (widget.mediaItem.type == MediaType.video) {
        _videoController = VideoPlayerController.file(tempFile);
        await _videoController!.initialize();
        await _videoController!.setLooping(true);
      }

      if (mounted) {
        setState(() {
          _decryptedFile = tempFile;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading media: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  double _getDisplayAspectRatio() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return 16 / 9; // Default fallback
    }

    final aspectRatio = _videoController!.value.aspectRatio;
    final rotation = _videoController!.value.rotationCorrection;

    // If rotation is 90 or 270 degrees, the video is rotated sideways
    // so we need to invert the aspect ratio
    if (rotation == 90 || rotation == 270) {
      return 1 / aspectRatio;
    }

    return aspectRatio;
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _decryptedFile?.delete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _decryptedFile == null
            ? const Center(child: Text('Error loading media', style: TextStyle(color: Colors.white)))
            : Center(
                child: widget.mediaItem.type == MediaType.photo
                    ? Image.file(_decryptedFile!)
                    : _videoController != null && _videoController!.value.isInitialized
                        ? GestureDetector(
                            onTap: () {
                              setState(() {
                                if (_videoController!.value.isPlaying) {
                                  _videoController!.pause();
                                } else {
                                  _videoController!.play();
                                }
                              });
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Center(
                                  child: AspectRatio(
                                    aspectRatio: _getDisplayAspectRatio(),
                                    child: VideoPlayer(_videoController!),
                                  ),
                                ),
                                if (!_videoController!.value.isPlaying)
                                  const Icon(
                                    Icons.play_circle_outline,
                                    size: 80,
                                    color: Colors.white,
                                  ),
                              ],
                            ),
                          )
                        : const Center(child: Text('Error loading video', style: TextStyle(color: Colors.white))),
              );
  }
}
