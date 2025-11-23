import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE media (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            filename TEXT NOT NULL,
            thumbnail_path TEXT,
            created_at INTEGER NOT NULL
          )
        ''');
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

  // Delete media item
  Future<void> deleteMedia(MediaItem item) async {
    // Delete file
    final vaultDir = await _getVaultDirectory();
    final filePath = '${vaultDir.path}/${item.filename}';
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
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

  // Close database
  Future<void> close() async {
    await _database?.close();
  }
}
