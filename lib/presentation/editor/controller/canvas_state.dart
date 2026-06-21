import 'dart:ui' as ui;

import '../engine/stroke.dart';
import '../engine/view_transform.dart';

/// Immutable snapshot of the drawing canvas at a single point in time.
///
/// Published by [CanvasController] via [ValueNotifier]. Consumers rebuild
/// only when the controller emits a new instance — pointer-move events
/// produce a new state on every frame, so fields are kept small.
class CanvasState {
  const CanvasState({
    required this.committedImage,
    required this.activeStroke,
    required this.canUndo,
    required this.canRedo,
    required this.isDirty,
    this.view = ViewTransform.identity,
  });

  /// The last fully committed raster buffer. Displayed as the canvas background.
  final ui.Image committedImage;

  /// The stroke currently being drawn, or null between gestures.
  /// Rendered as a cheap vector overlay on top of [committedImage].
  final Stroke? activeStroke;

  final bool canUndo;
  final bool canRedo;

  /// True when committed pixels have changed since the last save, load, or
  /// reset. Drives the export prompt so a clean drawing exports without nagging.
  final bool isDirty;

  /// User viewport zoom/pan. Composed onto the canvas fit by
  /// `fitRasterWithView` so the painter renders the zoomed view from the same
  /// transform the coordinate mapper inverts.
  final ViewTransform view;
}