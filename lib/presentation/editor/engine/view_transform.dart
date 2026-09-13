import 'dart:math' as math;
import 'dart:ui';

import 'canvas_fit.dart';

/// Immutable user viewport transform: a [zoom] factor, a [pan] offset and a
/// [rotation] angle layered on top of the canvas contain-fit. [identity] is the
/// un-zoomed, un-rotated, centred view, in which the painter and coordinate
/// mapper take their pre-zoom fast path.
class ViewTransform {
  const ViewTransform({
    required this.zoom,
    required this.pan,
    this.rotation = 0.0,
  });

  static const ViewTransform identity = ViewTransform(
    zoom: 1.0,
    pan: Offset.zero,
    rotation: 0.0,
  );

  final double zoom;
  final Offset pan;

  /// View rotation in radians, about the canvas centre. Normalised to
  /// (-pi, pi] so the [rotationDetent] test stays valid after a full turn.
  final double rotation;

  bool get isIdentity =>
      zoom == 1.0 && pan == Offset.zero && rotation == 0.0;

  /// Returns the transform after one frame of a two-finger gesture.
  ///
  /// [scale] and [rotationDelta] are cumulative since the gesture start and are
  /// applied relative to [startZoom] and [startRotation], so a gesture resumes
  /// from wherever the last one ended. Zoom and rotation are anchored about
  /// [focalPoint] so the content under the fingers stays put across both
  /// changes; [panDelta] then adds the two-finger drag, and the result is
  /// clamped so the canvas can never be pushed off the viewport.
  ///
  /// Rotations within [rotationDetent] of upright snap to exactly zero. Without
  /// that, hand-rotating back to 0.0 is effectively impossible, so the upright
  /// view and the identity fast path would both become unreachable once the
  /// canvas had been turned even slightly.
  ///
  /// [baseRect] is the contain-fit destination and [displaySize] the rendered
  /// canvas size, both needed to clamp pan against the real on-screen bounds.
  ViewTransform applyGesture({
    required double startZoom,
    required double scale,
    required double startRotation,
    required double rotationDelta,
    required Offset focalPoint,
    required Offset panDelta,
    required Rect baseRect,
    required Size displaySize,
    required double minZoom,
    required double maxZoom,
    required double rotationDetent,
  }) {
    final newZoom = (startZoom * scale).clamp(minZoom, maxZoom);

    final rawRotation = _normaliseAngle(startRotation + rotationDelta);
    final newRotation = rawRotation.abs() < rotationDetent ? 0.0 : rawRotation;

    final focalFromCentre = focalPoint - baseRect.center;
    final pannedFromCentre = pan + panDelta;
    // Solve for the pan that holds the raster point under the focal point fixed
    // as the view moves from the current zoom/rotation to the new one. The
    // focal-relative vector is rotated by the rotation *delta* before the zoom
    // ratio is applied: rotating the view moves that point around the canvas
    // centre, so anchoring on the unrotated vector would slide the content out
    // from under the fingers by the angle turned.
    final anchored =
        focalFromCentre -
        _rotate(focalFromCentre - pannedFromCentre, newRotation - rotation) *
            (newZoom / zoom);

    return ViewTransform(
      zoom: newZoom,
      pan: clampViewPan(
        baseRect: baseRect,
        displaySize: displaySize,
        zoom: newZoom,
        pan: anchored,
        rotation: newRotation,
      ),
      rotation: newRotation,
    );
  }
}

Offset _rotate(Offset offset, double angle) {
  if (angle == 0.0) return offset;
  final cos = math.cos(angle);
  final sin = math.sin(angle);
  return Offset(
    offset.dx * cos - offset.dy * sin,
    offset.dx * sin + offset.dy * cos,
  );
}

/// Wraps [angle] into (-pi, pi].
///
/// Cumulative gesture rotation is unbounded — a user can keep turning past a
/// full circle — so the raw sum drifts away from the range the detent test and
/// the zero comparison in [ViewTransform.isIdentity] assume.
double _normaliseAngle(double angle) {
  const twoPi = 2 * math.pi;
  var wrapped = angle % twoPi;
  if (wrapped > math.pi) {
    wrapped -= twoPi;
  } else if (wrapped <= -math.pi) {
    wrapped += twoPi;
  }
  return wrapped;
}