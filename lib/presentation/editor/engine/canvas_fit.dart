import 'dart:math' as math;
import 'dart:ui';

/// The rectangle a raster buffer occupies inside its display area when fitted
/// with uniform scale (contain), the scale factor used, and the user's view
/// rotation about that rectangle's centre.
///
/// A single source of truth shared by the painter and the coordinate mapper.
/// If these two computed fit independently they would drift apart whenever the
/// raster and display aspect ratios differ, stretching the image in one place
/// while mapping touches against another.
///
/// Use [applyTo] and [toRaster] rather than deriving a transform from
/// [destination] directly. Once [rotation] is non-zero the rectangle alone no
/// longer describes where the canvas is drawn, and a caller that subtracts
/// [destination] and divides by [scale] by hand silently ignores it.
class CanvasFit {
  const CanvasFit({
    required this.destination,
    required this.scale,
    this.rotation = 0.0,
  });

  /// Where the raster is drawn within the display area, in display pixels,
  /// before [rotation] is applied.
  final Rect destination;

  /// Uniform display-pixels-per-raster-pixel factor (same on both axes).
  final double scale;

  /// View rotation in radians, applied about [destination]'s centre.
  final double rotation;

  /// Concatenates the raster-space-to-display transform onto [canvas].
  ///
  /// After this call the canvas draws in raster pixel coordinates, so a caller
  /// paints at buffer coordinates and lets the fit place them. Wrap in
  /// save/restore — this mutates the canvas transform.
  void applyTo(Canvas canvas) {
    if (rotation != 0.0) {
      final centre = destination.center;
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(rotation);
      canvas.translate(-centre.dx, -centre.dy);
    }
    canvas.translate(destination.left, destination.top);
    canvas.scale(scale);
  }

  /// Inverts [applyTo]: maps a display-space point to raster coordinates.
  ///
  /// The result is unclamped and may fall outside the buffer when the point
  /// lies in the letterbox margin; bounds handling belongs to the caller.
  Offset toRaster(Offset displayPoint) {
    var point = displayPoint;

    if (rotation != 0.0) {
      final centre = destination.center;
      final relative = point - centre;
      final cos = math.cos(-rotation);
      final sin = math.sin(-rotation);
      point =
          Offset(
            relative.dx * cos - relative.dy * sin,
            relative.dx * sin + relative.dy * cos,
          ) +
          centre;
    }

    return Offset(
      (point.dx - destination.left) / scale,
      (point.dy - destination.top) / scale,
    );
  }
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
///
/// [rotation] widens those extents: a rotated rectangle covers an axis-aligned
/// span of `w·|cos| + h·|sin|`, which at intermediate angles is substantially
/// larger than its unrotated width. Clamping against the unrotated extent would
/// lock pan while the canvas visibly still overflows the screen. The
/// axis-aligned bounding box is used rather than the exact rotated hull, so the
/// clamp stays marginally conservative near the corners — it can only restrict
/// slightly early, never let the canvas escape the viewport.
Offset clampViewPan({
  required Rect baseRect,
  required Size displaySize,
  required double zoom,
  required Offset pan,
  double rotation = 0.0,
}) {
  final width = baseRect.width * zoom;
  final height = baseRect.height * zoom;

  final cos = math.cos(rotation).abs();
  final sin = math.sin(rotation).abs();
  final extentX = width * cos + height * sin;
  final extentY = width * sin + height * cos;

  final overflowX = (extentX - displaySize.width) / 2;
  final overflowY = (extentY - displaySize.height) / 2;
  final maxX = overflowX > 0 ? overflowX : 0.0;
  final maxY = overflowY > 0 ? overflowY : 0.0;
  return Offset(pan.dx.clamp(-maxX, maxX), pan.dy.clamp(-maxY, maxY));
}

/// The contain-fit with a user [zoom], [pan] and [rotation] composed on top,
/// scaled and rotated about the base fit's centre and translated by the clamped
/// pan.
///
/// Returns the same [CanvasFit] shape the painter and coordinate mapper already
/// consume, so both stay driven by one transform and cannot drift. When the
/// view is idle (zoom 1, no pan, no rotation) it returns the untouched base fit,
/// so disabling the feature is exactly the pre-zoom behaviour rather than a
/// near-copy of it.
CanvasFit fitRasterWithView({
  required Size rasterSize,
  required Size displaySize,
  required double zoom,
  required Offset pan,
  double rotation = 0.0,
}) {
  final base = fitRasterInDisplay(
    rasterSize: rasterSize,
    displaySize: displaySize,
  );

  if (zoom == 1.0 && pan == Offset.zero && rotation == 0.0) return base;

  final clampedPan = clampViewPan(
    baseRect: base.destination,
    displaySize: displaySize,
    zoom: zoom,
    pan: pan,
    rotation: rotation,
  );

  return CanvasFit(
    destination: Rect.fromCenter(
      center: base.destination.center + clampedPan,
      width: base.destination.width * zoom,
      height: base.destination.height * zoom,
    ),
    scale: base.scale * zoom,
    rotation: rotation,
  );
}