import 'package:flutter/material.dart';

import '../controller/canvas_state.dart';
import '../engine/canvas_fit.dart';
import '../engine/grid_renderer.dart';
import '../engine/stroke_renderer.dart';

/// Renders the committed raster image, the active stroke overlay (plus its
/// mirror, if mirror mode is on), the grid, and the mirror axis guide.
///
/// The raster image, strokes, and grid are drawn inside a single transform
/// block in raster coordinates, so the view's zoom, pan and rotation are
/// applied once and cannot diverge between layers. The mirror axis guide is
/// the one layer drawn outside that block, in plain display coordinates —
/// see the comment at its call site for why.
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

    final mirrorStroke = state.mirrorStroke;
    if (mirrorStroke != null && mirrorStroke.points.isNotEmpty) {
      paintStroke(canvas, mirrorStroke);
    }

    // Drawn last so the grid sits above the live stroke the same way it sits
    // above committed pixels. Painting it under the overlay let an in-progress
    // stroke cover grid lines until the frame it committed — most visible with
    // the eraser, whose canvas-coloured fill blanked the lines outright.
    if (state.grid.visible) {
      paintGrid(canvas, rasterSize, state.grid);
    }

    canvas.restore();

    // Drawn after canvas.restore(), so entirely outside the raster transform
    // block — the same reason CanvasController._reflect converts through
    // display space rather than reflecting in raster coordinates. The guide
    // marks a line fixed on screen; if it were drawn inside the rotated
    // block it would rotate with the canvas and stop matching the axis
    // strokes are actually being folded across.
    if (state.mirrorGuideVisible) {
      _paintMirrorGuide(canvas, size);
    }
  }

  void _paintMirrorGuide(Canvas canvas, Size size) {
    // The canvas paper is opaque white (CanvasConstants.canvasColor), so a
    // light guide colour would be nearly invisible against it — needs a dark
    // tone to read as a line rather than disappear into the paper.
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..strokeWidth = 1.5;
    final x = size.width / 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(DrawingCanvasPainter oldDelegate) =>
      oldDelegate.state != state;
}