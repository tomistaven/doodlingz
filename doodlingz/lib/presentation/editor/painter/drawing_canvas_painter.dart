import 'package:flutter/material.dart';

import '../../../domain/entities/drawing_tool.dart';
import '../controller/canvas_controller.dart';
import '../engine/stroke.dart';

/// Renders the committed raster image and the active stroke overlay.
///
/// The committed image is drawn first, then the in-progress stroke is
/// painted on top as a cheap vector overlay — avoiding a full raster
/// commit on every pointer-move event.
class DrawingCanvasPainter extends CustomPainter {
  const DrawingCanvasPainter({
    required this.state,
  });

  final CanvasState state;

  @override
  void paint(Canvas canvas, Size size) {
    _drawCommittedImage(canvas, size);

    final stroke = state.activeStroke;
    if (stroke != null && stroke.points.isNotEmpty) {
      _drawOverlay(canvas, size, stroke);
    }
  }

  void _drawCommittedImage(Canvas canvas, Size size) {
    final image = state.committedImage;
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Offset.zero & size;
    canvas.drawImageRect(image, src, dst, Paint());
  }

  void _drawOverlay(Canvas canvas, Size size, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final scaleX = size.width / state.committedImage.width;
    final scaleY = size.height / state.committedImage.height;

    canvas.save();
    canvas.scale(scaleX, scaleY);

    if (stroke.isShape) {
      _paintShape(canvas, stroke);
    } else {
      _paintFreehand(canvas, stroke);
    }

    canvas.restore();
  }

  void _paintFreehand(Canvas canvas, Stroke stroke) {
    if (stroke.drawingTool == DrawingTool.spray) {
      _paintSpray(canvas, stroke);
      return;
    }

    final paint = _buildPaint(stroke);

    if (stroke.points.length == 1) {
      canvas.drawCircle(stroke.points.first, stroke.size / 2, paint);
      return;
    }

    final path = Path()
      ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  // Spray points are random dots scattered around the finger — drawing them
  // as individual filled circles rather than a connected path.
  void _paintSpray(Canvas canvas, Stroke stroke) {
    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.fill;

    for (final point in stroke.points) {
      canvas.drawCircle(point, 2.5, paint);
    }
  }

  void _paintShape(Canvas canvas, Stroke stroke) {
    if (stroke.points.length < 2) return;
    final paint = _buildPaint(stroke);

    final start = stroke.points.first;
    final end = stroke.points.last;
    final rect = Rect.fromPoints(start, end);

    switch (stroke.drawingTool.name) {
      case 'line':
        canvas.drawLine(start, end, paint);
      case 'rectangle':
        canvas.drawRect(rect, paint);
      case 'ellipse':
        canvas.drawOval(rect, paint);
      case 'triangle':
        final path = Path()
          ..moveTo(rect.topCenter.dx, rect.topCenter.dy)
          ..lineTo(rect.bottomLeft.dx, rect.bottomLeft.dy)
          ..lineTo(rect.bottomRight.dx, rect.bottomRight.dy)
          ..close();
        canvas.drawPath(path, paint);
    }
  }

  Paint _buildPaint(Stroke stroke) {
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

  @override
  bool shouldRepaint(DrawingCanvasPainter oldDelegate) =>
      oldDelegate.state != state;
}