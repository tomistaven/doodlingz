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

/// Clamps a user pan offset so the zoomed canvas can never be dragged off the
/// viewport, returning the corrected offset.
///
/// Per axis the canvas may only be panned by how far it overflows the display
/// at the given [zoom]. When the canvas is not larger than the display on an
/// axis (the letterboxed axis, or any axis at zoom 1) the overflow is zero, so
/// pan locks to centred there — that is what keeps zoom 1 pinned exactly to the
/// contain-fit position and the canvas always at least partly visible.
Offset clampViewPan({
  required Rect baseRect,
  required Size displaySize,
  required double zoom,
  required Offset pan,
}) {
  final overflowX = (baseRect.width * zoom - displaySize.width) / 2;
  final overflowY = (baseRect.height * zoom - displaySize.height) / 2;
  final maxX = overflowX > 0 ? overflowX : 0.0;
  final maxY = overflowY > 0 ? overflowY : 0.0;
  return Offset(pan.dx.clamp(-maxX, maxX), pan.dy.clamp(-maxY, maxY));
}

/// The contain-fit with a user [zoom] and [pan] composed on top, scaled about
/// the base fit's centre and translated by the clamped pan.
///
/// Returns the same [CanvasFit] shape the painter and coordinate mapper already
/// consume, so both stay driven by one transform and cannot drift. When the
/// view is idle (zoom 1, no pan) it returns the untouched base fit, so disabling
/// the feature is exactly the pre-zoom behaviour rather than a near-copy of it.
CanvasFit fitRasterWithView({
  required Size rasterSize,
  required Size displaySize,
  required double zoom,
  required Offset pan,
}) {
  final base = fitRasterInDisplay(
    rasterSize: rasterSize,
    displaySize: displaySize,
  );

  if (zoom == 1.0 && pan == Offset.zero) return base;

  final clampedPan = clampViewPan(
    baseRect: base.destination,
    displaySize: displaySize,
    zoom: zoom,
    pan: pan,
  );

  return CanvasFit(
    destination: Rect.fromCenter(
      center: base.destination.center + clampedPan,
      width: base.destination.width * zoom,
      height: base.destination.height * zoom,
    ),
    scale: base.scale * zoom,
  );
}
