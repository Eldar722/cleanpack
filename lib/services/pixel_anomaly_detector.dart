import 'dart:collection';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/detection_result.dart';

/// Luminance-based anomaly detector that works directly on CameraImage
/// without any ML model. Detects dark spots (hair, dirt, sawdust, latex)
/// against the bright polyester fiber background.
///
/// Algorithm:
///   1. Sample the Y-plane (luma) of the YUV420 frame at reduced resolution.
///   2. Compute mean luminance of the scene.
///   3. Pixels significantly darker than the mean are "anomaly candidates".
///   4. BFS groups candidates into connected regions.
///   5. Regions above a minimum size become DetectionObjects.
///
/// Why this works for polyester fiber:
///   Fiber is typically bright white (luma 160–230). Hair, dirt, sawdust,
///   latex are significantly darker (luma 20–120). The contrast is reliable
///   under standard industrial lighting (500–2000 lux).
class PixelAnomalyDetector {
  // Downsample to this grid for speed (~5ms on mid-range Android)
  static const int _gW = 80;
  static const int _gH = 60;

  // A pixel is "dark" if its luma < mean * _darkFactor
  static const double _darkFactor = 0.62;

  // Minimum connected dark cells to report as a detection
  static const int _minCells = 5;

  // Maximum regions to return per frame (avoid UI flooding)
  static const int _maxRegions = 6;

  // Skip detection if mean luma is too low (bad lighting / dark scene)
  static const int _minMeanLuma = 45;

  List<DetectionObject> detect(CameraImage frame) {
    try {
      if (frame.format.group != ImageFormatGroup.yuv420) return const [];
      final yPlane = frame.planes[0];
      final fw = frame.width;
      final fh = frame.height;

      // Sample luma grid
      final grid = List.generate(_gH, (_) => List.filled(_gW, 0));
      double sum = 0;

      for (int gy = 0; gy < _gH; gy++) {
        for (int gx = 0; gx < _gW; gx++) {
          final px = (gx * fw / _gW).round().clamp(0, fw - 1);
          final py = (gy * fh / _gH).round().clamp(0, fh - 1);
          final idx = py * yPlane.bytesPerRow + px;
          final luma =
              idx < yPlane.bytes.length ? (yPlane.bytes[idx] & 0xff) : 128;
          grid[gy][gx] = luma;
          sum += luma;
        }
      }

      final mean = sum / (_gW * _gH);
      if (mean < _minMeanLuma) return const []; // too dark / bad lighting

      final threshold = (mean * _darkFactor).round();

      // Build dark-cell mask
      final dark = List.generate(
          _gH, (y) => List.generate(_gW, (x) => grid[y][x] < threshold));

      // BFS flood fill — iterative to avoid stack overflow on large regions
      final visited =
          List.generate(_gH, (_) => List.filled(_gW, false));
      final regions = <_Region>[];

      for (int y = 0; y < _gH && regions.length < _maxRegions; y++) {
        for (int x = 0; x < _gW && regions.length < _maxRegions; x++) {
          if (!dark[y][x] || visited[y][x]) continue;
          final region = _bfs(dark, visited, x, y);
          if (region.cells >= _minCells) regions.add(region);
        }
      }

      return regions.map(_toDetection).toList();
    } catch (_) {
      return const [];
    }
  }

  _Region _bfs(
      List<List<bool>> dark, List<List<bool>> visited, int sx, int sy) {
    int minX = sx, maxX = sx, minY = sy, maxY = sy, cells = 0;
    final queue = Queue<int>();
    queue.add(sy * _gW + sx);
    visited[sy][sx] = true;

    while (queue.isNotEmpty) {
      final id = queue.removeFirst();
      final x = id % _gW;
      final y = id ~/ _gW;
      cells++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      for (final d in const [
        [-1, 0], [1, 0], [0, -1], [0, 1],
      ]) {
        final nx = x + (d[0] as int);
        final ny = y + (d[1] as int);
        if (nx < 0 || nx >= _gW || ny < 0 || ny >= _gH) continue;
        if (visited[ny][nx] || !dark[ny][nx]) continue;
        visited[ny][nx] = true;
        queue.add(ny * _gW + nx);
      }
    }
    return _Region(minX, maxX, minY, maxY, cells);
  }

  DetectionObject _toDetection(_Region r) {
    final left = r.minX / _gW;
    final top = r.minY / _gH;
    final w = (r.maxX - r.minX + 1) / _gW;
    final h = (r.maxY - r.minY + 1) / _gH;
    final aspect = w / h.clamp(0.01, 100.0);
    // Confidence: proportional to region density (bigger anomaly = more confident)
    final confidence = (0.55 + r.cells / (_gW * _gH) * 30).clamp(0.55, 0.94);
    return DetectionObject(
      label: _classify(r.cells, aspect),
      confidence: confidence,
      bbox: Rect.fromLTWH(left, top, w, h),
    );
  }

  /// Classify anomaly type by shape heuristics:
  ///  - Very elongated → hair or fiber thread
  ///  - Large area     → dirt patch / sawdust cluster
  ///  - Small compact  → particle / foreign object
  static String _classify(int cells, double aspectRatio) {
    if (aspectRatio > 3.5 || aspectRatio < 0.28) return 'Волос/нить';
    if (cells > 25) return 'Загрязнение';
    if (cells > 10) return 'Опилки/частицы';
    return 'Посторонний объект';
  }
}

class _Region {
  final int minX, maxX, minY, maxY, cells;
  const _Region(this.minX, this.maxX, this.minY, this.maxY, this.cells);
}
