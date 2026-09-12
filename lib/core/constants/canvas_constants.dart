import 'dart:math' as math;
import 'dart:ui' show Color, Size;

/// Fixed configuration for the drawing canvas and its tools.
///
/// All tool dimensions are expressed in *raster* pixels — the fixed pixel
/// buffer the drawing is composited into — not logical screen pixels. This
/// keeps brush, shape, and spray sizes consistent across devices while the
/// display layer scales the buffer to fit the available space.
abstract final class CanvasConstants {
  // Default 3:4 budget for blank canvases. A fresh drawing is always portrait
  // or its landscape transpose, both the same pixel count.
  static const int rasterShortSide = 810;
  static const int rasterLongSide = 1080;

  static final Size portraitCanvasSize = Size(
    rasterShortSide.toDouble(),
    rasterLongSide.toDouble(),
  );
  static final Size landscapeCanvasSize = Size(
    rasterLongSide.toDouble(),
    rasterShortSide.toDouble(),
  );

  // Imported images keep their own aspect ratio rather than being cropped to
  // the 3:4 presets, so the raster can be any shape. What stays bounded is the
  // total pixel area: an import is scaled to fit within this budget, which is
  // what actually caps flood-fill cost and per-snapshot memory (~3.5 MB here).
  static const int rasterPixelBudget = rasterShortSide * rasterLongSide;

  // The canvas substrate is white by default and is never themed; the eraser
  // restores affected pixels to exactly this color.
  static const Color canvasColor = Color(0xFFFFFFFF);
  static const Color defaultToolColor = Color(0xFF000000);

  static const List<double> brushSizes = [4.0, 10.0, 20.0];
  static const List<double> shapeOutlineWidths = [3.0, 6.0, 12.0];
  static const List<double> spraySizes = [20.0, 40.0, 60.0];

  // Grid cell size options shown in the hub's Grid sub-menu, in raster pixels.
  static const List<double> gridCellSizes = [8.0, 16.0, 32.0];

  // Shared by EditorState's initial value and GridSettings.disabled, so the
  // default grid spacing is defined once rather than duplicated across the
  // cubit and engine layers.
  static const double defaultGridCellSize = 16.0;

  // Dots scattered per spray tick; higher values give denser coverage per pass.
  static const int sprayDensity = 30;

  // Flush accumulated spray points into the committed raster after this many
  // points accumulate on the active stroke. Keeps the painter's per-frame
  // drawCircle count bounded so long spray sessions don't accumulate lag.
  // 150 = 5 ticks ≈ ~0.4 s at typical gesture rates before the first flush.
  static const int sprayFlushThreshold = 150;

  // Undo depth. The task requires 5; the headroom is capped to bound total
  // snapshot memory (~3.5 MB per stored canvas state at this resolution).
  static const int maxHistorySteps = 20;

  // Per-channel tolerance when matching the target color during flood fill, so
  // anti-aliased edges don't leave an unfilled halo. Raise if halos appear,
  // lower if fills bleed past boundaries.
  static const int fillColorTolerance = 32;

  // The letterbox margin shown around a bounded canvas. Lighter than the
  // scaffold so the dark drawable area reads as distinct from the surround.
  static const Color canvasMarginColor = Color(0xFF333333);

  // Thin border drawn around the canvas rect so the drawable area stands out
  // from the margin like a sheet on a desk, for both blank and imported canvases.
  static const Color canvasBorderColor = Color(0x33FFFFFF);
  static const double canvasBorderWidth = 1.0;

  /// A budget-bounded raster matching [area]'s aspect ratio.
  ///
  /// A fresh canvas fills the editor area rather than using the fixed 3:4
  /// preset, so it does not letterbox on tall screens. The shape follows the
  /// device's editor area while the total pixel count stays under
  /// [rasterPixelBudget], which is what keeps flood-fill cost and snapshot
  /// memory bounded. Falls back to the portrait preset for a degenerate area.
  static Size rasterSizeForArea(Size area) {
    if (area.width <= 0 || area.height <= 0) {
      return portraitCanvasSize;
    }
    final aspect = area.width / area.height;
    // width * height = budget, width / height = aspect  ->  solve for each.
    final height = math.sqrt(rasterPixelBudget / aspect);
    final width = height * aspect;
    return Size(width.roundToDouble(), height.roundToDouble());
  }

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