import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/inspection_log.dart';
import '../models/reference_image.dart';
// Conditional import: on Web, `dart.library.io` is absent, so the stub is
// used — this keeps `package:sqflite` / `package:path_provider` native
// bindings out of the Web build graph.
import 'storage_mobile_stub.dart'
    if (dart.library.io) 'storage_mobile.dart';
import 'storage_web.dart';

abstract class StorageService {
  Future<void> initialize();

  Future<void> saveLog(InspectionLog log);
  Future<List<InspectionLog>> getLogs({int limit = 200});
  Future<Map<String, dynamic>> getStats();
  Future<void> resetShift();
  Future<String> exportCsv();

  Future<void> saveReference(ReferenceImage ref);
  Future<List<ReferenceImage>> getReferences();
  Future<void> deleteReference(String id);

  static StorageService create() {
    if (kIsWeb) return StorageWeb();
    return StorageMobile();
  }
}
