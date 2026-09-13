import 'dart:ui' show Color, Offset;

import '../../../domain/entities/drawing_tool.dart';

/// Holds the data for a single in-progress drawing action.
///
/// Created on pointer-down, updated on pointer-move, and committed to the
/// raster buffer on pointer-up. Not persisted — exists only during a gesture.
class Stroke {
  Stroke({
    required this.drawingTool,
    required this.color,
    required this.size,
    this.isPixelArt = false,
    this.pixelCellSize = 0,
    List<Offset>? points,
  }) : points = points ?? [];

  final DrawingTool drawingTool;
  final Color color;

  /// Stroke width or spray radius in raster pixels.
  final double size;

  /// True when this stroke was started in pixel art mode. Locked at
  /// pointer-down like [drawingTool] — a stroke can't switch behavior
  /// mid-drag, matching how the tool itself can't change mid-stroke.
  final bool isPixelArt;

  /// Grid cell size in raster pixels, used as the stamped square's side
  /// length. Only meaningful when [isPixelArt] is true; 0 otherwise.
  final double pixelCellSize;

  /// Accumulated pointer positions in raster space.
  final List<Offset> points;

  bool get isHighlighter => drawingTool == DrawingTool.highlighter;

  bool get isShape =>
      drawingTool == DrawingTool.line ||
      drawingTool == DrawingTool.rectangle ||
      drawingTool == DrawingTool.ellipse ||
      drawingTool == DrawingTool.triangle;

  bool get isFreehand =>
      drawingTool == DrawingTool.brush ||
      drawingTool == DrawingTool.highlighter ||
      drawingTool == DrawingTool.eraser ||
      drawingTool == DrawingTool.spray;

  /// Returns a copy with an additional [point] appended.
  Stroke withPoint(Offset point) => Stroke(
    drawingTool: drawingTool,
    color: color,
    size: size,
    isPixelArt: isPixelArt,
    pixelCellSize: pixelCellSize,
    points: [...points, point],
  );
}