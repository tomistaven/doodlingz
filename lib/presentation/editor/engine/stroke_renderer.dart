import 'dart:ui';

import '../../../domain/entities/drawing_tool.dart';
import 'stroke.dart';

/// Single source of truth for how each [DrawingTool] is drawn onto a [Canvas].
///
/// Used by both `DrawingCanvasPainter` (live preview, every pointer-move
/// frame) and `CanvasCompositor` (one-shot raster commit on pointer-up).
/// Previously this logic was written twice — once per file — and the two
/// copies drifted: the spray tool committed as a solid line while previewing
/// as scattered dots, and shape corners previewed rounded but committed
/// mitered. Routing both call sites through these functions makes that class
/// of bug structurally impossible: there is only one implementation to drift
/// from.
///
/// Takes a plain [Canvas] because `dart:ui`'s [Canvas] and
/// `package:flutter/material.dart`'s re-export are the same type — both the
/// painter (UI-thread `CustomPainter`) and the compositor
/// (`PictureRecorder`-backed) can call these directly.
///
/// Builds the [Paint] for a freehand or shape stroke.
///
/// Highlighter gets a multiply blend mode and reduced alpha so overlapping
/// strokes darken like a real highlighter instead of opaquely covering what's
/// beneath. Every other tool — including shapes — uses the stroke's color and
/// a round cap/join, which is also the corner style shapes commit with.
Paint buildStrokePaint(Stroke stroke) {
  final paint = Paint()
    ..color = stroke.color
    ..strokeWidth = stroke.size
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  if (stroke.isHighlighter) {
    paint.blendMode = BlendMode.multiply;
    paint.color = stroke.color.withValues(alpha: 0.4);
  }

  return paint;
}

/// Draws a freehand stroke (brush, highlighter, eraser) as a traced path.
///
/// A single-point stroke (a tap with no drag) renders as a filled dot the
/// width of the brush, so a tap is visible instead of invisible.
void paintFreehand(Canvas canvas, Stroke stroke) {
  if (stroke.points.isEmpty) return;

  final paint = buildStrokePaint(stroke);

  if (stroke.points.length == 1) {
    canvas.drawCircle(stroke.points.first, stroke.size / 2, paint);
    return;
  }

  final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
  for (final point in stroke.points.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  canvas.drawPath(path, paint);
}

/// Draws spray points as independent filled dots rather than a connected
/// path — spray points are scattered, not sequential.
void paintSpray(Canvas canvas, Stroke stroke) {
  final paint = Paint()
    ..color = stroke.color.withValues(alpha: stroke.color.a * 0.4)
    ..style = PaintingStyle.fill;

  for (final point in stroke.points) {
    // Fixed small radius for a fine mist regardless of the tool's size slider
    canvas.drawCircle(point, 1.2, paint);
  }
}

/// Draws a shape stroke (line, rectangle, ellipse, triangle) between the
/// stroke's first and last point.
void paintShape(Canvas canvas, Stroke stroke) {
  if (stroke.points.length < 2) return;

  final paint = buildStrokePaint(stroke);
  final start = stroke.points.first;
  final end = stroke.points.last;
  final rect = Rect.fromPoints(start, end);

  switch (stroke.drawingTool) {
    case DrawingTool.line:
      canvas.drawLine(start, end, paint);
    case DrawingTool.rectangle:
      canvas.drawRect(rect, paint);
    case DrawingTool.ellipse:
      canvas.drawOval(rect, paint);
    case DrawingTool.triangle:
      final path = Path()
        ..moveTo(rect.topCenter.dx, rect.topCenter.dy)
        ..lineTo(rect.bottomLeft.dx, rect.bottomLeft.dy)
        ..lineTo(rect.bottomRight.dx, rect.bottomRight.dy)
        ..close();
      canvas.drawPath(path, paint);
    case DrawingTool.brush:
    case DrawingTool.highlighter:
    case DrawingTool.spray:
    case DrawingTool.eraser:
    case DrawingTool.fill:
      // Not shape tools; paintShape is never called for these. Listed
      // explicitly rather than a default case so adding a tool without
      // updating this switch is a compile error, not a silent no-op.
      break;
  }
}

/// Dispatches a single stroke to the correct paint function for its tool.
///
/// The one place that decides shape vs. spray vs. plain freehand, so the
/// painter and compositor make that decision identically.
void paintStroke(Canvas canvas, Stroke stroke) {
  if (stroke.points.isEmpty) return;

  if (stroke.isShape) {
    paintShape(canvas, stroke);
    return;
  }

  if (stroke.drawingTool == DrawingTool.spray) {
    paintSpray(canvas, stroke);
    return;
  }

  paintFreehand(canvas, stroke);
}