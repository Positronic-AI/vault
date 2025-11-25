enum MediaType {
  photo,
  video,
  note,
  file,
}

class MediaItem {
  final String id;
  final MediaType type;
  final String filename;
  final String? thumbnailPath;
  final String? originalName; // Original filename for imported files
  final DateTime createdAt;

  MediaItem({
    required this.id,
    required this.type,
    required this.filename,
    this.thumbnailPath,
    this.originalName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    String typeStr;
    switch (type) {
      case MediaType.photo:
        typeStr = 'photo';
        break;
      case MediaType.video:
        typeStr = 'video';
        break;
      case MediaType.note:
        typeStr = 'note';
        break;
      case MediaType.file:
        typeStr = 'file';
        break;
    }
    return {
      'id': id,
      'type': typeStr,
      'filename': filename,
      'thumbnail_path': thumbnailPath,
      'original_name': originalName,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  static MediaType _parseType(String type) {
    switch (type) {
      case 'photo':
        return MediaType.photo;
      case 'video':
        return MediaType.video;
      case 'note':
        return MediaType.note;
      case 'file':
        return MediaType.file;
      default:
        return MediaType.photo;
    }
  }

  factory MediaItem.fromMap(Map<String, dynamic> map) {
    return MediaItem(
      id: map['id'],
      type: _parseType(map['type']),
      filename: map['filename'],
      thumbnailPath: map['thumbnail_path'],
      originalName: map['original_name'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
    );
  }
}
