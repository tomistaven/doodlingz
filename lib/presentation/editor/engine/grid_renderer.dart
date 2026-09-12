import 'dart:ui';

/// User-configurable grid overlay state.
///
/// [cellSize] is in raster pixels, not display pixels. Grid lines are drawn
/// inside the same raster-space transform block the stroke overlay uses, so a
/// raster-space cell size scales correctly with zoom automatically — a
/// display-pixel cell size would need separate correction math under zoom.
class GridSettings {
  const GridSettings({required this.visible, required this.cellSize});

  static const GridSettings disabled = GridSettings(
    visible: false,
    cellSize: 16.0,
  );

  final bool visible;
  final double cellSize;
}

/// Draws grid lines spaced [GridSettings.cellSize] apart across [rasterSize].
///
/// Called from within the same translate/scale block `DrawingCanvasPainter`
/// uses for the raster-space stroke overlay, so lines are in raster
/// coordinates here and the caller's transform handles zoom/pan.
void paintGrid(Canvas canvas, Size rasterSize, GridSettings grid) {
  if (!grid.visible || grid.cellSize <= 0) return;

  final paint = Paint()
    ..color = const Color(0x33000000)
    ..strokeWidth = 0;

  for (var x = grid.cellSize; x < rasterSize.width; x += grid.cellSize) {
    canvas.drawLine(Offset(x, 0), Offset(x, rasterSize.height), paint);
  }

  for (var y = grid.cellSize; y < rasterSize.height; y += grid.cellSize) {
    canvas.drawLine(Offset(0, y), Offset(rasterSize.width, y), paint);
  }
}