import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../services/storage_service.dart';
import '../models/media_item.dart';

class MediaViewerScreen extends StatefulWidget {
  final List<MediaItem> allMedia;
  final int initialIndex;
  final Future<void> Function(MediaItem) onDelete;

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
  final StorageService _storageService = StorageService();
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _storageService.initialize();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleDelete() async {
    final item = widget.allMedia[_currentIndex];
    await widget.onDelete(item);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _handleExport() async {
    final item = widget.allMedia[_currentIndex];
    final typeLabel = item.type == MediaType.photo ? 'photo' : 'video';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export file?'),
        content: Text('This will decrypt and save the $typeLabel to your Downloads folder.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Export'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isExporting = true;
    });

    try {
      final exportDir = await _storageService.getExportDirectory();
      final exportedFile = await _storageService.exportFile(
        item: item,
        exportPath: exportDir.path,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to ${exportedFile.path}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
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
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.file_download),
            onPressed: _isExporting ? null : _handleExport,
            tooltip: 'Export to Downloads',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _handleDelete,
            tooltip: 'Delete',
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
                    ? InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 4.0,
                        child: Image.file(_decryptedFile!),
                      )
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
