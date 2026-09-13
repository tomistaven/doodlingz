import 'dart:math' as math;
import 'dart:ui';

/// Maps a raster-space point to the center of the grid cell it falls inside.
///
/// Rounding to the nearest grid line intersection (a previous version of
/// this function) is the wrong operation for pixel art: it snaps to a corner
/// shared by four cells, so a square stamped there straddles all four
/// instead of filling any single one. Flooring to the containing cell, then
/// offsetting by half a cell, lands on that cell's center instead — the
/// point a same-size stamped square needs to exactly fill one visible grid
/// square, matching what the grid overlay actually shows.
///
/// Kept separate from [paintGrid] so pixel art mode's coordinate snapping
/// never depends on grid rendering — a caller can snap points with a grid
/// that is not even visible.
Offset snapToGrid(Offset rasterPoint, double cellSize) {
  return Offset(
    (math.max(0, rasterPoint.dx) / cellSize).floor() * cellSize + cellSize / 2,
    (math.max(0, rasterPoint.dy) / cellSize).floor() * cellSize + cellSize / 2,
  );
}