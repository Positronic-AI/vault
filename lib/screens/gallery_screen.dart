import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../services/storage_service.dart';
import '../models/media_item.dart';
import 'media_viewer_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final StorageService _storageService = StorageService();
  List<MediaItem> _mediaItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    setState(() {
      _isLoading = true;
    });

    await _storageService.initialize();
    final items = await _storageService.getAllMedia();

    setState(() {
      _mediaItems = items;
      _isLoading = false;
    });
  }

  Future<void> _deleteMedia(MediaItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Media'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storageService.deleteMedia(item);
      await _loadMedia();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Media deleted')),
        );
      }
    }
  }

  Future<Uint8List?> _generateVideoThumbnail(MediaItem item) async {
    try {
      // Decrypt the video first
      final bytes = await _storageService.getMediaBytes(item);

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_thumb_${item.id}.mp4');
      await tempFile.writeAsBytes(bytes);

      // Generate thumbnail
      final thumbnail = await VideoThumbnail.thumbnailData(
        video: tempFile.path,
        imageFormat: ImageFormat.PNG,
        maxWidth: 300,
        quality: 75,
      );

      // Clean up temp file
      await tempFile.delete();

      return thumbnail;
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMedia,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _mediaItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 64,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No media yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use the camera to capture photos and videos',
                        style: TextStyle(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: _mediaItems.length,
                  itemBuilder: (context, index) {
                    final item = _mediaItems[index];

                    return GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MediaViewerScreen(
                              allMedia: _mediaItems,
                              initialIndex: index,
                              onDelete: (item) => _deleteMedia(item),
                            ),
                          ),
                        );
                      },
                      onLongPress: () => _deleteMedia(item),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          color: Colors.grey[900],
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Show thumbnail for photos and videos
                              if (item.type == MediaType.photo)
                                FutureBuilder(
                                  future: _storageService.getMediaBytes(item),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData) {
                                      return Image.memory(
                                        snapshot.data!,
                                        fit: BoxFit.cover,
                                      );
                                    }
                                    return Icon(
                                      Icons.photo,
                                      size: 48,
                                      color: Colors.grey[700],
                                    );
                                  },
                                )
                              else
                                FutureBuilder<Uint8List?>(
                                  future: _generateVideoThumbnail(item),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData && snapshot.data != null) {
                                      return Image.memory(
                                        snapshot.data!,
                                        fit: BoxFit.cover,
                                      );
                                    }
                                    return Icon(
                                      Icons.videocam,
                                      size: 48,
                                      color: Colors.grey[700],
                                    );
                                  },
                                ),

                              // Play icon overlay for videos
                              if (item.type == MediaType.video)
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
