class ReferenceImage {
  final String id;
  final String name;
  final DateTime createdAt;
  /// Raw bytes of a downscaled reference image (PNG encoded).
  final List<int> bytes;
  final int width;
  final int height;

  const ReferenceImage({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.bytes,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'bytes': bytes,
        'w': width,
        'h': height,
      };

  factory ReferenceImage.fromJson(Map<String, dynamic> j) => ReferenceImage(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        bytes: List<int>.from(j['bytes'] as List),
        width: j['w'] as int,
        height: j['h'] as int,
      );
}
