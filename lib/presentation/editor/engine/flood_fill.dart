import 'dart:typed_data';

/// Parameters bundle for passing flood fill arguments through [compute].
///
/// All fields are plain Dart types so the object crosses isolate boundaries
/// without serialisation issues.
class FloodFillParams {
  const FloodFillParams({
    required this.pixels,
    required this.width,
    required this.height,
    required this.startX,
    required this.startY,
    required this.fillColor,
    required this.tolerance,
  });

  final Uint8List pixels;
  final int width;
  final int height;
  final int startX;
  final int startY;

  /// Fill color packed as 0xAARRGGBB.
  final int fillColor;
  final int tolerance;
}

/// Performs an iterative 4-connected flood fill on a raw RGBA pixel buffer.
///
/// Anti-aliased pixels right at a stroke's edge sit between the target
/// color and the boundary color, so a hard tolerance cutoff either leaves
/// a visible unfilled ring (tolerance too low) or eats into the boundary
/// stroke itself (tolerance too high, or spatial dilation — see below).
///
/// Instead, every pixel the main fill reaches but rejects on tolerance is
/// blended toward the fill color in proportion to how close that pixel's
/// own original color already was to the target. A pixel that's mostly
/// target color (e.g. a faint AA fringe) gets mostly filled; a pixel
/// that's mostly boundary color (e.g. the solid stroke itself) is barely
/// touched. This is a per-pixel decision based only on that pixel's own
/// color — unlike spatial dilation, it can never penetrate further than
/// the single ring of genuinely-blended edge pixels, so it can't eat
/// through a stroke regardless of how thin that stroke is.
///
/// Returns a new [Uint8List] with the filled pixels. The input buffer is
/// never mutated, keeping the caller's snapshot state clean.
///
/// Designed as a top-level function so it can be passed directly to
/// [compute] and executed on a background isolate without UI jank.
Uint8List floodFill(FloodFillParams params) {
  final pixels = Uint8List.fromList(params.pixels);
  final width = params.width;
  final height = params.height;

  final fillA = (params.fillColor >> 24) & 0xFF;
  final fillR = (params.fillColor >> 16) & 0xFF;
  final fillG = (params.fillColor >> 8) & 0xFF;
  final fillB = params.fillColor & 0xFF;

  final targetIndex = (params.startY * width + params.startX) * 4;
  final targetR = pixels[targetIndex];
  final targetG = pixels[targetIndex + 1];
  final targetB = pixels[targetIndex + 2];
  final targetA = pixels[targetIndex + 3];

  // Nothing to do if the target pixel is already the fill color.
  if (targetR == fillR &&
      targetG == fillG &&
      targetB == fillB &&
      targetA == fillA) {
    return pixels;
  }

  final queue = <int>[];
  queue.add(params.startY * width + params.startX);

  // Tracks pixels visited by the main fill so the same edge pixel isn't
  // queued and blended more than once from different directions.
  final processedMask = Uint8List(width * height);

  while (queue.isNotEmpty) {
    final pos = queue.removeLast();
    if (processedMask[pos] == 1) continue;
    processedMask[pos] = 1;

    final x = pos % width;
    final y = pos ~/ width;
    if (x < 0 || x >= width || y < 0 || y >= height) continue;

    final idx = pos * 4;
    final r = pixels[idx];
    final g = pixels[idx + 1];
    final b = pixels[idx + 2];
    final a = pixels[idx + 3];

    if (!_withinTolerance(
      r,
      g,
      b,
      a,
      targetR,
      targetG,
      targetB,
      targetA,
      params.tolerance,
    )) {
      // Out of tolerance: an anti-aliased edge pixel. Blend it toward the
      // fill color by how close it already is to the target, rather than
      // either skipping it (leaves a gap) or fully filling it (bleeds).
      _blendEdgePixel(
        pixels: pixels,
        idx: idx,
        r: r,
        g: g,
        b: b,
        a: a,
        targetR: targetR,
        targetG: targetG,
        targetB: targetB,
        targetA: targetA,
        fillR: fillR,
        fillG: fillG,
        fillB: fillB,
        fillA: fillA,
      );
      continue;
    }

    // Composite the fill color over the existing pixel using srcOver so the
    // raster buffer stays fully opaque. Writing fillA directly would store
    // transparent pixels, which look correct on screen (white desk behind
    // them) but break on export and in the gallery — the same failure mode
    // as the BlendMode.clear eraser bug.
    pixels[idx] = _srcOver(pixels[idx], fillR, fillA);
    pixels[idx + 1] = _srcOver(pixels[idx + 1], fillG, fillA);
    pixels[idx + 2] = _srcOver(pixels[idx + 2], fillB, fillA);
    pixels[idx + 3] = 255;

    if (x + 1 < width) queue.add(pos + 1);
    if (x - 1 >= 0) queue.add(pos - 1);
    if (y + 1 < height) queue.add(pos + width);
    if (y - 1 >= 0) queue.add(pos - width);
  }

  return pixels;
}

// Blends [idx] toward the fill color by a factor derived from how close its
// original channels were to the target color. Uses the channel with the
// LEAST similarity to target (i.e. the worst-case channel) so a pixel that's
// only close to target in one channel but far in another — which would
// otherwise read as "mostly target" — is correctly treated as mostly
// boundary instead.
void _blendEdgePixel({
  required Uint8List pixels,
  required int idx,
  required int r,
  required int g,
  required int b,
  required int a,
  required int targetR,
  required int targetG,
  required int targetB,
  required int targetA,
  required int fillR,
  required int fillG,
  required int fillB,
  required int fillA,
}) {
  final diffR = (r - targetR).abs();
  final diffG = (g - targetG).abs();
  final diffB = (b - targetB).abs();
  final diffA = (a - targetA).abs();
  final worstDiff = [
    diffR,
    diffG,
    diffB,
    diffA,
  ].reduce((a, b) => a > b ? a : b);

  // 0.0 = as far from target as a channel can be (pure boundary, untouched).
  // 1.0 = identical to target (would already have passed tolerance above).
  final closeness = 1.0 - (worstDiff / 255.0);
  if (closeness <= 0.0) return;

  final blendedFillA = (fillA * closeness).round().clamp(0, 255);
  pixels[idx] = _srcOver(r, _lerp(r, fillR, closeness), blendedFillA);
  pixels[idx + 1] = _srcOver(g, _lerp(g, fillG, closeness), blendedFillA);
  pixels[idx + 2] = _srcOver(b, _lerp(b, fillB, closeness), blendedFillA);
  pixels[idx + 3] = 255;
}

int _lerp(int from, int to, double t) =>
    (from + (to - from) * t).round().clamp(0, 255);

// Composites [src] over [dst] for one channel, assuming dstA = 255 (the
// canvas buffer is always opaque). Returns the composited value at full
// opacity so the buffer stays opaque after any fill regardless of fillA.
int _srcOver(int dst, int src, int srcA) =>
    ((src * srcA + dst * (255 - srcA)) ~/ 255).clamp(0, 255);

bool _withinTolerance(
  int r,
  int g,
  int b,
  int a,
  int tr,
  int tg,
  int tb,
  int ta,
  int tolerance,
) {
  return (r - tr).abs() <= tolerance &&
      (g - tg).abs() <= tolerance &&
      (b - tb).abs() <= tolerance &&
      (a - ta).abs() <= tolerance;
}
