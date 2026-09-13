import 'package:flutter/material.dart';

/// UI layout, animation, and styling constants for widgets outside the canvas.
///
/// Canvas and tool dimensions belong in [CanvasConstants]. These constants
/// cover the editor hub and shared chrome surfaces. The onboarding overlay is
/// deliberately excluded: its spacing is orientation-dependent, which a flat
/// constant list cannot express, so it owns its own layout values.
abstract final class UiConstants {
  // Hub geometry

  /// Diameter of the main hub handle button.
  static const double hubHandleSize = 64;

  /// Diameter of each arc node button.
  static const double hubNodeSize = 44;

  /// Distance from the screen edge (and safe-area inset) to the hub handle.
  static const double hubEdgeMargin = 24;

  /// Radius of the inner arc row when two rows are shown.
  static const double hubArcRadiusInner = 105;

  /// Radius of the single arc row when only one row is shown.
  static const double hubArcRadiusSingle = 115;

  /// Single-row radius used only at exactly 5 nodes. [hubArcRadiusSingle]
  /// (115) was sized for up to 4 nodes; at 5 nodes across the same 80° sweep
  /// the chord between adjacent nodes shrinks below their own diameter,
  /// causing visible overlap. Derived (not guessed) to match the same
  /// adjacent-node clearance the proven 4-node case already has: solving
  /// chord(r, 5 nodes, 80°) == chord(115, 4 nodes, 80°) gives r ≈ 152.7.
  static const double hubArcRadiusFive = 153;

  /// Radius of the outer arc row when two rows are shown.
  static const double hubArcRadiusOuter = 190;

  /// Corner radius for hub nodes when pixel art mode is active. Deliberately
  /// tight — square nodes should read as blocky/pixel-art, with just enough
  /// softening to avoid a harsh 0px edge clashing with the rest of the app's
  /// rounded chrome.
  static const double hubPixelArtNodeRadius = 3;

  /// Multiplier applied to every hub arc radius when pixel art mode is
  /// active. Nodes are placed at a fixed angular step, so two adjacent nodes'
  /// center-to-center distance is a chord that shrinks with the sine of half
  /// that angle — fine for circles, whose silhouette also shrinks away from
  /// the chord direction, but not for squares, whose flat corners stay at
  /// full extent right up to the chord line. sqrt(2) is the ratio between a
  /// square's side and its diagonal — scaling the radius (and so the chord)
  /// by that factor gives squares the same non-overlap guarantee circles
  /// already had at the unscaled radius.
  static const double hubPixelArtRadiusScale = 1.41;

  // Hub animation

  /// Duration of the hub open/close arc animation.
  static const Duration hubArcDuration = Duration(milliseconds: 280);

  /// Duration of the handle icon opacity fade.
  static const Duration hubHandleFadeDuration = Duration(milliseconds: 150);

  //  Hub colours
  /// Background colour for hub nodes and the handle interior. Dark chrome,
  /// matches the app surface colour but hardcoded so it never themes to white.
  static const Color hubSurface = Color(0xFF242424);

  /// Outer ring on the hub handle. The handle interior is dark, so on the dark
  /// editor margin around a bounded canvas it would otherwise vanish; this
  /// translucent-white ring keeps an edge visible against both the white canvas
  /// and the dark surround.
  static const Color hubHandleRing = Color(0x66FFFFFF);

  /// Width of the hub handle contrast ring.
  static const double hubHandleRingWidth = 2.0;

  /// Scrim opacity behind open hub arc nodes.
  static const double hubScrimOpacity = 0.08;

  /// Icon opacity for hub node icons.
  static const double hubIconOpacity = 0.9;

  /// Border opacity for the colour category node.
  static const double hubColorNodeBorderOpacity = 0.85;

  // Splash

  /// Total time the splash screen is shown before navigating to [AppShell].
  static const Duration splashDuration = Duration(milliseconds: 1400);

  /// Width and height of the splash icon mark.
  static const double splashIconSize = 96;
}