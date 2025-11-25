import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/media_item.dart';
import '../services/storage_service.dart';

class NoteEditorScreen extends StatefulWidget {
  final MediaItem? existingNote;

  const NoteEditorScreen({super.key, this.existingNote});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final TextEditingController _controller = TextEditingController();
  final StorageService _storageService = StorageService();
  bool _isPreview = false;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _storageService.initialize();
    if (widget.existingNote != null) {
      _loadNote();
    }
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!_hasChanges) {
      setState(() {
        _hasChanges = true;
      });
    }
  }

  Future<void> _loadNote() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final content = await _storageService.getNoteContent(widget.existingNote!);
      _controller.text = content;
      _hasChanges = false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading note: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveNote() async {
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot save empty note')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      if (widget.existingNote != null) {
        await _storageService.updateNote(widget.existingNote!, _controller.text);
      } else {
        await _storageService.saveNote(_controller.text);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note saved securely')),
        );
        Navigator.of(context).pop(true); // Return true to indicate save
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving note: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _exportNote() async {
    // Can only export existing notes
    if (widget.existingNote == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save the note first before exporting')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export note?'),
        content: const Text('This will decrypt and save the note as a markdown file to your Downloads folder.'),
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
        item: widget.existingNote!,
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

  Future<bool> _onWillPop() async {
    if (!_hasChanges || _controller.text.trim().isEmpty) {
      return true;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('What would you like to do with your changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == 'save') {
      await _saveNote();
      return false; // _saveNote handles navigation
    }
    return result == 'discard';
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.existingNote != null ? 'Edit Note' : 'New Note'),
          actions: [
            // Preview toggle
            IconButton(
              icon: Icon(_isPreview ? Icons.edit : Icons.preview),
              onPressed: () {
                setState(() {
                  _isPreview = !_isPreview;
                });
              },
              tooltip: _isPreview ? 'Edit' : 'Preview',
            ),
            // Export button (only for existing notes)
            if (widget.existingNote != null)
              IconButton(
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download),
                onPressed: _isExporting ? null : _exportNote,
                tooltip: 'Export to Downloads',
              ),
            // Save button
            IconButton(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              onPressed: _isSaving ? null : _saveNote,
              tooltip: 'Save',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _isPreview
                ? _buildPreview()
                : _buildEditor(),
      ),
    );
  }

  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          hintText: 'Write your note here...\n\nSupports **markdown** formatting',
          border: InputBorder.none,
        ),
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_controller.text.trim().isEmpty) {
      return const Center(
        child: Text(
          'Nothing to preview',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Markdown(
      data: _controller.text,
      selectable: true,
      padding: const EdgeInsets.all(16.0),
    );
  }
}
