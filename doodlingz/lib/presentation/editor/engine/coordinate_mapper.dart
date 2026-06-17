import 'dart:ui';

/// Maps a pointer position in screen (display) space to the corresponding
/// pixel coordinate in the fixed raster buffer.
///
/// [localPosition] is the pointer offset relative to the top-left corner
/// of the rendered canvas widget.
/// [displaySize] is the current rendered size of the canvas widget in
/// logical pixels.
/// [rasterSize] is the fixed pixel dimensions of the underlying buffer
/// (one of [CanvasConstants.portraitCanvasSize] or
/// [CanvasConstants.landscapeCanvasSize]).
///
/// Returns an [Offset] clamped to valid pixel indices so callers never
/// index out of bounds on the raw byte buffer.
Offset localToRaster({
  required Offset localPosition,
  required Size displaySize,
  required Size rasterSize,
}) {
  final scaleX = rasterSize.width / displaySize.width;
  final scaleY = rasterSize.height / displaySize.height;

  final rx = (localPosition.dx * scaleX).clamp(0.0, rasterSize.width - 1);
  final ry = (localPosition.dy * scaleY).clamp(0.0, rasterSize.height - 1);

  return Offset(rx, ry);
}
