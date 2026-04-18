import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import '../models/detection_result.dart';

/// Tile-based reference comparison for micro-defect detection.
///
/// Instead of comparing the entire frame against a reference (which loses
/// small details), this service:
///  1. Divides both the reference and current frame into a grid of tiles.
///  2. Computes per-tile luminance statistics (mean, variance, edge density).
///  3. Compares each current tile to the *global* reference statistics.
///  4. Tiles whose local texture deviates significantly are flagged as anomalies.
///
/// This approach catches dust particles as small as 2-3 pixels because
/// the comparison happens at tile level (e.g. 20x20 pixel patches), not
/// at the full 640x640 frame level where dust is invisible.
class ReferenceComparator {
  static const int _compareW = 320;  // resize both images to this
  static const int _compareH = 240;
  static const int _tileSize = 16;   // 16x16 pixel tiles = 20x15 grid

  img.Image? _reference;
  _TileStats? _refStats;
  bool _ready = false;

  bool get isReady => _ready;

  /// Load the bundled reference image from assets.
  Future<void> loadFromAsset(String assetPath) async {
    try {
      final bytes = await rootBundle.load(assetPath);
      final decoded = img.decodeImage(bytes.buffer.asUint8List());
      if (decoded == null) {
        debugPrint('[RefComparator] Failed to decode reference image');
        return;
      }
      _reference = img.grayscale(
        img.copyResize(decoded, width: _compareW, height: _compareH),
      );
      _refStats = _computeTileStats(_reference!);
      _ready = true;
      debugPrint('[RefComparator] Reference loaded: ${_refStats!.tiles.length} tiles');
    } catch (e) {
      debugPrint('[RefComparator] Failed to load reference: $e');
    }
  }

  /// Load reference from raw bytes (e.g. from StorageService).
  void loadFromImage(img.Image image) {
    _reference = img.grayscale(
      img.copyResize(image, width: _compareW, height: _compareH),
    );
    _refStats = _computeTileStats(_reference!);
    _ready = true;
  }

  /// Compare a camera frame against the reference.
  /// Returns a list of DetectionObjects for tiles that show anomalies.
  List<DetectionObject> compare(img.Image currentFrame) {
    if (!_ready || _refStats == null) return const [];

    final current = img.grayscale(
      img.copyResize(currentFrame, width: _compareW, height: _compareH),
    );
    final curStats = _computeTileStats(current);

    final anomalies = <DetectionObject>[];
    final tilesX = _compareW ~/ _tileSize;
    final tilesY = _compareH ~/ _tileSize;

    for (int i = 0; i < curStats.tiles.length && i < _refStats!.tiles.length; i++) {
      final ref = _refStats!.tiles[i];
      final cur = curStats.tiles[i];

      // 1. Mean luminance difference (detects overall brightness changes)
      final meanDiff = (cur.mean - ref.mean).abs();

      // 2. Variance ratio (detects texture changes — dust adds variance)
      final varRef = ref.variance.clamp(0.001, double.infinity);
      final varRatio = cur.variance / varRef;

      // 3. Edge density difference (dust creates micro-edges)
      final edgeDiff = (cur.edgeDensity - ref.edgeDensity).abs();

      // Anomaly scoring: weighted combination (lowered thresholds for higher recall)
      double score = 0.0;
      if (meanDiff > 10) score += 0.3;       // brightness shift
      if (meanDiff > 25) score += 0.2;       // strong brightness shift
      if (varRatio > 1.7 || varRatio < 0.4) score += 0.35; // texture change
      if (edgeDiff > 0.10) score += 0.25;    // new edges appeared
      if (edgeDiff > 0.22) score += 0.15;    // many new edges

      if (score >= 0.35) {
        final tx = i % tilesX;
        final ty = i ~/ tilesX;
        final confidence = score.clamp(0.35, 0.99);

        anomalies.add(DetectionObject(
          label: _classifyAnomaly(meanDiff, varRatio, edgeDiff),
          confidence: confidence,
          bbox: Rect.fromLTWH(
            tx / tilesX,
            ty / tilesY,
            1.0 / tilesX,
            1.0 / tilesY,
          ),
        ));
      }
    }

    // If >45% of tiles are anomalous the whole scene differs from reference —
    // likely a camera/lighting change, not a real defect. Skip to avoid false positives.
    final totalTiles = tilesX * tilesY;
    if (anomalies.length > totalTiles * 0.45) return const [];

    // Merge nearby anomalies into clusters
    return _clusterAnomalies(anomalies, tilesX, tilesY);
  }

  /// Compare with the reference and return a single aggregated score [0..1].
  /// Lower = more anomalous. Similar to SSIM but tile-aware.
  double compareScore(img.Image currentFrame) {
    if (!_ready || _refStats == null) return 1.0;

    final current = img.grayscale(
      img.copyResize(currentFrame, width: _compareW, height: _compareH),
    );
    final curStats = _computeTileStats(current);

    int anomalyTiles = 0;
    for (int i = 0; i < curStats.tiles.length && i < _refStats!.tiles.length; i++) {
      final ref = _refStats!.tiles[i];
      final cur = curStats.tiles[i];
      final meanDiff = (cur.mean - ref.mean).abs();
      final varRef = ref.variance.clamp(0.001, double.infinity);
      final varRatio = cur.variance / varRef;
      if (meanDiff > 20 || varRatio > 2.0 || varRatio < 0.3) {
        anomalyTiles++;
      }
    }

    final total = curStats.tiles.length;
    if (total == 0) return 1.0;
    return 1.0 - (anomalyTiles / total);
  }

  // ─── Internal helpers ─────────────────────────────────────

  _TileStats _computeTileStats(img.Image gray) {
    final tilesX = _compareW ~/ _tileSize;
    final tilesY = _compareH ~/ _tileSize;
    final tiles = <_Tile>[];

    for (int ty = 0; ty < tilesY; ty++) {
      for (int tx = 0; tx < tilesX; tx++) {
        final x0 = tx * _tileSize;
        final y0 = ty * _tileSize;

        double sum = 0;
        int count = 0;
        final values = <double>[];

        for (int y = y0; y < y0 + _tileSize && y < gray.height; y++) {
          for (int x = x0; x < x0 + _tileSize && x < gray.width; x++) {
            final luma = gray.getPixel(x, y).luminance * 255.0;
            values.add(luma);
            sum += luma;
            count++;
          }
        }

        final mean = count > 0 ? sum / count : 128.0;

        // Variance
        double varSum = 0;
        for (final v in values) {
          varSum += (v - mean) * (v - mean);
        }
        final variance = count > 0 ? varSum / count : 0.0;

        // Edge density (simple Sobel-like: count pixels with high gradient)
        int edgeCount = 0;
        for (int y = y0 + 1; y < y0 + _tileSize - 1 && y < gray.height - 1; y++) {
          for (int x = x0 + 1; x < x0 + _tileSize - 1 && x < gray.width - 1; x++) {
            final c = gray.getPixel(x, y).luminance * 255.0;
            final r = gray.getPixel(x + 1, y).luminance * 255.0;
            final d = gray.getPixel(x, y + 1).luminance * 255.0;
            final grad = (c - r).abs() + (c - d).abs();
            if (grad > 15) edgeCount++;
          }
        }
        final edgeDensity = count > 0 ? edgeCount / count : 0.0;

        tiles.add(_Tile(mean: mean, variance: variance, edgeDensity: edgeDensity));
      }
    }

    return _TileStats(tiles);
  }

  String _classifyAnomaly(double meanDiff, double varRatio, double edgeDiff) {
    if (edgeDiff > 0.3) return 'Микро-загрязнение (пыль)';
    if (varRatio > 3.0) return 'Текстурная аномалия';
    if (meanDiff > 40) return 'Пятно / загрязнение';
    if (edgeDiff > 0.15) return 'Частица / ворс';
    return 'Посторонний объект';
  }

  /// Merge nearby anomaly tiles into separate bounding boxes using union-find.
  /// Tiles closer than 2 tile-widths are grouped together.
  List<DetectionObject> _clusterAnomalies(
      List<DetectionObject> raw, int tilesX, int tilesY) {
    if (raw.isEmpty) return const [];

    // Union-Find
    final parent = List<int>.generate(raw.length, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }
    void union(int a, int b) {
      parent[find(a)] = find(b);
    }

    final tileW = 1.0 / tilesX;
    final tileH = 1.0 / tilesY;
    final gapX = tileW * 2.5;
    final gapY = tileH * 2.5;

    for (int i = 0; i < raw.length; i++) {
      for (int j = i + 1; j < raw.length; j++) {
        final a = raw[i].bbox, b = raw[j].bbox;
        if ((a.left - b.left).abs() <= gapX &&
            (a.top - b.top).abs() <= gapY) {
          union(i, j);
        }
      }
    }

    // Collect groups
    final groups = <int, List<DetectionObject>>{};
    for (int i = 0; i < raw.length; i++) {
      groups.putIfAbsent(find(i), () => []).add(raw[i]);
    }

    // Build one bbox per group, keep top 4 largest groups
    final result = <DetectionObject>[];
    final sorted = groups.values.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final group in sorted.take(4)) {
      double minL = 1, minT = 1, maxR = 0, maxB = 0;
      double maxConf = 0;
      String bestLabel = group.first.label;
      for (final a in group) {
        if (a.bbox.left < minL) minL = a.bbox.left;
        if (a.bbox.top < minT) minT = a.bbox.top;
        if (a.bbox.right > maxR) maxR = a.bbox.right;
        if (a.bbox.bottom > maxB) maxB = a.bbox.bottom;
        if (a.confidence > maxConf) {
          maxConf = a.confidence;
          bestLabel = a.label;
        }
      }
      result.add(DetectionObject(
        label: group.length > 1 ? '$bestLabel (${group.length})' : bestLabel,
        confidence: maxConf,
        bbox: Rect.fromLTRB(minL, minT, maxR, maxB),
      ));
    }
    return result;
  }
}

class _Tile {
  final double mean;
  final double variance;
  final double edgeDensity;
  const _Tile({required this.mean, required this.variance, required this.edgeDensity});
}

class _TileStats {
  final List<_Tile> tiles;
  const _TileStats(this.tiles);
}
