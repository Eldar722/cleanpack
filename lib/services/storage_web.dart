import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inspection_log.dart';
import '../models/reference_image.dart';
import 'storage_service.dart';

class StorageWeb implements StorageService {
  static const _logsKey = 'tazalens_logs';
  static const _refsKey = 'tazalens_refs';
  SharedPreferences? _prefs;

  @override
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> _ensureInitialized() async {
    if (_prefs != null) return;
    await initialize();
  }

  SharedPreferences get _p => _prefs!;

  List<Map<String, dynamic>> _readList(String key) {
    final raw = _p.getString(key);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .cast<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _writeList(String key, List list) =>
      _p.setString(key, jsonEncode(list));

  @override
  Future<void> saveLog(InspectionLog log) async {
    await _ensureInitialized();
    final list = _readList(_logsKey);
    list.insert(0, log.toJson());
    if (list.length > 10000) list.removeRange(10000, list.length);
    await _writeList(_logsKey, list);
  }

  @override
  Future<List<InspectionLog>> getLogs({int limit = 200}) async {
    await _ensureInitialized();
    final list = _readList(_logsKey);
    return list.take(limit).map(InspectionLog.fromJson).toList();
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    await _ensureInitialized();
    final list = _readList(_logsKey);
    final total = list.length;
    final defects = list.where((e) => e['result'] == 'DEFECT').length;
    return {
      'total': total,
      'defects': defects,
      'ok': total - defects,
      'defect_percent': total == 0 ? 0.0 : defects / total * 100,
    };
  }

  @override
  Future<void> resetShift() async {
    await _ensureInitialized();
    await _p.remove(_logsKey);
  }

  static String _q(String s) => '"${s.replaceAll('"', '""')}"';

  @override
  Future<String> exportCsv() async {
    final logs = await getLogs(limit: 10000);
    final buf = StringBuffer('id,position_id,timestamp,result,defect_type,confidence,ssim\n');
    for (final l in logs) {
      buf.writeln(
          '${_q(l.id)},${_q(l.positionId)},${l.timestamp.toIso8601String()},${l.result},${_q(l.defectType)},${l.confidence.toStringAsFixed(3)},${l.ssimScore?.toStringAsFixed(3) ?? ''}');
    }
    return buf.toString();
  }

  @override
  Future<void> saveReference(ReferenceImage ref) async {
    await _ensureInitialized();
    final list = _readList(_refsKey);
    list.insert(0, ref.toJson());
    if (list.length > 100) list.removeRange(100, list.length);
    await _writeList(_refsKey, list);
  }

  @override
  Future<List<ReferenceImage>> getReferences() async {
    await _ensureInitialized();
    final list = _readList(_refsKey);
    return list.map(ReferenceImage.fromJson).toList();
  }

  @override
  Future<void> deleteReference(String id) async {
    await _ensureInitialized();
    final list = _readList(_refsKey);
    list.removeWhere((e) => e['id'] == id);
    await _writeList(_refsKey, list);
  }
}
