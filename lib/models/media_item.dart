enum MediaType {
  photo,
  video,
}

class MediaItem {
  final String id;
  final MediaType type;
  final String filename;
  final String? thumbnailPath;
  final DateTime createdAt;

  MediaItem({
    required this.id,
    required this.type,
    required this.filename,
    this.thumbnailPath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type == MediaType.photo ? 'photo' : 'video',
      'filename': filename,
      'thumbnail_path': thumbnailPath,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory MediaItem.fromMap(Map<String, dynamic> map) {
    return MediaItem(
      id: map['id'],
      type: map['type'] == 'photo' ? MediaType.photo : MediaType.video,
      filename: map['filename'],
      thumbnailPath: map['thumbnail_path'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
    );
  }
}
