import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/canvas_constants.dart';
import 'flood_fill.dart';
import 'stroke.dart';
import 'stroke_renderer.dart';

/// Composites drawing operations onto an immutable [ui.Image] raster buffer.
///
/// Every method takes the current committed image and returns a new one,
/// leaving the input untouched so the snapshot stack remains clean.
class CanvasCompositor {
  /// Creates a blank white canvas at the given [size].
  static Future<ui.Image> createBlank(Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = CanvasConstants.canvasColor,
    );
    final picture = recorder.endRecording();
    return picture.toImage(size.width.toInt(), size.height.toInt());
  }

  /// Loads PNG [bytes] into a raster [ui.Image] that keeps the source's exact
  /// aspect ratio, scaled so the total pixel area fits within
  /// [CanvasConstants.rasterPixelBudget].
  ///
  /// The buffer reshapes to the image — no crop, no letterbox. A small image is
  /// never upscaled past its own size; a large one is downscaled until its area
  /// is under budget. Saved app drawings already sit within budget so they
  /// short-circuit to a 1:1 return. The whole source is drawn into a buffer of
  /// exactly the target shape, so the draw is a straight fit with no overflow.
  static Future<ui.Image> fromBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final source = frame.image;

    final sourceArea = source.width * source.height;
    // Downscale only. sqrt(budget/area) is the linear factor that brings the
    // area to budget while holding aspect ratio; clamp to 1.0 so we never
    // enlarge an already-small image.
    final scale = sourceArea <= CanvasConstants.rasterPixelBudget
        ? 1.0
        : sqrt(CanvasConstants.rasterPixelBudget / sourceArea);

    if (scale == 1.0) {
      return source;
    }

    final targetWidth = (source.width * scale).round();
    final targetHeight = (source.height * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final srcRect = Rect.fromLTWH(
      0,
      0,
      source.width.toDouble(),
      source.height.toDouble(),
    );
    final dstRect = Rect.fromLTWH(
      0,
      0,
      targetWidth.toDouble(),
      targetHeight.toDouble(),
    );
    canvas.drawImageRect(
      source,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    final picture = recorder.endRecording();
    return picture.toImage(targetWidth, targetHeight);
  }

  /// Commits a completed [stroke] onto [current], returning a new image.
  static Future<ui.Image> commitStroke(ui.Image current, Stroke stroke) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    canvas.drawImage(current, Offset.zero, Paint());
    paintStroke(canvas, stroke);

    final picture = recorder.endRecording();
    return picture.toImage(current.width, current.height);
  }

  /// Commits a shape preview (line, rect, ellipse, triangle) onto [current].
  static Future<ui.Image> commitShape(ui.Image current, Stroke stroke) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    canvas.drawImage(current, Offset.zero, Paint());
    paintShape(canvas, stroke);

    final picture = recorder.endRecording();
    return picture.toImage(current.width, current.height);
  }

  /// Runs flood fill on [current] at [rasterPoint] with [fillColor].
  ///
  /// The pixel manipulation runs on a background isolate via [compute]
  /// to avoid blocking the UI thread on large fills.
  static Future<ui.Image> commitFill(
    ui.Image current,
    Offset rasterPoint,
    Color fillColor,
  ) async {
    final byteData = await current.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (byteData == null) return current;

    final pixels = byteData.buffer.asUint8List();
    final filled = await compute(
      floodFill,
      FloodFillParams(
        pixels: pixels,
        width: current.width,
        height: current.height,
        startX: rasterPoint.dx.round().clamp(0, current.width - 1),
        startY: rasterPoint.dy.round().clamp(0, current.height - 1),
        fillColor: _colorToFillInt(fillColor),
        tolerance: CanvasConstants.fillColorTolerance,
      ),
    );

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      filled,
      current.width,
      current.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// Encodes [current] to PNG bytes for saving.
  static Future<Uint8List> toPngBytes(ui.Image current) async {
    final byteData = await current.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // Packs a Flutter [Color] into 0xAARRGGBB int for the flood fill isolate.
  static int _colorToFillInt(Color color) {
    return ((color.a * 255.0).round().clamp(0, 255) << 24) |
        ((color.r * 255.0).round().clamp(0, 255) << 16) |
        ((color.g * 255.0).round().clamp(0, 255) << 8) |
        (color.b * 255.0).round().clamp(0, 255);
  }
}
