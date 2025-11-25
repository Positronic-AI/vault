import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:file_picker/file_picker.dart';
import '../services/storage_service.dart';
import '../models/media_item.dart';
import '../main.dart';
import 'media_viewer_screen.dart';
import 'note_editor_screen.dart';
import 'file_viewer_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final StorageService _storageService = StorageService();
  List<MediaItem> _mediaItems = [];
  bool _isLoading = true;
  bool _fabExpanded = false;

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
    final typeName = item.type == MediaType.note ? 'note' : 'media';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $typeName'),
        content: Text('Are you sure you want to delete this $typeName?'),
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
          SnackBar(content: Text('${typeName.substring(0, 1).toUpperCase()}${typeName.substring(1)} deleted')),
        );
      }
    }
  }

  Future<void> _openNewNote() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NoteEditorScreen(),
      ),
    );

    if (result == true) {
      _loadMedia();
    }
  }

  Future<void> _openNote(MediaItem item) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(existingNote: item),
      ),
    );

    if (result == true) {
      _loadMedia();
    }
  }

  Future<void> _importFiles() async {
    setState(() {
      _fabExpanded = false;
    });

    // Suppress auto-lock during file picker
    suppressAutoLock = true;

    // Pick files
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    suppressAutoLock = false;

    if (result == null || result.files.isEmpty) return;

    // Ask move or copy
    final moveFiles = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Options'),
        content: const Text('Would you like to move the files (delete originals) or copy them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (moveFiles == null) return;

    // Import each file
    int imported = 0;
    for (final file in result.files) {
      if (file.path != null) {
        try {
          await _storageService.importFile(
            file: File(file.path!),
            originalName: file.name,
            deleteOriginal: moveFiles,
          );
          imported++;
        } catch (e) {
          debugPrint('Error importing ${file.name}: $e');
        }
      }
    }

    await _loadMedia();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$imported file(s) imported securely')),
      );
    }
  }

  Future<void> _openFile(MediaItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileViewerScreen(
          item: item,
          onDelete: () => _deleteMedia(item),
        ),
      ),
    );
    _loadMedia();
  }

  Widget _buildFilePreview(MediaItem item) {
    final name = item.originalName ?? 'Unknown file';
    final ext = name.contains('.') ? name.split('.').last.toUpperCase() : '?';

    // Choose icon based on extension
    IconData icon;
    Color color;
    switch (ext.toLowerCase()) {
      case 'pdf':
        icon = Icons.picture_as_pdf;
        color = Colors.red;
        break;
      case 'doc':
      case 'docx':
        icon = Icons.description;
        color = Colors.blue;
        break;
      case 'xls':
      case 'xlsx':
        icon = Icons.table_chart;
        color = Colors.green;
        break;
      case 'zip':
      case 'rar':
      case '7z':
        icon = Icons.folder_zip;
        color = Colors.orange;
        break;
      case 'mp3':
      case 'wav':
      case 'aac':
        icon = Icons.audio_file;
        color = Colors.purple;
        break;
      default:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
    }

    return Container(
      color: Colors.grey[850],
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 4),
          Text(
            name,
            style: const TextStyle(fontSize: 10, color: Colors.white),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNotePreview(String content) {
    final lines = content.split('\n');
    // First non-empty line is the title
    String title = '';
    List<String> previewLines = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      // Skip empty lines and markdown headers for cleaner display
      final cleanLine = line.replaceAll(RegExp(r'^#+\s*'), ''); // Remove # headers
      if (cleanLine.isEmpty) continue;

      if (title.isEmpty) {
        title = cleanLine;
      } else if (previewLines.length < 3) {
        previewLines.add(cleanLine);
      }
    }

    if (title.isEmpty) {
      title = 'Empty note';
    }

    return Container(
      color: Colors.grey[850],
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.white,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (previewLines.isNotEmpty) ...[
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                previewLines.join('\n'),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[400],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Expandable options
          if (_fabExpanded) ...[
            FloatingActionButton.small(
              heroTag: 'import',
              onPressed: _importFiles,
              tooltip: 'Import Files',
              child: const Icon(Icons.file_upload),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'note',
              onPressed: () {
                setState(() {
                  _fabExpanded = false;
                });
                _openNewNote();
              },
              tooltip: 'New Note',
              child: const Icon(Icons.note_add),
            ),
            const SizedBox(height: 8),
          ],
          // Main FAB
          FloatingActionButton(
            heroTag: 'main',
            onPressed: () {
              setState(() {
                _fabExpanded = !_fabExpanded;
              });
            },
            child: Icon(_fabExpanded ? Icons.close : Icons.add),
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
                        Icons.folder_outlined,
                        size: 64,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your vault is empty',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Capture photos/videos or create notes',
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
                        if (item.type == MediaType.note) {
                          _openNote(item);
                        } else if (item.type == MediaType.file) {
                          _openFile(item);
                        } else {
                          // Filter to only photos and videos for the media viewer
                          final mediaOnly = _mediaItems
                              .where((i) => i.type == MediaType.photo || i.type == MediaType.video)
                              .toList();
                          final mediaIndex = mediaOnly.indexOf(item);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MediaViewerScreen(
                                allMedia: mediaOnly,
                                initialIndex: mediaIndex,
                                onDelete: (item) => _deleteMedia(item),
                              ),
                            ),
                          );
                        }
                      },
                      onLongPress: () => _deleteMedia(item),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          color: Colors.grey[900],
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Show thumbnail based on type
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
                              else if (item.type == MediaType.video)
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
                                )
                              else if (item.type == MediaType.note)
                                FutureBuilder<String>(
                                  future: _storageService.getNoteContent(item),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData) {
                                      return _buildNotePreview(snapshot.data!);
                                    }
                                    return Container(
                                      color: Colors.deepPurple.withOpacity(0.3),
                                      child: Icon(
                                        Icons.note,
                                        size: 48,
                                        color: Colors.grey[400],
                                      ),
                                    );
                                  },
                                )
                              else if (item.type == MediaType.file)
                                _buildFilePreview(item),

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

                              // Note icon overlay
                              if (item.type == MediaType.note)
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
                                      Icons.edit_note,
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
