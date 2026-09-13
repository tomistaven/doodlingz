import 'dart:ui';

import 'canvas_fit.dart';

/// Maps a pointer position in screen (display) space to the corresponding
/// pixel coordinate in the raster buffer.
///
/// [localPosition] is the pointer offset relative to the top-left corner of the
/// rendered canvas widget. [displaySize] is the current rendered size of that
/// widget in logical pixels. [rasterSize] is the pixel dimensions of the
/// underlying buffer, which may be any aspect ratio once an image is imported.
///
/// [zoom], [pan] and [rotation] apply the user's viewport transform; at their
/// defaults the mapping is the plain contain-fit. The inverse is taken by
/// [CanvasFit.toRaster] rather than re-derived here, so the mapping is
/// guaranteed to invert the exact transform the painter drew with. Result is
/// clamped to valid pixel indices so callers never index out of bounds, which
/// also folds a touch in the letterbox margin onto the nearest edge pixel.
Offset localToRaster({
  required Offset localPosition,
  required Size displaySize,
  required Size rasterSize,
  double zoom = 1.0,
  Offset pan = Offset.zero,
  double rotation = 0.0,
}) {
  final fit = fitRasterWithView(
    rasterSize: rasterSize,
    displaySize: displaySize,
    zoom: zoom,
    pan: pan,
    rotation: rotation,
  );

  final raster = fit.toRaster(localPosition);

  // Clamped per axis after the inverse, never before: under rotation the two
  // axes are mixed, so an out-of-bounds display point has to be mapped into
  // raster space first for the clamp to land on the edge pixel the user is
  // actually nearest to.
  return Offset(
    raster.dx.clamp(0.0, rasterSize.width - 1),
    raster.dy.clamp(0.0, rasterSize.height - 1),
  );
}