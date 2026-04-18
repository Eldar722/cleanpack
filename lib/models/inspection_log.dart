class InspectionLog {
  final String id;
  final String positionId;
  final DateTime timestamp;
  final String result; // OK | DEFECT
  final String defectType;
  final double confidence;
  final double? ssimScore;

  const InspectionLog({
    required this.id,
    required this.positionId,
    required this.timestamp,
    required this.result,
    required this.defectType,
    required this.confidence,
    this.ssimScore,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'position_id': positionId,
        'timestamp': timestamp.toIso8601String(),
        'result': result,
        'defect_type': defectType,
        'confidence': confidence,
        'ssim': ssimScore,
      };

  factory InspectionLog.fromJson(Map<String, dynamic> j) => InspectionLog(
        id: j['id'] as String,
        positionId: j['position_id'] as String? ?? 'Не указано',
        timestamp: DateTime.parse(j['timestamp'] as String),
        result: j['result'] as String,
        defectType: j['defect_type'] as String? ?? 'none',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
        ssimScore: (j['ssim'] as num?)?.toDouble(),
      );

  bool get isDefect => result == 'DEFECT';
}
