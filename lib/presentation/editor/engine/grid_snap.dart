import 'dart:ui';

/// Rounds a raster-space point to the nearest grid intersection.
///
/// Kept separate from [paintGrid] so pixel art mode's coordinate snapping
/// never depends on grid rendering — a caller can snap points with a grid
/// that is not even visible.
Offset snapToGrid(Offset rasterPoint, double cellSize) {
  return Offset(
    (rasterPoint.dx / cellSize).round() * cellSize,
    (rasterPoint.dy / cellSize).round() * cellSize,
  );
}