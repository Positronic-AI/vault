import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media_item.dart';
import '../services/storage_service.dart';

class FileViewerScreen extends StatefulWidget {
  final MediaItem item;
  final VoidCallback onDelete;

  const FileViewerScreen({
    super.key,
    required this.item,
    required this.onDelete,
  });

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  final StorageService _storageService = StorageService();
  bool _isExporting = false;
  bool _isLoading = true;
  String? _error;

  // PDF specific
  String? _pdfPath;
  File? _tempFile;
  int _totalPages = 0;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _storageService.initialize();

    if (_isPdf) {
      await _loadPdf();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool get _isPdf {
    final name = widget.item.originalName?.toLowerCase() ?? '';
    return name.endsWith('.pdf');
  }

  Future<void> _loadPdf() async {
    try {
      // Decrypt to temp file
      final bytes = await _storageService.getMediaBytes(widget.item);
      final tempDir = await getTemporaryDirectory();
      _tempFile = File('${tempDir.path}/temp_${widget.item.id}.pdf');
      await _tempFile!.writeAsBytes(bytes);

      setState(() {
        _pdfPath = _tempFile!.path;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load PDF: $e';
      });
    }
  }

  @override
  void dispose() {
    // Clean up temp file
    _tempFile?.delete().catchError((_) {});
    super.dispose();
  }

  Future<void> _exportFile() async {
    final fileName = widget.item.originalName ?? 'file';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export file?'),
        content: Text('This will decrypt and save "$fileName" to your Downloads folder.'),
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
        item: widget.item,
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

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete file'),
        content: const Text('Are you sure you want to delete this file from the vault?'),
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
      widget.onDelete();
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  IconData _getFileIcon(String? name) {
    if (name == null) return Icons.insert_drive_file;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'mp3':
      case 'wav':
      case 'aac':
        return Icons.audio_file;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String? name) {
    if (name == null) return Colors.grey;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

    switch (ext) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'zip':
      case 'rar':
      case '7z':
        return Colors.orange;
      case 'mp3':
      case 'wav':
      case 'aac':
        return Colors.purple;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.item.originalName ?? 'Unknown file';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isPdf ? fileName : 'File Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _isExporting ? null : _exportFile,
            tooltip: 'Export',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmDelete,
            tooltip: 'Delete',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _isPdf
                  ? _buildPdfViewer()
                  : _buildFileInfo(fileName),
    );
  }

  Widget _buildPdfViewer() {
    if (_pdfPath == null) {
      return const Center(child: Text('Failed to load PDF'));
    }

    return Stack(
      children: [
        PDFView(
          filePath: _pdfPath!,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          pageSnap: true,
          fitPolicy: FitPolicy.BOTH,
          onRender: (pages) {
            setState(() {
              _totalPages = pages ?? 0;
            });
          },
          onPageChanged: (page, total) {
            setState(() {
              _currentPage = page ?? 0;
            });
          },
          onError: (error) {
            setState(() {
              _error = error.toString();
            });
          },
        ),
        // Page indicator
        if (_totalPages > 0)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${_currentPage + 1} / $_totalPages',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFileInfo(String fileName) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // File icon
            Icon(
              _getFileIcon(fileName),
              size: 80,
              color: _getFileColor(fileName),
            ),
            const SizedBox(height: 24),

            // File name
            Text(
              fileName,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Import date
            Text(
              'Imported: ${_formatDate(widget.item.createdAt)}',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 48),

            // Export button
            FilledButton.icon(
              onPressed: _isExporting ? null : _exportFile,
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download),
              label: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(_isExporting ? 'Exporting...' : 'Export to Downloads'),
              ),
            ),
            const SizedBox(height: 16),

            // Info text
            Text(
              'File will be decrypted and saved to your Downloads folder',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
