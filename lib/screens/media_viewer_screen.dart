import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    // Allow all rotations in media viewer
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Restore portrait-only when leaving
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
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
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main content - PageView (full screen)
          PageView.builder(
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
          // Custom transparent overlay controls
          Positioned(
            top: statusBarHeight,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              color: Colors.black.withOpacity(0.2),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      '${_currentIndex + 1} / ${widget.allMedia.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ),
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
                        : const Icon(Icons.file_download, color: Colors.white),
                    onPressed: _isExporting ? null : _handleExport,
                    tooltip: 'Export to Downloads',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white),
                    onPressed: _handleDelete,
                    tooltip: 'Delete',
                  ),
                ],
              ),
            ),
          ),
        ],
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

  // Diagnostic info
  int _imageWidth = 0;
  int _imageHeight = 0;
  int _fileSize = 0;
  String _orientation = 'unknown';

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
      _fileSize = bytes.length;

      // Save to temporary file for viewing
      final tempDir = await getTemporaryDirectory();
      final extension = widget.mediaItem.type == MediaType.photo ? 'jpg' : 'mp4';
      final tempFile = File('${tempDir.path}/temp_view_${widget.mediaItem.id}.$extension');

      await tempFile.writeAsBytes(bytes);

      // Get image dimensions for diagnostics
      if (widget.mediaItem.type == MediaType.photo) {
        final dims = await _getImageDimensions(bytes);
        _imageWidth = dims['width'] ?? 0;
        _imageHeight = dims['height'] ?? 0;
        _orientation = _imageWidth > _imageHeight ? 'LANDSCAPE' :
                       _imageWidth < _imageHeight ? 'PORTRAIT' : 'SQUARE';
      }

      // Initialize video controller for videos
      if (widget.mediaItem.type == MediaType.video) {
        _videoController = VideoPlayerController.file(tempFile);
        await _videoController!.initialize();
        await _videoController!.setLooping(true);
        _imageWidth = _videoController!.value.size.width.toInt();
        _imageHeight = _videoController!.value.size.height.toInt();
        _orientation = _imageWidth > _imageHeight ? 'LANDSCAPE' : 'PORTRAIT';
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

  Future<Map<String, int>> _getImageDimensions(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return {
        'width': frame.image.width,
        'height': frame.image.height,
      };
    } catch (e) {
      return {'width': 0, 'height': 0};
    }
  }

  Widget _buildDiagnosticOverlay() {
    final screenOrientation = MediaQuery.of(context).orientation;
    return Positioned(
      bottom: 20,
      left: 10,
      right: 10,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'STORED: ${_imageWidth}x$_imageHeight ($_orientation)\n'
          'FILE: ${(_fileSize / 1024).toStringAsFixed(0)} KB\n'
          'SCREEN: $screenOrientation',
          style: const TextStyle(
            color: Colors.greenAccent,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
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

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_decryptedFile == null) {
      return const Center(
        child: Text('Error loading media', style: TextStyle(color: Colors.white)),
      );
    }

    // Photo display
    if (widget.mediaItem.type == MediaType.photo) {
      return SizedBox.expand(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Image.file(
              _decryptedFile!,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    }

    // Video display
    if (_videoController != null && _videoController!.value.isInitialized) {
      return GestureDetector(
        onTap: () {
          setState(() {
            if (_videoController!.value.isPlaying) {
              _videoController!.pause();
            } else {
              _videoController!.play();
            }
          });
        },
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: _getDisplayAspectRatio(),
                child: VideoPlayer(_videoController!),
              ),
              if (!_videoController!.value.isPlaying)
                const Icon(
                  Icons.play_circle_outline,
                  size: 80,
                  color: Colors.white,
                ),
            ],
          ),
        ),
      );
    }

    return const Center(
      child: Text('Error loading video', style: TextStyle(color: Colors.white)),
    );
  }
}
