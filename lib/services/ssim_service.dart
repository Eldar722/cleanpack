import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class SsimResult {
  final double score;
  final bool isAnomaly;
  const SsimResult(this.score, this.isAnomaly);
}

class SsimService {
  static const int _w = 160;
  static const int _h = 120;

  SsimResult compare(img.Image current, img.Image reference, double threshold) {
    final a = img.grayscale(img.copyResize(current, width: _w, height: _h));
    final b = img.grayscale(img.copyResize(reference, width: _w, height: _h));
    final score = _ssim(a, b);
    return SsimResult(score, score < threshold);
  }

  double _ssim(img.Image a, img.Image b) {
    final n = a.width * a.height;
    double sumA = 0, sumB = 0;
    for (int y = 0; y < a.height; y++) {
      for (int x = 0; x < a.width; x++) {
        sumA += a.getPixel(x, y).luminance;
        sumB += b.getPixel(x, y).luminance;
      }
    }
    final muA = sumA / n;
    final muB = sumB / n;

    double varA = 0, varB = 0, cov = 0;
    for (int y = 0; y < a.height; y++) {
      for (int x = 0; x < a.width; x++) {
        final va = a.getPixel(x, y).luminance - muA;
        final vb = b.getPixel(x, y).luminance - muB;
        varA += va * va;
        varB += vb * vb;
        cov += va * vb;
      }
    }
    varA /= n;
    varB /= n;
    cov /= n;

    // luminance from package:image is in [0.0, 1.0], so K1=0.01, K2=0.03
    const c1 = 0.0001; // (0.01)^2
    const c2 = 0.0009; // (0.03)^2
    final num = (2 * muA * muB + c1) * (2 * cov + c2);
    final den = (muA * muA + muB * muB + c1) * (varA + varB + c2);
    if (den == 0) return 1.0;
    return math.max(0, math.min(1, num / den));
  }

  /// Encodes an image as PNG bytes for storage.
  List<int> encodePng(img.Image image, {int maxW = 320, int maxH = 240}) {
    final scaled = img.copyResize(image, width: maxW, height: maxH);
    return img.encodePng(scaled);
  }

  img.Image decodePng(List<int> bytes) {
    return img.decodePng(Uint8List.fromList(bytes)) ?? img.Image(width: 1, height: 1);
  }
}
