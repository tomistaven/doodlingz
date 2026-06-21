import 'dart:math' as math;
import 'dart:ui';

/// The rectangle a raster buffer occupies inside its display area when fitted
/// with uniform scale (contain), plus the scale factor used.
///
/// A single source of truth shared by the painter and the coordinate mapper.
/// If these two computed fit independently they would drift apart whenever the
/// raster and display aspect ratios differ, stretching the image in one place
/// while mapping touches against another.
class CanvasFit {
  const CanvasFit({required this.destination, required this.scale});

  /// Where the raster is drawn within the display area, in display pixels.
  final Rect destination;

  /// Uniform display-pixels-per-raster-pixel factor (same on both axes).
  final double scale;
}

/// Fits [rasterSize] inside [displaySize] with a single uniform scale and
/// centres it, leaving equal margins on the overflowing axis (letterbox).
///
/// Uniform scale is what preserves the image's aspect ratio: stretching width
/// and height by different factors is exactly the distortion this avoids.
CanvasFit fitRasterInDisplay({
  required Size rasterSize,
  required Size displaySize,
}) {
  final scale = math.min(
    displaySize.width / rasterSize.width,
    displaySize.height / rasterSize.height,
  );

  final width = rasterSize.width * scale;
  final height = rasterSize.height * scale;
  final left = (displaySize.width - width) / 2;
  final top = (displaySize.height - height) / 2;

  return CanvasFit(
    destination: Rect.fromLTWH(left, top, width, height),
    scale: scale,
  );
}