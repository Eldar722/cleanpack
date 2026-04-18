import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/inspection_log.dart';
import '../models/reference_image.dart';
import 'storage_service.dart';

class StorageMobile implements StorageService {
  Database? _db;
  Completer<void>? _initCompleter;

  @override
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'tazalens.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE logs (
            id TEXT PRIMARY KEY,
            position_id TEXT NOT NULL,
            ts TEXT NOT NULL,
            result TEXT NOT NULL,
            defect_type TEXT,
            confidence REAL,
            ssim REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE refs (
            id TEXT PRIMARY KEY,
            name TEXT,
            created_at TEXT,
            bytes BLOB,
            w INTEGER,
            h INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('DROP TABLE IF EXISTS logs');
          await db.execute('''
            CREATE TABLE logs (
              id TEXT PRIMARY KEY,
              position_id TEXT NOT NULL,
              ts TEXT NOT NULL,
              result TEXT NOT NULL,
              defect_type TEXT,
              confidence REAL,
              ssim REAL
            )
          ''');
        }
      },
    );
  }

  Future<void> _ensureInitialized() async {
    if (_db != null) return;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<void>();
    try {
      await initialize();
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  Database get _d => _db!;

  @override
  Future<void> saveLog(InspectionLog log) async {
    await _ensureInitialized();
    await _d.insert('logs', {
      'id': log.id,
      'position_id': log.positionId,
      'ts': log.timestamp.toIso8601String(),
      'result': log.result,
      'defect_type': log.defectType,
      'confidence': log.confidence,
      'ssim': log.ssimScore,
    });
  }

  @override
  Future<List<InspectionLog>> getLogs({int limit = 200}) async {
    await _ensureInitialized();
    final rows = await _d.query('logs', orderBy: 'ts DESC', limit: limit);
    return rows
        .map((r) => InspectionLog(
              id: r['id'] as String,
              positionId: r['position_id'] as String? ?? 'Не указано',
              timestamp: DateTime.parse(r['ts'] as String),
              result: r['result'] as String,
              defectType: (r['defect_type'] as String?) ?? 'none',
              confidence: (r['confidence'] as num?)?.toDouble() ?? 0.0,
              ssimScore: (r['ssim'] as num?)?.toDouble(),
            ))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    await _ensureInitialized();
    final total = Sqflite.firstIntValue(
            await _d.rawQuery('SELECT COUNT(*) FROM logs')) ??
        0;
    final defects = Sqflite.firstIntValue(await _d
            .rawQuery("SELECT COUNT(*) FROM logs WHERE result='DEFECT'")) ??
        0;
    return {
      'total': total,
      'defects': defects,
      'ok': total - defects,
      'defect_percent':
          total == 0 ? 0.0 : (defects / total * 100).toDouble(),
    };
  }

  @override
  Future<void> resetShift() async {
    await _ensureInitialized();
    await _d.delete('logs');
  }

  static String _q(String s) =>
      '"${s.replaceAll('"', '""').replaceAll('\n', ' ').replaceAll('\r', ' ')}"';

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
    await _d.insert('refs', {
      'id': ref.id,
      'name': ref.name,
      'created_at': ref.createdAt.toIso8601String(),
      'bytes': ref.bytes,
      'w': ref.width,
      'h': ref.height,
    });
  }

  @override
  Future<List<ReferenceImage>> getReferences() async {
    await _ensureInitialized();
    final rows = await _d.query('refs', orderBy: 'created_at DESC');
    return rows
        .map((r) => ReferenceImage(
              id: r['id'] as String,
              name: (r['name'] as String?) ?? 'Эталон',
              createdAt: DateTime.parse(r['created_at'] as String),
              bytes: List<int>.from(r['bytes'] as List),
              width: r['w'] as int,
              height: r['h'] as int,
            ))
        .toList();
  }

  @override
  Future<void> deleteReference(String id) async {
    await _ensureInitialized();
    await _d.delete('refs', where: 'id = ?', whereArgs: [id]);
  }
}

// unused import guard
// ignore: unused_element
void _jsonShim() => jsonEncode({});
