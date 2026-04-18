import '../models/inspection_log.dart';
import '../models/reference_image.dart';
import 'storage_service.dart';

/// Web-compilation stub for [StorageMobile].
///
/// Pulled in by the conditional import in `storage_service.dart` when
/// `dart.library.io` is absent. Keeps `package:sqflite` and
/// `package:path_provider` out of the Web build graph.
///
/// The factory in [StorageService.create] returns [StorageWeb] on Web, so
/// these methods are never reached at runtime.
class StorageMobile implements StorageService {
  @override
  Future<void> initialize() async {
    throw UnsupportedError(
      'StorageMobile is not available on Web. Use StorageWeb instead.',
    );
  }

  @override
  Future<void> saveLog(InspectionLog log) async =>
      throw UnsupportedError('StorageMobile unavailable on Web.');

  @override
  Future<List<InspectionLog>> getLogs({int limit = 200}) async =>
      throw UnsupportedError('StorageMobile unavailable on Web.');

  @override
  Future<Map<String, dynamic>> getStats() async =>
      throw UnsupportedError('StorageMobile unavailable on Web.');

  @override
  Future<void> resetShift() async =>
      throw UnsupportedError('StorageMobile unavailable on Web.');

  @override
  Future<String> exportCsv() async =>
      throw UnsupportedError('StorageMobile unavailable on Web.');

  @override
  Future<void> saveReference(ReferenceImage ref) async =>
      throw UnsupportedError('StorageMobile unavailable on Web.');

  @override
  Future<List<ReferenceImage>> getReferences() async =>
      throw UnsupportedError('StorageMobile unavailable on Web.');

  @override
  Future<void> deleteReference(String id) async =>
      throw UnsupportedError('StorageMobile unavailable on Web.');
}
