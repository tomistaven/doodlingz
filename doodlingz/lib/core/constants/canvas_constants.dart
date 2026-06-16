import 'dart:ui' show Color, Size;

/// Fixed configuration for the drawing canvas and its tools.
///
/// All tool dimensions are expressed in *raster* pixels — the fixed pixel
/// buffer the drawing is composited into — not logical screen pixels. This
/// keeps brush, shape, and spray sizes consistent across devices while the
/// display layer scales the buffer to fit the available space.
abstract final class CanvasConstants {
  // Fixed 3:4 pixel budget. Portrait and landscape are transposes of the same
  // pixel count, so flood-fill cost and snapshot memory stay constant
  // regardless of the orientation a drawing is created in.
  static const int rasterShortSide = 810;
  static const int rasterLongSide = 1080;

  static final Size portraitCanvasSize =
      Size(rasterShortSide.toDouble(), rasterLongSide.toDouble());
  static final Size landscapeCanvasSize =
      Size(rasterLongSide.toDouble(), rasterShortSide.toDouble());

  // The canvas substrate is white by default and is never themed; the eraser
  // restores affected pixels to exactly this color.
  static const Color canvasColor = Color(0xFFFFFFFF);
  static const Color defaultToolColor = Color(0xFF000000);

  static const List<double> brushSizes = [4.0, 10.0, 20.0];
  static const List<double> shapeOutlineWidths = [3.0, 6.0, 12.0];
  static const List<double> spraySizes = [20.0, 40.0];

  // Dots scattered per spray tick; higher values give denser coverage per pass.
  static const int sprayDensity = 30;

  // Undo depth. The task requires 5; the headroom is capped to bound total
  // snapshot memory (~3.5 MB per stored canvas state at this resolution).
  static const int maxHistorySteps = 20;

  // Per-channel tolerance when matching the target color during flood fill, so
  // anti-aliased edges don't leave an unfilled halo. Raise if halos appear,
  // lower if fills bleed past boundaries.
  static const int fillColorTolerance = 32;

  // Quick-access palette shown in the radial swatch menu. Kept here rather than
  // in the widget so the palette can be tuned without touching presentation
  // code.
  static const List<Color> presetColors = [
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
  ];
}