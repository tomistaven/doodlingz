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
/// The raster is fitted into the display with uniform scale and centred, so the
/// inverse mapping removes the centring offset first, then divides by the same
/// single scale the painter uses. Result is clamped to valid pixel indices so
/// callers never index out of bounds, which also folds a touch in the
/// letterbox margin onto the nearest edge pixel.
Offset localToRaster({
  required Offset localPosition,
  required Size displaySize,
  required Size rasterSize,
}) {
  final fit = fitRasterInDisplay(
    rasterSize: rasterSize,
    displaySize: displaySize,
  );

  final rx = ((localPosition.dx - fit.destination.left) / fit.scale)
      .clamp(0.0, rasterSize.width - 1);
  final ry = ((localPosition.dy - fit.destination.top) / fit.scale)
      .clamp(0.0, rasterSize.height - 1);

  return Offset(rx, ry);
}