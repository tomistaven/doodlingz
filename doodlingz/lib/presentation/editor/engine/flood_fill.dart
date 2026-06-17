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

  while (queue.isNotEmpty) {
    final pos = queue.removeLast();
    final x = pos % width;
    final y = pos ~/ width;

    if (x < 0 || x >= width || y < 0 || y >= height) continue;

    final idx = pos * 4;
    if (!_withinTolerance(
      pixels[idx],
      pixels[idx + 1],
      pixels[idx + 2],
      pixels[idx + 3],
      targetR,
      targetG,
      targetB,
      targetA,
      params.tolerance,
    )) {
      continue;
    }

    // Check the pixel hasn't already been filled in a previous iteration.
    if (pixels[idx] == fillR &&
        pixels[idx + 1] == fillG &&
        pixels[idx + 2] == fillB &&
        pixels[idx + 3] == fillA) {
      continue;
    }

    pixels[idx] = fillR;
    pixels[idx + 1] = fillG;
    pixels[idx + 2] = fillB;
    pixels[idx + 3] = fillA;

    if (x + 1 < width) queue.add(pos + 1);
    if (x - 1 >= 0) queue.add(pos - 1);
    if (y + 1 < height) queue.add(pos + width);
    if (y - 1 >= 0) queue.add(pos - width);
  }

  return pixels;
}

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
