import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/constants/canvas_constants.dart';
import '../../../domain/entities/drawing_tool.dart';
import '../engine/canvas_compositor.dart';
import '../engine/coordinate_mapper.dart';
import '../engine/stroke.dart';

/// Holds the complete mutable state of the drawing canvas.
class CanvasState {
  const CanvasState({
    required this.committedImage,
    required this.activeStroke,
    required this.canUndo,
    required this.canRedo,
  });

  final ui.Image committedImage;
  final Stroke? activeStroke;
  final bool canUndo;
  final bool canRedo;
}

/// Drives the drawing canvas.
///
/// Owned and created directly by [EditorScreen] — not registered in get_it —
/// so its lifetime is tied to the screen, not the app. This avoids the
/// stale singleton instance trap when navigating away and back.
///
/// High-frequency pointer events update state via [ValueNotifier] rather
/// than BLoC to avoid per-event overhead on the platform channel.
class CanvasController extends ValueNotifier<CanvasState> {
  CanvasController() : super(_placeholder);

  static final _placeholder = CanvasState(
    committedImage: _emptyImage(),
    activeStroke: null,
    canUndo: false,
    canRedo: false,
  );

  final List<ui.Image> _undoStack = [];
  final List<ui.Image> _redoStack = [];

  late Size _rasterSize;
  late Size _displaySize;

  bool _initialised = false;

  /// Must be called once before any drawing operations.
  ///
  /// [rasterSize] is the fixed pixel buffer size.
  /// [displaySize] is the current rendered canvas widget size.
  Future<void> initialise({
    required Size rasterSize,
    required Size displaySize,
    ui.Image? existingImage,
  }) async {
    _rasterSize = rasterSize;
    _displaySize = displaySize;

    final image =
        existingImage ?? await CanvasCompositor.createBlank(rasterSize);

    _initialised = true;
    _notify(image, null);
  }

  /// Updates the display size when the canvas widget is resized or rotated.
  void updateDisplaySize(Size displaySize) {
    _displaySize = displaySize;
  }

  void onPointerDown(
    Offset localPosition,
    DrawingTool tool,
    Color color,
    double size,
  ) {
    if (!_initialised) return;

    final rasterPoint = localToRaster(
      localPosition: localPosition,
      displaySize: _displaySize,
      rasterSize: _rasterSize,
    );

    if (tool == DrawingTool.fill) {
      _commitFill(rasterPoint, color);
      return;
    }

    final stroke = Stroke(
      drawingTool: tool,
      color: tool == DrawingTool.eraser ? CanvasConstants.canvasColor : color,
      size: size,
      points: [rasterPoint],
    );

    _notifyWithStroke(stroke);
  }

  void onPointerMove(Offset localPosition) {
    if (!_initialised) return;
    final current = value.activeStroke;
    if (current == null) return;

    final rasterPoint = localToRaster(
      localPosition: localPosition,
      displaySize: _displaySize,
      rasterSize: _rasterSize,
    );

    if (current.isFreehand) {
      if (current.drawingTool == DrawingTool.spray) {
        _addSprayPoints(current, rasterPoint);
        return;
      }
      _notifyWithStroke(current.withPoint(rasterPoint));
      return;
    }

    final updated = Stroke(
      drawingTool: current.drawingTool,
      color: current.color,
      size: current.size,
      points: [current.points.first, rasterPoint],
    );
    _notifyWithStroke(updated);
  }

  void onPointerUp() {
    if (!_initialised) return;
    final stroke = value.activeStroke;
    if (stroke == null) return;
    _commitStroke(stroke);
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(value.committedImage);
    final previous = _undoStack.removeLast();
    _notify(previous, null);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(value.committedImage);
    final next = _redoStack.removeLast();
    _notify(next, null);
  }

  Future<Uint8List> toPngBytes() =>
      CanvasCompositor.toPngBytes(value.committedImage);

  Future<void> _commitStroke(Stroke stroke) async {
    _pushUndo(value.committedImage);
    final next = stroke.isShape
        ? await CanvasCompositor.commitShape(value.committedImage, stroke)
        : await CanvasCompositor.commitStroke(value.committedImage, stroke);
    _notify(next, null);
  }

  Future<void> _commitFill(Offset rasterPoint, Color color) async {
    _pushUndo(value.committedImage);
    final next = await CanvasCompositor.commitFill(
      value.committedImage,
      rasterPoint,
      color,
    );
    _notify(next, null);
  }

  void _addSprayPoints(Stroke current, Offset centre) {
    final random = Random();
    final radius = current.size;
    final newPoints = List.generate(CanvasConstants.sprayDensity, (_) {
      final angle = random.nextDouble() * 2 * pi;
      final distance = random.nextDouble() * radius;
      return Offset(
        (centre.dx + cos(angle) * distance).clamp(0.0, _rasterSize.width - 1),
        (centre.dy + sin(angle) * distance)
            .clamp(0.0, _rasterSize.height - 1),
      );
    });
    _notifyWithStroke(Stroke(
      drawingTool: current.drawingTool,
      color: current.color,
      size: current.size / 4,
      points: [...current.points, ...newPoints],
    ));
  }

  void _pushUndo(ui.Image image) {
    _undoStack.add(image);
    if (_undoStack.length > CanvasConstants.maxHistorySteps) {
      _undoStack.removeAt(0);
    }
    // A new action clears the redo branch.
    _redoStack.clear();
  }

  void _notify(ui.Image image, Stroke? stroke) {
    value = CanvasState(
      committedImage: image,
      activeStroke: stroke,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
  }

  void _notifyWithStroke(Stroke stroke) {
    value = CanvasState(
      committedImage: value.committedImage,
      activeStroke: stroke,
      canUndo: value.canUndo,
      canRedo: value.canRedo,
    );
  }

  static ui.Image _emptyImage() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()..color = const Color(0x00000000),
    );
    return recorder.endRecording().toImageSync(1, 1);
  }
}