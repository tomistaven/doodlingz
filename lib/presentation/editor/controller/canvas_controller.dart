import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/constants/canvas_constants.dart';
import '../../../domain/entities/drawing_tool.dart';
import '../engine/canvas_compositor.dart';
import '../engine/coordinate_mapper.dart';
import '../engine/stroke.dart';
import 'canvas_state.dart';

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
    isDirty: false,
  );

  final List<ui.Image> _undoStack = [];
  final List<ui.Image> _redoStack = [];

  bool _dirty = false;

  // Defaults to the portrait preset so the canvas can be laid out at the right
  // aspect ratio before initialise() runs; an import later reshapes it.
  Size _rasterSize = CanvasConstants.portraitCanvasSize;
  late Size _displaySize;

  // The most recent editor area (full available space, not the fitted canvas).
  // A fresh canvas is shaped to this so it fills the screen without letterbox.
  Size _editorArea = CanvasConstants.portraitCanvasSize;

  bool _initialised = false;

  bool get isInitialised => _initialised;

  /// Current raster buffer dimensions. Drives the canvas widget's aspect ratio.
  Size get rasterSize => _rasterSize;

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

    _dirty = false;
    _initialised = true;
    _notify(image, null);
  }

  /// Updates the display size when the canvas widget is resized or rotated.
  void updateDisplaySize(Size displaySize) {
    _displaySize = displaySize;
  }

  /// Records the editor's available area so a fresh canvas can be shaped to fill
  /// it. A plain field assignment with no notify, safe to call during build.
  void setEditorArea(Size area) {
    _editorArea = area;
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
    _dirty = true;
    _notify(previous, null);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(value.committedImage);
    final next = _redoStack.removeLast();
    _dirty = true;
    _notify(next, null);
  }

  /// Wipes the canvas back to white as a single undoable action.
  Future<void> clear() async {
    if (!_initialised) return;
    _pushUndo(value.committedImage);
    final blank = await CanvasCompositor.createBlank(_rasterSize);
    _notify(blank, null);
  }

  /// Starts a fresh drawing: blank canvas, no history, not dirty.
  ///
  /// Unlike [clear] this is not undoable — it abandons the previous drawing
  /// entirely, including its undo/redo branches, so the editor is in the same
  /// state as a cold launch. That includes the canvas shape: an import may have
  /// left the raster at an arbitrary aspect ratio, so reset rebuilds it to fill
  /// the current editor area.
  Future<void> reset() async {
    if (!_initialised) return;
    _rasterSize = CanvasConstants.rasterSizeForArea(_editorArea);
    _undoStack.clear();
    _redoStack.clear();
    _dirty = false;
    final blank = await CanvasCompositor.createBlank(_rasterSize);
    _notify(blank, null);
  }

  /// Swaps in a loaded image, wipes history, and marks the canvas clean.
  ///
  /// Parallel to [reset] but with content instead of blank. The loaded image
  /// defines the new raster size, so an imported landscape photo flips the
  /// buffer to landscape and the coordinate mapper, clear, and spray clamps all
  /// follow. Safe to call only after [initialise] has completed — callers must
  /// guard on [isInitialised].
  void loadImage(ui.Image image) {
    if (!_initialised) return;
    _rasterSize = Size(image.width.toDouble(), image.height.toDouble());
    _undoStack.clear();
    _redoStack.clear();
    _dirty = false;
    _notify(image, null);
  }

  /// Marks the current committed image as persisted, clearing the dirty flag
  /// without altering pixels or history.
  void markSaved() {
    if (!_dirty) return;
    _dirty = false;
    _notify(value.committedImage, value.activeStroke);
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
      // Multiplying two randoms heavily weights the distribution toward the center
      final distance = (random.nextDouble() * random.nextDouble()) * radius;
      return Offset(
        (centre.dx + cos(angle) * distance).clamp(0.0, _rasterSize.width - 1),
        (centre.dy + sin(angle) * distance)
            .clamp(0.0, _rasterSize.height - 1),
      );
    });
    _notifyWithStroke(Stroke(
      drawingTool: current.drawingTool,
      color: current.color,
      size: current.size,
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
    // Every committed action funnels through here, so this is the single
    // point where the drawing becomes dirty.
    _dirty = true;
  }

  void _notify(ui.Image image, Stroke? stroke) {
    value = CanvasState(
      committedImage: image,
      activeStroke: stroke,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
      isDirty: _dirty,
    );
  }

  void _notifyWithStroke(Stroke stroke) {
    value = CanvasState(
      committedImage: value.committedImage,
      activeStroke: stroke,
      canUndo: value.canUndo,
      canRedo: value.canRedo,
      isDirty: _dirty,
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