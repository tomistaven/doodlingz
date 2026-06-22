import 'dart:ui';

import 'canvas_fit.dart';

/// Immutable user viewport transform: a [zoom] factor and a [pan] offset layered
/// on top of the canvas contain-fit. [identity] is the un-zoomed, centred view,
/// in which the painter and coordinate mapper take their pre-zoom fast path.
class ViewTransform {
  const ViewTransform({required this.zoom, required this.pan});

  static const ViewTransform identity = ViewTransform(
    zoom: 1.0,
    pan: Offset.zero,
  );

  final double zoom;
  final Offset pan;

  bool get isIdentity => zoom == 1.0 && pan == Offset.zero;

  /// Returns the transform after one frame of a two-finger gesture.
  ///
  /// [scale] is cumulative since the gesture start and is applied relative to
  /// [startZoom], so a pinch resumes from wherever the last one ended. The new
  /// zoom is anchored about [focalPoint] so the content under the fingers stays
  /// put across the zoom change; [panDelta] then adds the two-finger drag, and
  /// the result is clamped so the canvas can never be pushed off the viewport.
  ///
  /// [baseRect] is the contain-fit destination and [displaySize] the rendered
  /// canvas size, both needed to clamp pan against the real on-screen bounds.
  ViewTransform applyGesture({
    required double startZoom,
    required double scale,
    required Offset focalPoint,
    required Offset panDelta,
    required Rect baseRect,
    required Size displaySize,
    required double minZoom,
    required double maxZoom,
  }) {
    final newZoom = (startZoom * scale).clamp(minZoom, maxZoom);

    final focalFromCentre = focalPoint - baseRect.center;
    final pannedFromCentre = pan + panDelta;
    // Solve for the pan that holds the raster point under the focal point fixed
    // as the zoom moves from the current value to newZoom.
    final anchored =
        focalFromCentre -
        (focalFromCentre - pannedFromCentre) * (newZoom / zoom);

    return ViewTransform(
      zoom: newZoom,
      pan: clampViewPan(
        baseRect: baseRect,
        displaySize: displaySize,
        zoom: newZoom,
        pan: anchored,
      ),
    );
  }
}
