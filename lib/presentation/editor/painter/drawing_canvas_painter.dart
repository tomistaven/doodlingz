import 'package:flutter/material.dart';

import '../controller/canvas_state.dart';
import '../engine/canvas_fit.dart';
import '../engine/grid_renderer.dart';
import '../engine/stroke_renderer.dart';

/// Renders the committed raster image, the active stroke overlay and the grid.
///
/// All three are drawn inside a single transform block in raster coordinates,
/// so the view's zoom, pan and rotation are applied once and cannot diverge
/// between layers. The committed image is drawn first, then the in-progress
/// stroke on top as a cheap vector overlay — avoiding a full raster commit on
/// every pointer-move event — and the grid last of all.
class DrawingCanvasPainter extends CustomPainter {
  const DrawingCanvasPainter({required this.state});

  final CanvasState state;

  @override
  void paint(Canvas canvas, Size size) {
    // CustomPainter does not clip to its size; without this a zoomed canvas
    // spills magnified pixels over the paper border and onto the desk margin.
    // Applied before the fit transform so it clips in display space.
    canvas.clipRect(Offset.zero & size);

    final image = state.committedImage;
    final rasterSize = Size(image.width.toDouble(), image.height.toDouble());

    final fit = fitRasterWithView(
      rasterSize: rasterSize,
      displaySize: size,
      zoom: state.view.zoom,
      pan: state.view.pan,
      rotation: state.view.rotation,
    );

    canvas.save();
    fit.applyTo(canvas);

    final rasterRect = Offset.zero & rasterSize;

    // Smooths out the sub-pixel aliasing jump when the vector is rasterized
    canvas.drawImageRect(
      image,
      rasterRect,
      rasterRect,
      Paint()..filterQuality = FilterQuality.high,
    );

    final stroke = state.activeStroke;
    if (stroke != null && stroke.points.isNotEmpty) {
      paintStroke(canvas, stroke);
    }

    // Drawn last so the grid sits above the live stroke the same way it sits
    // above committed pixels. Painting it under the overlay let an in-progress
    // stroke cover grid lines until the frame it committed — most visible with
    // the eraser, whose canvas-coloured fill blanked the lines outright.
    if (state.grid.visible) {
      paintGrid(canvas, rasterSize, state.grid);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(DrawingCanvasPainter oldDelegate) =>
      oldDelegate.state != state;
}