import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/constants/canvas_constants.dart';
import '../../../domain/entities/drawing_tool.dart';
import '../engine/canvas_compositor.dart';
import '../engine/canvas_fit.dart';
import '../engine/coordinate_mapper.dart';
import '../engine/grid_renderer.dart';
import '../engine/grid_snap.dart';
import '../engine/stroke.dart';
import '../engine/view_transform.dart';
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

  // User viewport transform. ViewTransform.identity is the plain contain-fit,
  // in which state the painter and mapper take their pre-zoom fast path.
  ViewTransform _view = ViewTransform.identity;

  // Grid overlay state. Threaded through both _notify and _notifyWithStroke
  // like _view — omitting it from either would reset the grid to disabled
  // on the next pointer-move frame, since _notifyWithStroke fires every drag.
  GridSettings _grid = GridSettings.disabled;

  // Zoom at the start of the active scale gesture, so cumulative scale deltas
  // in applyGesture compose onto wherever the previous gesture left the view.
  double _viewStartZoom = 1.0;

  // Kept local to the view gesture rather than in CanvasConstants because they
  // are private to this transform; hoist them if another screen ever zooms.
  static const double _minZoom = 1.0;
  static const double _maxZoom = 5.0;

  // Fill is deferred from pointer-down to pointer-up. Unlike every other tool it
  // mutated the raster on touch-down, which fired before a second finger could
  // be seen — so a two-finger zoom flood-filled on the first touch. Stashing it
  // here lets cancelStroke discard it when the gesture turns into navigation.
  Offset? _pendingFill;
  Color? _pendingFillColor;

  // Spray flushes accumulated points into the raster mid-stroke to keep the
  // painter's per-frame drawCircle count bounded. The undo snapshot must be
  // taken once at pointer-down (before any flush), not per-flush, so the whole
  // spray gesture stays a single undo step.
  bool _sprayUndoSaved = false;

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

  /// Toggles the grid overlay on or off.
  void setGridVisible(bool visible) {
    _grid = GridSettings(visible: visible, cellSize: _grid.cellSize);
    _notify(value.committedImage, value.activeStroke);
  }

  /// Sets the grid cell size in raster pixels.
  void setGridCellSize(double cellSize) {
    _grid = GridSettings(visible: _grid.visible, cellSize: cellSize);
    _notify(value.committedImage, value.activeStroke);
  }

  void onPointerDown(
    Offset localPosition,
    DrawingTool tool,
    Color color,
    double size, {
    bool isPixelArt = false,
    double pixelCellSize = 0,
  }) {
    if (!_initialised) return;

    var rasterPoint = localToRaster(
      localPosition: localPosition,
      displaySize: _displaySize,
      rasterSize: _rasterSize,
      zoom: _view.zoom,
      pan: _view.pan,
    );

    if (isPixelArt) {
      rasterPoint = snapToGrid(rasterPoint, pixelCellSize);
    }

    if (tool == DrawingTool.fill) {
      _pendingFill = rasterPoint;
      _pendingFillColor = color;
      return;
    }

    final stroke = Stroke(
      drawingTool: tool,
      color: tool == DrawingTool.eraser ? CanvasConstants.canvasColor : color,
      size: size,
      isPixelArt: isPixelArt,
      pixelCellSize: pixelCellSize,
      points: [rasterPoint],
    );

    // Spray flushes mid-stroke, so the undo snapshot must be taken here at
    // pointer-down — before any flush — so the whole gesture stays one undo step.
    if (tool == DrawingTool.spray) {
      _pushUndo(value.committedImage);
      _sprayUndoSaved = true;
    }

    _notifyWithStroke(stroke);
  }

  Future<void> onPointerMove(Offset localPosition) async {
    if (!_initialised) return;
    final current = value.activeStroke;
    if (current == null) return;

    var rasterPoint = localToRaster(
      localPosition: localPosition,
      displaySize: _displaySize,
      rasterSize: _rasterSize,
      zoom: _view.zoom,
      pan: _view.pan,
    );

    if (current.isPixelArt) {
      rasterPoint = snapToGrid(rasterPoint, current.pixelCellSize);
    }

    if (current.isFreehand) {
      if (current.drawingTool == DrawingTool.spray) {
        await _addSprayPoints(current, rasterPoint);
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

    final fillPoint = _pendingFill;
    final fillColor = _pendingFillColor;
    if (fillPoint != null && fillColor != null) {
      _pendingFill = null;
      _pendingFillColor = null;
      _commitFill(fillPoint, fillColor);
      return;
    }

    final stroke = value.activeStroke;
    if (stroke == null) return;
    final sprayAlreadySaved = _sprayUndoSaved;
    _sprayUndoSaved = false;
    _commitStroke(stroke, skipUndoPush: sprayAlreadySaved);
  }

  /// Discards an in-progress action without committing it or touching history.
  ///
  /// Called when a one-finger gesture escalates to two-finger navigation: the
  /// stroke or pending fill finger one began must be thrown away here, because
  /// otherwise it commits on pointer-up as a stray mark — the exact failure that
  /// sank the previous zoom attempt. Clears the pending fill unconditionally,
  /// since a fill leaves no active stroke to detect.
  void cancelStroke() {
    if (!_initialised) return;
    _pendingFill = null;
    _pendingFillColor = null;
    _sprayUndoSaved = false;
    if (value.activeStroke == null) return;
    _notify(value.committedImage, null);
  }

  /// Snapshots the current zoom as the baseline for an incoming scale gesture.
  ///
  /// Called on every scale-gesture start, including single-finger draws, so the
  /// baseline is ready if the gesture later escalates to two fingers. Cumulative
  /// scale in [updateView] is multiplied against this, so a pinch resumes from
  /// wherever the last one ended instead of snapping back to 1.0.
  void beginView() {
    _viewStartZoom = _view.zoom;
  }

  /// Applies one frame of a two-finger navigation gesture.
  ///
  /// [scale] is cumulative since the gesture start; [focalPoint] and
  /// [focalDelta] are in canvas-widget-local pixels. The focal-anchored zoom
  /// and pan-clamp math lives in [ViewTransform.applyGesture] so it can be
  /// tested as pure geometry independent of the controller.
  void updateView({
    required double scale,
    required Offset focalPoint,
    required Offset focalDelta,
  }) {
    if (!_initialised) return;

    final base = fitRasterInDisplay(
      rasterSize: _rasterSize,
      displaySize: _displaySize,
    );

    _view = _view.applyGesture(
      startZoom: _viewStartZoom,
      scale: scale,
      focalPoint: focalPoint,
      panDelta: focalDelta,
      baseRect: base.destination,
      displaySize: _displaySize,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
    );
    _notify(value.committedImage, value.activeStroke);
  }

  /// Returns the viewport to 1:1, centred. Called whenever the canvas identity
  /// changes (new drawing, loaded image) so it always opens un-zoomed.
  void resetView() {
    _view = ViewTransform.identity;
    _viewStartZoom = 1.0;
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
    resetView();
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
    resetView();
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

  Future<void> _commitStroke(Stroke stroke, {bool skipUndoPush = false}) async {
    if (!skipUndoPush) _pushUndo(value.committedImage);
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

  Future<void> _addSprayPoints(Stroke current, Offset centre) async {
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

    final updated = Stroke(
      drawingTool: current.drawingTool,
      color: current.color,
      size: current.size,
      points: [...current.points, ...newPoints],
    );

    if (updated.points.length >= CanvasConstants.sprayFlushThreshold) {
      // Bake accumulated dots into the committed image and start a fresh
      // active stroke. The undo snapshot was already saved at pointer-down,
      // so this flush is invisible to the undo stack — the whole spray
      // gesture stays a single undo step.
      final flushed = await CanvasCompositor.commitStroke(
        value.committedImage,
        updated,
      );
      _notify(
        flushed,
        Stroke(
          drawingTool: updated.drawingTool,
          color: updated.color,
          size: updated.size,
          points: [],
        ),
      );
      return;
    }

    _notifyWithStroke(updated);
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
      view: _view,
      grid: _grid,
    );
  }

  void _notifyWithStroke(Stroke stroke) {
    value = CanvasState(
      committedImage: value.committedImage,
      activeStroke: stroke,
      canUndo: value.canUndo,
      canRedo: value.canRedo,
      isDirty: _dirty,
      view: _view,
      grid: _grid,
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