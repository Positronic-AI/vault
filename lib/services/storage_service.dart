import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as img;
import 'package:video_thumbnail/video_thumbnail.dart';
import '../models/media_item.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();
  static const _encryptionKeyKey = 'vault_encryption_key';

  Database? _database;
  encrypt_lib.Key? _encryptionKey;
  encrypt_lib.IV? _iv;

  // Initialize the service
  Future<void> initialize() async {
    await _initEncryption();
    await _initDatabase();
  }

  // Initialize encryption key
  Future<void> _initEncryption() async {
    // Try to get existing key
    String? keyString = await _storage.read(key: _encryptionKeyKey);

    if (keyString == null) {
      // Generate new key
      _encryptionKey = encrypt_lib.Key.fromSecureRandom(32);
      await _storage.write(
        key: _encryptionKeyKey,
        value: _encryptionKey!.base64,
      );
    } else {
      _encryptionKey = encrypt_lib.Key.fromBase64(keyString);
    }

    // Use a fixed IV for all files (simpler for MVP)
    // In production, consider using a random IV per file and storing it with the encrypted data
    _iv = encrypt_lib.IV.fromUtf8('vault1234567890');
  }

  // Initialize database
  Future<void> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'vault.db');

    _database = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE media (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            filename TEXT NOT NULL,
            thumbnail_path TEXT,
            original_name TEXT,
            created_at INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE media ADD COLUMN original_name TEXT');
        }
      },
    );
  }

  // Get vault directory
  Future<Directory> _getVaultDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory('${appDir.path}/vault_media');

    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }

    return vaultDir;
  }

  // Save media file (encrypted)
  Future<MediaItem> saveMedia({
    required File file,
    required MediaType type,
  }) async {
    final vaultDir = await _getVaultDirectory();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final extension = type == MediaType.photo ? 'jpg.enc' : 'mp4.enc';
    final filename = '$id.$extension';
    final encryptedPath = '${vaultDir.path}/$filename';

    // Read file
    final bytes = await file.readAsBytes();

    // Encrypt
    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(_encryptionKey!),
    );
    final encrypted = encrypter.encryptBytes(bytes, iv: _iv!);

    // Save encrypted file
    await File(encryptedPath).writeAsBytes(encrypted.bytes);

    // Generate and save thumbnail
    Uint8List? thumbnailBytes;
    if (type == MediaType.photo) {
      thumbnailBytes = await _generateImageThumbnail(bytes);
    } else if (type == MediaType.video) {
      thumbnailBytes = await _generateVideoThumbnail(file);
    }

    if (thumbnailBytes != null) {
      await _saveThumbnail(id, thumbnailBytes);
    }

    // Save to database
    final mediaItem = MediaItem(
      id: id,
      type: type,
      filename: filename,
      createdAt: DateTime.now(),
    );

    await _database!.insert('media', mediaItem.toMap());

    return mediaItem;
  }

  // Get all media items
  Future<List<MediaItem>> getAllMedia() async {
    final maps = await _database!.query(
      'media',
      orderBy: 'created_at DESC',
    );

    return maps.map((map) => MediaItem.fromMap(map)).toList();
  }

  // Get decrypted media bytes
  Future<Uint8List> getMediaBytes(MediaItem item) async {
    final vaultDir = await _getVaultDirectory();
    final filePath = '${vaultDir.path}/${item.filename}';
    final encryptedBytes = await File(filePath).readAsBytes();

    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(_encryptionKey!),
    );

    final encrypted = encrypt_lib.Encrypted(encryptedBytes);
    final decrypted = encrypter.decryptBytes(encrypted, iv: _iv!);

    return Uint8List.fromList(decrypted);
  }

  // Thumbnail size constant
  static const int _thumbnailSize = 300;

  // Get thumbnail filename from item id
  String _getThumbnailFilename(String id) => '${id}_thumb.jpg.enc';

  // Generate thumbnail from image bytes (runs in isolate for performance)
  Future<Uint8List?> _generateImageThumbnail(Uint8List imageBytes) async {
    try {
      return await compute(_resizeImage, imageBytes);
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
      return null;
    }
  }

  // Static function for compute isolate
  static Uint8List? _resizeImage(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      // Resize to thumbnail size (maintaining aspect ratio)
      final thumbnail = img.copyResize(
        image,
        width: image.width > image.height ? _thumbnailSize : null,
        height: image.height >= image.width ? _thumbnailSize : null,
        interpolation: img.Interpolation.linear,
      );

      // Encode as JPEG with quality 85
      return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 85));
    } catch (e) {
      return null;
    }
  }

  // Generate video thumbnail
  Future<Uint8List?> _generateVideoThumbnail(File videoFile) async {
    try {
      final thumbnail = await VideoThumbnail.thumbnailData(
        video: videoFile.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: _thumbnailSize,
        quality: 85,
      );
      return thumbnail;
    } catch (e) {
      debugPrint('Error generating video thumbnail: $e');
      return null;
    }
  }

  // Save encrypted thumbnail
  Future<String?> _saveThumbnail(String id, Uint8List thumbnailBytes) async {
    try {
      final vaultDir = await _getVaultDirectory();
      final thumbnailFilename = _getThumbnailFilename(id);
      final thumbnailPath = '${vaultDir.path}/$thumbnailFilename';

      // Encrypt thumbnail
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(_encryptionKey!),
      );
      final encrypted = encrypter.encryptBytes(thumbnailBytes, iv: _iv!);

      // Save encrypted thumbnail
      await File(thumbnailPath).writeAsBytes(encrypted.bytes);

      return thumbnailFilename;
    } catch (e) {
      debugPrint('Error saving thumbnail: $e');
      return null;
    }
  }

  // Get decrypted thumbnail bytes (returns null if no thumbnail exists)
  Future<Uint8List?> getThumbnailBytes(MediaItem item) async {
    final vaultDir = await _getVaultDirectory();
    final thumbnailFilename = _getThumbnailFilename(item.id);
    final thumbnailPath = '${vaultDir.path}/$thumbnailFilename';

    final file = File(thumbnailPath);
    if (!await file.exists()) {
      return null;
    }

    try {
      final encryptedBytes = await file.readAsBytes();
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(_encryptionKey!),
      );
      final encrypted = encrypt_lib.Encrypted(encryptedBytes);
      final decrypted = encrypter.decryptBytes(encrypted, iv: _iv!);
      return Uint8List.fromList(decrypted);
    } catch (e) {
      debugPrint('Error reading thumbnail: $e');
      return null;
    }
  }

  // Check if thumbnail exists for a media item
  Future<bool> hasThumbnail(MediaItem item) async {
    final vaultDir = await _getVaultDirectory();
    final thumbnailPath = '${vaultDir.path}/${_getThumbnailFilename(item.id)}';
    return await File(thumbnailPath).exists();
  }

  // Generate and save thumbnail for existing media item
  Future<bool> generateThumbnailForItem(MediaItem item) async {
    try {
      // Check if thumbnail already exists
      if (await hasThumbnail(item)) {
        return true;
      }

      Uint8List? thumbnailBytes;

      if (item.type == MediaType.photo) {
        // For photos, decrypt and generate thumbnail
        final bytes = await getMediaBytes(item);
        thumbnailBytes = await _generateImageThumbnail(bytes);
      } else if (item.type == MediaType.video) {
        // For videos, need to decrypt to temp file first
        final bytes = await getMediaBytes(item);
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/temp_${item.id}.mp4');
        await tempFile.writeAsBytes(bytes);
        thumbnailBytes = await _generateVideoThumbnail(tempFile);
        await tempFile.delete();
      } else if (item.type == MediaType.file && item.originalName != null) {
        // For imported image files
        final ext = item.originalName!.split('.').last.toLowerCase();
        if (_isImageExtension(ext)) {
          final bytes = await getMediaBytes(item);
          thumbnailBytes = await _generateImageThumbnail(bytes);
        }
      }

      if (thumbnailBytes != null) {
        await _saveThumbnail(item.id, thumbnailBytes);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error generating thumbnail for ${item.id}: $e');
      return false;
    }
  }

  // Delete media item
  Future<void> deleteMedia(MediaItem item) async {
    final vaultDir = await _getVaultDirectory();

    // Delete main file
    final filePath = '${vaultDir.path}/${item.filename}';
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }

    // Delete thumbnail if exists
    final thumbnailPath = '${vaultDir.path}/${_getThumbnailFilename(item.id)}';
    final thumbnailFile = File(thumbnailPath);
    if (await thumbnailFile.exists()) {
      await thumbnailFile.delete();
    }

    // Delete from database
    await _database!.delete(
      'media',
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  // Get media count
  Future<int> getMediaCount() async {
    final result = await _database!.rawQuery('SELECT COUNT(*) FROM media');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Save note (encrypted)
  Future<MediaItem> saveNote(String content) async {
    final vaultDir = await _getVaultDirectory();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final filename = '$id.md.enc';
    final encryptedPath = '${vaultDir.path}/$filename';

    // Convert text to bytes
    final bytes = utf8.encode(content);

    // Encrypt
    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(_encryptionKey!),
    );
    final encrypted = encrypter.encryptBytes(bytes, iv: _iv!);

    // Save encrypted file
    await File(encryptedPath).writeAsBytes(encrypted.bytes);

    // Save to database
    final mediaItem = MediaItem(
      id: id,
      type: MediaType.note,
      filename: filename,
      createdAt: DateTime.now(),
    );

    await _database!.insert('media', mediaItem.toMap());

    return mediaItem;
  }

  // Get decrypted note content
  Future<String> getNoteContent(MediaItem item) async {
    final bytes = await getMediaBytes(item);
    return utf8.decode(bytes);
  }

  // Update existing note
  Future<void> updateNote(MediaItem item, String content) async {
    final vaultDir = await _getVaultDirectory();
    final encryptedPath = '${vaultDir.path}/${item.filename}';

    // Convert text to bytes
    final bytes = utf8.encode(content);

    // Encrypt
    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(_encryptionKey!),
    );
    final encrypted = encrypter.encryptBytes(bytes, iv: _iv!);

    // Overwrite encrypted file
    await File(encryptedPath).writeAsBytes(encrypted.bytes);
  }

  // Check if extension is an image type
  bool _isImageExtension(String ext) {
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext.toLowerCase());
  }

  // Check if extension is a video type
  bool _isVideoExtension(String ext) {
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext.toLowerCase());
  }

  // Import file (encrypted)
  Future<MediaItem> importFile({
    required File file,
    required String originalName,
    bool deleteOriginal = false,
  }) async {
    final vaultDir = await _getVaultDirectory();
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    // Get file extension from original name
    final ext = originalName.contains('.')
        ? originalName.split('.').last.toLowerCase()
        : 'bin';
    final filename = '$id.$ext.enc';
    final encryptedPath = '${vaultDir.path}/$filename';

    // Read file
    final bytes = await file.readAsBytes();

    // Encrypt
    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(_encryptionKey!),
    );
    final encrypted = encrypter.encryptBytes(bytes, iv: _iv!);

    // Save encrypted file
    await File(encryptedPath).writeAsBytes(encrypted.bytes);

    // Generate thumbnail for image files
    if (_isImageExtension(ext)) {
      final thumbnailBytes = await _generateImageThumbnail(bytes);
      if (thumbnailBytes != null) {
        await _saveThumbnail(id, thumbnailBytes);
      }
    } else if (_isVideoExtension(ext)) {
      // For videos, generate thumbnail from the original file before deleting
      final thumbnailBytes = await _generateVideoThumbnail(file);
      if (thumbnailBytes != null) {
        await _saveThumbnail(id, thumbnailBytes);
      }
    }

    // Delete original if requested (move mode)
    if (deleteOriginal) {
      try {
        await file.delete();
      } catch (e) {
        // Ignore deletion errors (might be permission issues)
      }
    }

    // Determine media type - images should be photos, videos should be videos
    MediaType mediaType = MediaType.file;
    if (_isImageExtension(ext)) {
      mediaType = MediaType.photo;
    } else if (_isVideoExtension(ext)) {
      mediaType = MediaType.video;
    }

    // Save to database
    final mediaItem = MediaItem(
      id: id,
      type: mediaType,
      filename: filename,
      originalName: originalName,
      createdAt: DateTime.now(),
    );

    await _database!.insert('media', mediaItem.toMap());

    return mediaItem;
  }

  // Export file (decrypt and save to specified location)
  Future<File> exportFile({
    required MediaItem item,
    required String exportPath,
  }) async {
    // Get decrypted bytes
    final bytes = await getMediaBytes(item);

    // Determine filename based on type
    String exportName;
    if (item.originalName != null) {
      exportName = item.originalName!;
    } else {
      // Generate filename based on media type
      switch (item.type) {
        case MediaType.photo:
          exportName = 'vault_photo_${item.id}.jpg';
          break;
        case MediaType.video:
          exportName = 'vault_video_${item.id}.mp4';
          break;
        case MediaType.note:
          exportName = 'vault_note_${item.id}.md';
          break;
        case MediaType.file:
          exportName = 'exported_${item.id}';
          break;
      }
    }
    final fullPath = '$exportPath/$exportName';

    // Write to export location
    final exportFile = File(fullPath);
    await exportFile.writeAsBytes(bytes);

    return exportFile;
  }

  // Get export directory (Downloads folder)
  Future<Directory> getExportDirectory() async {
    // On Android, use external storage Downloads folder
    final dir = Directory('/storage/emulated/0/Download');
    if (await dir.exists()) {
      return dir;
    }
    // Fallback to app documents directory
    return await getApplicationDocumentsDirectory();
  }

  // Close database
  Future<void> close() async {
    await _database?.close();
  }
}
