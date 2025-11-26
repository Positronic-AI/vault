import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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

  /// Status message bar (replaces both loading overlay and snackbars)
  String _statusMessage = '';
  bool _isStatusVisible = false;

  /// Filter state
  String _selectedFilter = 'All';
  static const List<String> _filters = ['All', 'Photos', 'Videos', 'Notes', 'Files'];

  /// Grid column count (pinch to zoom)
  int _gridColumns = 3;
  static const int _minColumns = 2;
  static const int _maxColumns = 6;
  double _baseScale = 1.0;
  int _pointerCount = 0;

  /// Static cache for decrypted thumbnails - survives navigation
  static final Map<String, Uint8List> _thumbnailCache = {};
  static final Map<String, String> _noteCache = {};

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  /// Show a status message (auto-hides after delay unless persistent)
  void _showStatus(String message, {bool persistent = false}) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
        _isStatusVisible = true;
      });
    }
    debugPrint('Gallery: $message');

    if (!persistent && message.isNotEmpty) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _statusMessage == message) {
          setState(() {
            _isStatusVisible = false;
          });
        }
      });
    }
  }

  /// Hide the status bar
  void _hideStatus() {
    if (mounted) {
      setState(() {
        _isStatusVisible = false;
      });
    }
  }

  Future<void> _loadMedia() async {
    setState(() {
      _isLoading = true;
    });

    _showStatus('Loading...', persistent: true);
    await _storageService.initialize();

    final items = await _storageService.getAllMedia();

    // Count what needs loading
    int cached = 0;
    int needsLoading = 0;

    for (final item in items) {
      if (_thumbnailCache.containsKey(item.id) || _noteCache.containsKey(item.id)) {
        cached++;
      } else {
        needsLoading++;
      }
    }

    if (needsLoading > 0) {
      _showStatus('Loading $needsLoading items...', persistent: true);
    }

    // Pre-load all thumbnails in parallel for instant display
    await _preloadThumbnails(items);

    setState(() {
      _mediaItems = items;
      _isLoading = false;
    });
    _hideStatus();
  }

  /// Pre-load thumbnails for all items in parallel
  Future<void> _preloadThumbnails(List<MediaItem> items) async {
    final futures = <Future>[];
    int toLoad = 0;

    for (final item in items) {
      // Skip if already cached
      if (_thumbnailCache.containsKey(item.id)) continue;
      if (item.type == MediaType.note && _noteCache.containsKey(item.id)) continue;

      if (item.type == MediaType.photo || item.type == MediaType.video) {
        toLoad++;
        futures.add(_loadAndCacheThumbnail(item));
      } else if (item.type == MediaType.file && _isImageFile(item.originalName)) {
        toLoad++;
        futures.add(_loadAndCacheThumbnail(item));
      } else if (item.type == MediaType.note) {
        toLoad++;
        futures.add(_loadAndCacheNote(item));
      }
    }

    if (toLoad > 0) {
      _showStatus('Loading $toLoad items...', persistent: true);
    }

    // Wait for all to complete
    await Future.wait(futures);
  }

  int _generatingCount = 0;

  Future<void> _loadAndCacheThumbnail(MediaItem item) async {
    try {
      var thumbnail = await _storageService.getThumbnailBytes(item);
      if (thumbnail == null) {
        _generatingCount++;
        _showStatus('Generating thumbnails ($_generatingCount)...', persistent: true);
        await _storageService.generateThumbnailForItem(item);
        thumbnail = await _storageService.getThumbnailBytes(item);
        _generatingCount--;
      }
      if (thumbnail != null) {
        _thumbnailCache[item.id] = thumbnail;
      }
    } catch (e) {
      debugPrint('Error loading thumbnail for ${item.id}: $e');
    }
  }

  Future<void> _loadAndCacheNote(MediaItem item) async {
    try {
      final content = await _storageService.getNoteContent(item);
      _noteCache[item.id] = content;
    } catch (e) {
      debugPrint('Error loading note ${item.id}: $e');
    }
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
      // Clear from caches
      _thumbnailCache.remove(item.id);
      _noteCache.remove(item.id);

      await _storageService.deleteMedia(item);
      await _loadMedia();

      _showStatus('${typeName.substring(0, 1).toUpperCase()}${typeName.substring(1)} deleted');
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
      // Clear note cache since content may have changed
      _noteCache.remove(item.id);
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
    final total = result.files.length;
    for (final file in result.files) {
      if (file.path != null) {
        try {
          _showStatus('Importing ${imported + 1}/$total...', persistent: true);
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

    _showStatus('$imported file(s) imported securely');
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

  bool _isImageFile(String? name) {
    if (name == null) return false;
    final ext = name.toLowerCase();
    return ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.gif') ||
        ext.endsWith('.webp') ||
        ext.endsWith('.bmp');
  }

  Widget _buildFilePreview(MediaItem item) {
    final name = item.originalName ?? 'Unknown file';
    final ext = name.contains('.') ? name.split('.').last.toUpperCase() : '?';

    // For image files, show actual thumbnail
    if (_isImageFile(name)) {
      return _ImageFileThumbnail(
        item: item,
        storageService: _storageService,
        cache: _thumbnailCache,
      );
    }

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

  /// Get thumbnail bytes for photos/videos with caching
  /// Uses persistent encrypted thumbnails, generates if missing
  Future<Uint8List?> _getThumbnailBytes(MediaItem item) async {
    // Check memory cache first
    if (_thumbnailCache.containsKey(item.id)) {
      return _thumbnailCache[item.id]!;
    }

    // Try to get persistent thumbnail
    var thumbnail = await _storageService.getThumbnailBytes(item);

    // If no thumbnail exists, generate it (migration for existing media)
    if (thumbnail == null) {
      await _storageService.generateThumbnailForItem(item);
      thumbnail = await _storageService.getThumbnailBytes(item);
    }

    // Cache and return
    if (thumbnail != null) {
      _thumbnailCache[item.id] = thumbnail;
    }
    return thumbnail;
  }

  /// Get note content with caching
  Future<String> _getNoteContent(MediaItem item) async {
    if (_noteCache.containsKey(item.id)) {
      return _noteCache[item.id]!;
    }
    final content = await _storageService.getNoteContent(item);
    _noteCache[item.id] = content;
    return content;
  }

  /// Filter items based on selected filter
  List<MediaItem> get _filteredItems {
    if (_selectedFilter == 'All') return _mediaItems;
    return _mediaItems.where((item) {
      switch (_selectedFilter) {
        case 'Photos':
          return item.type == MediaType.photo;
        case 'Videos':
          return item.type == MediaType.video;
        case 'Notes':
          return item.type == MediaType.note;
        case 'Files':
          return item.type == MediaType.file;
        default:
          return true;
      }
    }).toList();
  }

  /// Group items by date
  Map<String, List<MediaItem>> _groupByDate(List<MediaItem> items) {
    final grouped = <String, List<MediaItem>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final item in items) {
      final itemDate = DateTime(
        item.createdAt.year,
        item.createdAt.month,
        item.createdAt.day,
      );

      String label;
      if (itemDate == today) {
        label = 'Today';
      } else if (itemDate == yesterday) {
        label = 'Yesterday';
      } else if (now.difference(itemDate).inDays < 7) {
        // Day name for this week
        const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        label = days[itemDate.weekday - 1];
      } else if (itemDate.year == now.year) {
        // Month and day for this year
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        label = '${months[itemDate.month - 1]} ${itemDate.day}';
      } else {
        // Full date for older items
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        label = '${months[itemDate.month - 1]} ${itemDate.day}, ${itemDate.year}';
      }

      grouped.putIfAbsent(label, () => []).add(item);
    }

    return grouped;
  }

  /// Track pointer count for gesture handling
  void _onPointerDown(PointerDownEvent event) {
    setState(() {
      _pointerCount++;
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    setState(() {
      _pointerCount = (_pointerCount - 1).clamp(0, 10);
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    setState(() {
      _pointerCount = (_pointerCount - 1).clamp(0, 10);
    });
  }

  /// Handle pinch to zoom - start
  void _onScaleStart(ScaleStartDetails details) {
    _baseScale = _gridColumns.toDouble();
  }

  /// Handle pinch to zoom - update
  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Only respond to pinch gestures (2+ pointers)
    // Use our tracked pointer count as it's more reliable
    if (_pointerCount < 2 && details.pointerCount < 2) return;

    final scale = details.scale;

    // Ignore very small scale changes (noise)
    if ((scale - 1.0).abs() < 0.05) return;

    // Calculate target columns based on scale
    // Pinch out (scale > 1) = fewer columns (larger thumbnails)
    // Pinch in (scale < 1) = more columns (smaller thumbnails)
    final targetColumns = (_baseScale / scale).round().clamp(_minColumns, _maxColumns);

    if (targetColumns != _gridColumns) {
      setState(() {
        _gridColumns = targetColumns;
      });
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
      body: Column(
        children: [
          // Filter chips (always visible)
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: _filters.length,
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = filter == _selectedFilter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                    },
                  ),
                );
              },
            ),
          ),
          // Status bar (shows when there's a message)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _isStatusVisible ? 36 : 0,
            child: _isStatusVisible
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Row(
                      children: [
                        if (_isLoading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        if (_isLoading) const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _statusMessage,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // Main content
          Expanded(
            child: _isLoading && _mediaItems.isEmpty
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
                    : Listener(
                        onPointerDown: _onPointerDown,
                        onPointerUp: _onPointerUp,
                        onPointerCancel: _onPointerCancel,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          child: _buildGroupedGallery(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedGallery() {
    final items = _filteredItems;
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No ${_selectedFilter.toLowerCase()} found',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    final grouped = _groupByDate(items);
    final dateLabels = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      // Disable scrolling when 2+ fingers are down (pinch gesture)
      physics: _pointerCount >= 2
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: dateLabels.length,
      itemBuilder: (context, sectionIndex) {
        final label = dateLabels[sectionIndex];
        final sectionItems = grouped[label]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[400],
                ),
              ),
            ),
            // Grid for this date section
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _gridColumns,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: sectionItems.length,
              itemBuilder: (context, index) {
                final item = sectionItems[index];
                return _buildGridItem(item);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildGridItem(MediaItem item) {
    return GestureDetector(
      onTap: () async {
        if (item.type == MediaType.note) {
          _openNote(item);
        } else if (item.type == MediaType.file) {
          _openFile(item);
        } else {
          // Filter to only photos and videos for the media viewer
          final mediaOnly = _filteredItems
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
                _buildThumbnail(item, Icons.photo)
              else if (item.type == MediaType.video)
                _buildThumbnail(item, Icons.videocam)
              else if (item.type == MediaType.note)
                FutureBuilder<String>(
                  future: _getNoteContent(item),
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
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      size: _gridColumns > 4 ? 12 : 16,
                      color: Colors.white,
                    ),
                  ),
                ),

              // Note icon overlay
              if (item.type == MediaType.note)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      Icons.edit_note,
                      size: _gridColumns > 4 ? 12 : 16,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(MediaItem item, IconData fallbackIcon) {
    // Check cache first for instant display
    if (_thumbnailCache.containsKey(item.id)) {
      return Image.memory(
        _thumbnailCache[item.id]!,
        fit: BoxFit.cover,
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _getThumbnailBytes(item),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
          );
        }
        return Icon(
          fallbackIcon,
          size: _gridColumns > 4 ? 32 : 48,
          color: Colors.grey[700],
        );
      },
    );
  }
}

/// Widget to display thumbnail for imported image files
class _ImageFileThumbnail extends StatefulWidget {
  final MediaItem item;
  final StorageService storageService;
  final Map<String, Uint8List> cache;

  const _ImageFileThumbnail({
    required this.item,
    required this.storageService,
    required this.cache,
  });

  @override
  State<_ImageFileThumbnail> createState() => _ImageFileThumbnailState();
}

class _ImageFileThumbnailState extends State<_ImageFileThumbnail> {
  Uint8List? _imageBytes;
  bool _isLoading = true;
  String? _loadedItemId;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(_ImageFileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if the item changed
    if (oldWidget.item.id != widget.item.id) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final itemId = widget.item.id;

    // Check memory cache first
    if (widget.cache.containsKey(itemId)) {
      if (mounted) {
        setState(() {
          _imageBytes = widget.cache[itemId];
          _loadedItemId = itemId;
          _isLoading = false;
        });
      }
      return;
    }

    // Skip if already loading this item
    if (_loadedItemId == itemId && _imageBytes != null) return;

    setState(() {
      _isLoading = true;
    });
    try {
      // Try to get persistent thumbnail first
      var bytes = await widget.storageService.getThumbnailBytes(widget.item);

      // If no thumbnail exists, generate it
      if (bytes == null) {
        await widget.storageService.generateThumbnailForItem(widget.item);
        bytes = await widget.storageService.getThumbnailBytes(widget.item);
      }

      // Store in memory cache
      if (bytes != null) {
        widget.cache[itemId] = bytes;
      }

      if (mounted) {
        setState(() {
          _imageBytes = bytes;
          _loadedItemId = itemId;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadedItemId = itemId;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.grey[850],
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_imageBytes == null) {
      return Container(
        color: Colors.grey[850],
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }

    return Image.memory(
      _imageBytes!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey[850],
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.grey),
        ),
      ),
    );
  }
}
