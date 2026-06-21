import 'package:flutter/material.dart';

import '../controller/canvas_state.dart';
import '../engine/canvas_fit.dart';
import '../engine/stroke.dart';
import '../engine/stroke_renderer.dart';

/// Renders the committed raster image and the active stroke overlay.
///
/// The committed image is drawn first, then the in-progress stroke is
/// painted on top as a cheap vector overlay — avoiding a full raster
/// commit on every pointer-move event.
class DrawingCanvasPainter extends CustomPainter {
  const DrawingCanvasPainter({required this.state});

  final CanvasState state;

  @override
  void paint(Canvas canvas, Size size) {
    // CustomPainter does not clip to its size; without this a zoomed canvas
    // spills magnified pixels over the paper border and onto the desk margin.
    canvas.clipRect(Offset.zero & size);

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
    final fit = fitRasterWithView(
      rasterSize: Size(image.width.toDouble(), image.height.toDouble()),
      displaySize: size,
      zoom: state.view.zoom,
      pan: state.view.pan,
    );

    // Smooths out the sub-pixel aliasing jump when the vector is rasterized
    final paint = Paint()..filterQuality = FilterQuality.high;

    canvas.drawImageRect(image, src, fit.destination, paint);
  }

  void _drawOverlay(Canvas canvas, Size size, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final image = state.committedImage;
    final fit = fitRasterWithView(
      rasterSize: Size(image.width.toDouble(), image.height.toDouble()),
      displaySize: size,
      zoom: state.view.zoom,
      pan: state.view.pan,
    );

    canvas.save();
    canvas.translate(fit.destination.left, fit.destination.top);
    canvas.scale(fit.scale, fit.scale);
    paintStroke(canvas, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(DrawingCanvasPainter oldDelegate) =>
      oldDelegate.state != state;
}