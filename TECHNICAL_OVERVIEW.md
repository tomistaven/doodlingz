# Doodlingz — Technical Overview

This document covers the architecture, the raster pipeline, the view transform, each drawing tool, the grid and pixel art mode, the flood-fill algorithm, undo/redo, the editor load path, and the persistence layer. The README covers features and setup; this covers the code.

---

## Table of Contents

- [Architecture](#architecture)
- [The Raster Pipeline](#the-raster-pipeline)
- [The View Transform and Coordinate Mapping](#the-view-transform-and-coordinate-mapping)
- [Drawing Tools](#drawing-tools)
- [Grid and Pixel Art Mode](#grid-and-pixel-art-mode)
- [Mirror Mode](#mirror-mode)
- [Flood Fill](#flood-fill)
- [Undo and Redo](#undo-and-redo)
- [Editor Load Path and State Management](#editor-load-path-and-state-management)
- [Persistence and Gallery](#persistence-and-gallery)
- [Dependency Injection](#dependency-injection)
- [Key Constants](#key-constants)
- [Back to README.md](README.md)

---

## Architecture

The project uses Flutter Clean Architecture with three layers plus a shared core.

**Domain layer** (`lib/domain/`) defines the `SavedDrawing` entity, the `DrawingTool` enum, and the abstract `DrawingRepository` interface. No Flutter imports, no external packages — pure Dart. If the storage mechanism or UI framework changes, the domain is unaffected.

**Data layer** (`lib/data/`) implements `DrawingRepository` via `DrawingRepositoryImpl`, which delegates to `LocalDrawingDataSource` for all file I/O. `SavedDrawingModel` maps between filesystem metadata and the domain entity. The data layer knows about `path_provider` and `dart:io`, but not about Flutter widgets.

**Presentation layer** (`lib/presentation/`) contains the editor, gallery, settings, and shell. It holds the Cubits, the screens, the custom painter, and the raster engine. Screens talk to Cubits and to the canvas controller — never directly to the repository.

**Core** (`lib/core/`) holds the theme and the constants. `CanvasConstants` is the single source of truth for raster dimensions, tool sizes, spray density, fill tolerance, and undo depth; `AppConstants` owns storage paths and the filename format.

A note on layer placement: the raster engine (`canvas_compositor.dart`, `flood_fill.dart`, `coordinate_mapper.dart`, `canvas_fit.dart`, `view_transform.dart`, `stroke.dart`, `stroke_renderer.dart`, `grid_renderer.dart`, `grid_snap.dart`) lives under `presentation/editor/engine/` rather than in core. It is `dart:ui` rendering code tied to the editor screen, not app-wide configuration, so it sits with the feature that owns it.

### Typography

`AppTheme` builds its base `TextTheme` from `GoogleFonts.mansalvaTextTheme()`, then rebuilds every named slot with an explicit `copyWith(fontSize: ...)` to apply a uniform `+2` size increase, rather than calling `TextTheme.apply(fontSizeDelta: 2)` on the whole theme. `TextStyle.apply()` asserts at runtime if a style's `fontSize` is null while a nonzero `fontSizeFactor` or `fontSizeDelta` is supplied — `flutter analyze` cannot catch this, since the assertion only fires when that specific `TextStyle` is actually built and rendered. The per-slot `copyWith`, with a Material-default fallback (`?? 14`, etc.) for any slot that comes through null, guarantees every slot carries a concrete `fontSize` so the assertion path is structurally unreachable.

`AppBarThemeData.titleTextStyle` is set separately to `GoogleFonts.lacquer()`, so every app-bar title (`Doodlingz`, `Settings`, the gallery title) picks up the wordmark font from one place without per-screen styling.

---

## The Raster Pipeline

The canvas is a single immutable `ui.Image` — the **committed image** — plus at most one **active stroke** layered on top while a gesture is in progress.

### Committed image versus active stroke

Rasterising on every pointer-move event would be far too expensive. Instead:

- While the finger is down, the in-progress stroke is held as a lightweight `Stroke` (a tool, a color, a size, and a growing list of points) and painted as a **vector overlay** on top of the committed image each frame.
- On pointer-up, the stroke is composited **once** into a new committed `ui.Image`, and the overlay is cleared.

`DrawingCanvasPainter` does exactly this: it draws the committed image first, then — if an active stroke exists — paints it as vectors above, then its mirror stroke if mirror mode is on, and finally the grid overlay if it is visible. The preview paint logic and the commit paint logic are deliberately kept identical per tool (same path construction, same blend modes, same spray dots) so what the user sees during the gesture is exactly what gets baked in.

All of the above are drawn inside a **single** transform block, in raster coordinates, applied once via `CanvasFit.applyTo()`. Each layer previously derived that transform for itself, which is the duplication that produced the spray and stroke-join bugs described under Drawing Tools; computing it once removes the opportunity to drift.

The grid is drawn **last** within that block, above the active stroke and its mirror. It already sits above every committed pixel, so painting it beneath the in-progress overlay meant a live stroke covered grid lines until the frame it committed — most visible with the eraser, whose opaque white fill blanked them outright mid-drag. Drawing it last makes the live preview match the committed result for every tool.

One further layer sits **outside** that transform block entirely: the mirror axis guide line, drawn after `canvas.restore()` in plain display coordinates whenever `mirrorGuideVisible` is set. This is the one deliberate exception to "single transform block, computed once" — see Mirror Mode below for why the guide specifically must not rotate, pan, or zoom with the canvas the way every other layer does.

### CanvasController and ValueNotifier

`CanvasController` (`controller/canvas_controller.dart`) extends `ValueNotifier<CanvasState>` rather than being a BLoC. Pointer-move events fire at the display refresh rate; routing each one through a BLoC would emit a new state object and run comparison logic every frame, flooding the platform channel. `ValueNotifier` is the Flutter primitive built for exactly this high-frequency case, and a `ValueListenableBuilder` rebuilds only the canvas widget. BLoC is still used everywhere else (tool selection, gallery, settings).

The controller is **owned and created directly by `EditorScreen`**, not registered in `get_it`. Its lifetime is tied to the screen, which avoids the stale-singleton trap where a `get_it` instance survives a screen dispose and comes back holding old pixels.

### CanvasState

`CanvasState` is the immutable snapshot the controller publishes:

```dart
final ui.Image    committedImage;   // last fully baked raster
final Stroke?     activeStroke;      // in-progress vector overlay, or null
final Stroke?     mirrorStroke;      // activeStroke's reflection, or null
final bool        canUndo;
final bool        canRedo;
final bool        isDirty;           // pixels changed since last save/load/reset
final ViewTransform view;            // user zoom/pan/rotation; identity = plain contain-fit
final GridSettings  grid;            // overlay visibility and cell size
final bool        mirrorGuideVisible; // standing render flag for the mirror axis line
```

Because a pointer-move produces a new state every frame, the fields are kept minimal — the heavy `ui.Image` is passed by reference, not copied.

### Budget-bounded raster buffer

All drawing happens against a pixel buffer, not the on-screen widget size. The buffer's *shape* is not fixed, but its *area* is: it always stays within a pixel budget of **810 × 1080 = 874,800 pixels** (`rasterPixelBudget`). What occupies that budget depends on how the canvas was created:

- A **blank new drawing** is shaped to the editor area's aspect ratio (`rasterSizeForArea`), so it fills the screen without letterboxing. On a tall phone that is roughly 683 × 1280; the 3:4 presets (`portraitCanvasSize` / `landscapeCanvasSize`) remain as the pre-layout default and fallback.
- An **imported image** keeps its own aspect ratio, scaled down only until its area is under budget (`CanvasCompositor.fromBytes`). A wide panorama becomes a wide buffer; a tall photo becomes a tall one.

Bounding the *area* rather than the *dimensions* is what actually keeps flood-fill cost and per-snapshot memory constant — those scale with pixel count, not shape. Tool sizes are still expressed in *raster* pixels, so a 10px brush is a consistent fraction of the buffer. The display layer scales the buffer to fit the available space with a single uniform scale (never separate per-axis scales, which would distort), and the committed image is drawn with `FilterQuality.high` to smooth that scale.

---

## The View Transform and Coordinate Mapping

Because the buffer and the display area can have different aspect ratios, the canvas is fitted into its display area with a single uniform scale and centred — the `BoxFit.contain` model. A single helper, `fitRasterInDisplay()` (`engine/canvas_fit.dart`), computes that base fit and is the **one** source of truth shared by the painter and the coordinate mapper.

### ViewTransform

`ViewTransform` (`engine/view_transform.dart`) is the user's viewport state: a zoom factor, a pan offset, and a rotation angle. `fitRasterWithView()` composes it onto the base fit, returning the same `CanvasFit` both the painter and the mapper consume — so the rendered image and the touch mapping are always driven by one transform and cannot diverge. At identity (zoom 1, no pan, no rotation) it returns the untouched base fit, so the common case carries no overhead.

`ViewTransform.applyGesture()` folds one frame of a two-finger gesture into a new transform. Both `scale` and `rotation` arrive from `ScaleUpdateDetails` cumulative since the gesture began, and compose against a baseline snapshotted at gesture start (`_viewStartZoom` / `_viewStartRotation`), so a second pinch or twist resumes from wherever the last one ended rather than snapping back.

The focal anchor keeps the content under the fingers fixed across the change. The focal-relative vector is rotated by the rotation **delta** before the zoom ratio is applied — rotating the view moves that point around the canvas centre, so anchoring on the unrotated vector would slide the drawing out from under the fingers by exactly the angle turned.

Rotation is normalised into (-pi, pi] and snapped to exactly zero within `_rotationDetent` (4°). Two fingers cannot reliably land on 0.0, so without the detent an upright canvas would be unreachable once turned, and the identity fast path would never re-engage. Normalisation matters for the same reason: cumulative gesture rotation is unbounded, so a user who turns a full circle back to upright would otherwise sit at 6.28 rad with the detent never firing.

### Pan clamping under rotation

`clampViewPan()` limits pan to how far the canvas overflows the display, so it can never be dragged fully off-screen; at zoom 1 the overflow is zero on both axes, which pins the view exactly to the contain-fit position.

Rotation widens those extents. A rotated rectangle covers an axis-aligned span of `w·|cos| + h·|sin|`, substantially larger than its unrotated width at intermediate angles, so clamping against the unrotated extent would lock pan while the canvas was still visibly overflowing. The clamp uses the rotated axis-aligned bounding box rather than the exact hull, which is marginally conservative near the corners — it can only ever restrict slightly early, never allow the canvas to escape.

### Mapping touches back to pixels

`CanvasFit` exposes the transform as three methods rather than leaving callers to rebuild it from `destination` and `scale`:

- `applyTo(Canvas)` — concatenates the raster-to-display transform, so the painter draws in buffer coordinates
- `toRaster(Offset)` — the exact inverse, used by `localToRaster()` (`engine/coordinate_mapper.dart`)
- `toDisplay(Offset)` — the exact inverse of `toRaster`, mapping a raster point back to display coordinates. Added for mirror mode (see Mirror Mode below), which needs to reason about a point's position in screen space regardless of the canvas's current rotation — something `toRaster` alone cannot do, since it only goes the other direction. Verified as an exact algebraic inverse by round-trip composition (`toRaster(toDisplay(p)) == p`) rather than by inspection alone, since a rotation-composition error here would be silent until someone rotated and mirrored at the same time.

This matters once rotation exists: the destination rectangle alone no longer describes where the canvas is drawn, so any caller doing its own subtract-and-divide would silently ignore the angle.

`localToRaster()` inverts the composed fit and then clamps:

```dart
fit    = fitRasterWithView(rasterSize, displaySize, zoom, pan, rotation)
raster = fit.toRaster(localPosition)   // un-rotate about the fit centre, then un-scale
rx     = raster.dx.clamp(0, rasterSize.width  - 1)
ry     = raster.dy.clamp(0, rasterSize.height - 1)
```

The clamp is applied **after** the full inverse, never fused into it per-axis. Under rotation the two axes are mixed — a point off the left edge of the screen can map out of bounds in *y* — so clamping a coordinate mid-inverse would fold the touch onto the wrong edge. Clamping at all guarantees every returned coordinate is a valid index into the raw byte buffer, which also folds a touch in the letterbox margin onto the nearest edge pixel.

The painter clips to the canvas widget bounds at the top of `paint()`, **before** the fit transform is applied, so the clip stays in display space; clipping inside the transform block would rotate the clip region along with the content and let pixels spill past the widget edge.

---

## Drawing Tools

Every tool ends up as a `Stroke` that is committed by `CanvasCompositor`. The compositor draws the existing committed image into a fresh `PictureRecorder`, draws the new stroke on top, and returns a new `ui.Image` — the input image is never mutated, which keeps the undo stack's snapshots clean.

### Single rendering source of truth

All per-tool rendering logic — paint building, path construction, spray dot scatter, shape drawing — lives in `engine/stroke_renderer.dart`. Both the live preview (`DrawingCanvasPainter`) and the raster commit (`CanvasCompositor`) call the same functions from this file. Previously the logic was duplicated: the spray tool was a real-world example of the failure mode — spray committed as a solid connected line while previewing correctly as scattered dots, because the preview was fixed without updating the commit path. Shape corners previewed rounded but committed mitered for the same reason (the compositor's independent `Paint` never set `StrokeJoin`). Routing both paths through one file makes that class of drift structurally impossible.

### Brush

A standard stroked path: `StrokeCap.round`, `StrokeJoin.round`, width = the selected size. Points are accumulated on pointer-move and joined with `lineTo`. The live preview additionally renders a lone point as a filled dot of radius `size / 2`, so a tap shows up immediately while the finger is down.

### Highlighter

Same path construction as the brush, but with `BlendMode.multiply` and the color forced to 0.4 alpha. Multiply darkens what is underneath rather than replacing it, so overlapping highlighter strokes deepen and the white substrate tints instead of being painted over — the translucent-marker look.

### Eraser

The eraser is **not** transparency. On pointer-down its stroke color is forced to `CanvasConstants.canvasColor` (opaque white) and it then commits exactly like a brush stroke.

This is deliberate. The eraser is meant to restore the affected area to the canvas's default color, and the whole app assumes opaque canvases — gallery thumbnails and the re-open-for-edit flow both expect a solid background. An earlier attempt using `BlendMode.clear` with `saveLayer` sandboxing was reverted: it would have punched real holes in the buffer and produced transparent PNG exports, breaking that assumption. Painting white is the correct model here.

Because the eraser's color is fixed, the hub's color node is suppressed when the eraser is active (`_showsColor()` in `editor_hub.dart`) — showing a color picker for a tool that ignores it would confuse the user.

### Spray

This is the tool that most often trips people up on this task, because the obvious implementation — drawing one big translucent circle that scales with the tool size — looks like a blurry stamp, not an airbrush. Doodlingz scatters individual dots instead, with two details doing the work:

**The tool "size" is the scatter radius, not the dot size.** The three spray sizes (20, 40 and 60) set how wide the cloud of dots spreads from the finger. The dots themselves are always a fine fixed 1.2px radius. So a bigger spray covers a wider area with the same fine grain, exactly like opening up an airbrush nozzle.

**The distribution is center-weighted by multiplying two random values.** On each pointer-move tick, `_addSprayPoints` scatters `sprayDensity` (30) dots:

```dart
final angle    = random.nextDouble() * 2 * pi;
final distance = (random.nextDouble() * random.nextDouble()) * radius;
final dx = centre.dx + cos(angle) * distance;
final dy = centre.dy + sin(angle) * distance;
```

A single uniform random would spread dots evenly across the disc, which reads as a flat ring with a hollow centre (area grows with radius, so a uniform radius oversamples the edge). Multiplying *two* uniform randoms biases `distance` toward 0, packing more dots near the centre and thinning them toward the edge — the soft falloff a real airbrush has. Each dot is drawn at 0.4× alpha, so overlapping dots build opacity naturally and a slow or repeated pass darkens the area, matching how holding an airbrush in place deposits more paint.

The randomness is generated **once**, in the controller, and appended to the stroke's point list. Both the live preview and the final commit render that same accumulated list, so the spray never re-rolls and "jumps" when the finger lifts. All points are clamped to the raster bounds.

### Shapes (line, rectangle, ellipse, triangle)

Shapes are two-point strokes: the pointer-down position and the current pointer position. Only those two points are kept — a move replaces the second point rather than appending — so dragging rubber-bands the shape live. The two points form a `Rect.fromPoints(start, end)`, and each shape is drawn from that rect:

- **line** → `drawLine(start, end)`
- **rectangle** → `drawRect(rect)` (a square falls out when width ≈ height)
- **ellipse** → `drawOval(rect)` (a circle falls out of a square rect)
- **triangle** → a `Path` from the rect's top-centre to its two bottom corners

All four are stroked outlines with a selectable width, drawn with `StrokeJoin.round` so corners match the rounded look of the brush and highlighter.

---

## Grid and Pixel Art Mode

### The grid overlay

`GridSettings` (`engine/grid_renderer.dart`) carries the overlay's visibility and cell size, and `paintGrid()` draws the lines. The cell size is expressed in **raster** pixels, not display pixels, and the lines are drawn inside the same raster-space transform block as the stroke overlay. That is what makes the grid scale, pan and rotate with the canvas automatically — a display-pixel cell size would need separate correction math at every zoom level, and could not follow a rotation at all.

Lines are drawn at `strokeWidth = 0`, which Dart's canvas renders as a hairline: one device pixel regardless of the transform, so the grid stays crisp at any zoom instead of thickening with it.

Grid state reaches the controller as standing state, synced from `EditorState` by `EditorScreen` via a `BlocListener`, mirroring the existing tool/colour/size flow rather than the cubit touching the controller directly. It is threaded through both `_notify` and `_notifyWithStroke` — omitting it from either would reset the grid to disabled on the next pointer-move frame, since `_notifyWithStroke` fires every drag.

### Snapping

`snapToGrid()` (`engine/grid_snap.dart`) maps a raster point to the **centre of the cell containing it** — floor to the cell, then offset by half a cell. Rounding to the nearest grid line intersection is the wrong operation and was the first implementation: an intersection is a corner shared by four cells, so a square stamped there straddles all four rather than filling any one of them. Flooring lands on the point a same-size square needs in order to fill exactly one visible grid square.

The function is deliberately independent of grid rendering, so a caller can snap against a grid that is not even visible.

### Pixel art mode

Pixel art mode is a cohesive package rather than three independent toggles. `EditorCubit.setPixelArtMode(true)` force-selects the brush and force-shows the grid in the same emit; turning it off leaves grid visibility as the user last set it rather than force-hiding it.

`Stroke` carries `isPixelArt` and `pixelCellSize`, and `stroke_renderer.dart` branches on them to stamp a filled square of one cell at each point instead of joining points into a path. Because that branch lives in the shared renderer, the live preview and the raster commit pick it up from one edit — the structural fix that makes preview/commit divergence impossible.

The eraser needed no special-casing: its colour is already forced to the canvas colour upstream, so it stamps squares through the same path as the brush.

Two restrictions follow from the stamp mechanic, both expressed by hiding controls rather than disabling them — the same pattern the hub already used to hide the size node for fill and the colour node for the eraser:

- **Tools** are restricted to brush and eraser. Spray, fill and the shapes have no defined behaviour under grid-snapped square stamping.
- **Stroke size** is hidden from the hub root, since brush footprint is governed by the grid cell size instead.

Hub nodes also switch from circles to tight-cornered squares throughout the entire hub while the mode is active, including the handle and colour swatches, as a deliberate universal switch. That change carries a geometry consequence: nodes sit at a fixed angular step, so adjacent centres are a chord that shrinks with the sine of half that angle. Circles tolerate this because their silhouette also shrinks away from the chord direction; squares do not, since their corners stay at full extent right up to the chord line. `hubPixelArtRadiusScale` (sqrt 2, the side-to-diagonal ratio) scales every arc radius while the mode is on, giving squares the same non-overlap guarantee circles already had.

---

## Mirror Mode

### Reflecting in display space, not raster space

The obvious implementation reflects a raster point about the raster buffer's own centre: `Offset(rasterSize.width - p.dx, rasterSize.height - p.dy)`. This is correct point symmetry, but it silently breaks the moment the canvas can be rotated — the fold axis is defined in raster coordinates, so it rotates along with the buffer, and the same on-screen gesture mirrors to a different physical location depending on the canvas's current angle. This was tried first and rejected on-device: a stroke drawn "on the left" landed "on the right" only at zero rotation.

`CanvasController._reflect()` instead converts the raster point to display coordinates with `CanvasFit.toDisplay()`, mirrors it about the fixed horizontal centre of the canvas widget (`_displaySize.width / 2` — set once at layout, untouched by `_view.zoom`/`_view.pan`/`_view.rotation`), then converts the mirrored point back to raster coordinates with `CanvasFit.toRaster()`. Because the fold axis is defined in screen space and the conversion never reads the current rotation for the axis itself, the fold line stays visually fixed on screen through any zoom, pan, or rotation — a stroke on the physical left of the phone always mirrors to the physical right, regardless of how the canvas underneath it is turned. At rotation 0, `toDisplay`/`toRaster` short-circuit their rotation branch, so this reduces exactly to the naive raster-space formula in the common unrotated case.

A gesture and a view-rotation change can never overlap: the two-finger navigation handling in `CanvasController` cancels any in-progress stroke the moment a second finger is detected, so a stroke and a rotation gesture are mutually exclusive by construction. `_view` is therefore guaranteed stable for the full lifetime of any single stroke `_reflect()` is called against — no mid-stroke race between a rotation gesture and a mirror reflection is possible.

### Mirror stroke lifecycle

`CanvasState.mirrorStroke` shadows `activeStroke` through the same pointer lifecycle, built and cleared in lockstep by `CanvasController`:

- **`onPointerDown`** — if mirror mode is active and the tool isn't fill, a second `Stroke` is built from the reflected first point and stored as `mirrorStroke` alongside the primary.
- **`onPointerMove`** — each new point is reflected and appended to `mirrorStroke` the same frame the primary stroke's point is appended, for both freehand and shape (two-point) strokes.
- **Spray** — `_addSprayPoints` reflects each of that tick's newly-scattered points individually and appends them to the mirror stroke's own point list, rather than generating a second independent random cloud. This keeps the two clouds genuinely mirror-symmetric rather than merely similarly shaped. When the primary stroke's point count crosses `sprayFlushThreshold` and flushes to the raster, the mirror stroke flushes in the same pass, so the two never fall out of lockstep across a flush boundary.
- **`onPointerUp`** — the primary stroke commits first (pushing an undo snapshot, unless spray already pushed one for this gesture), then the mirror stroke commits with `skipUndoPush: true` unconditionally. Two strokes land on the raster from one gesture, but only one undo step is recorded.
- **`cancelStroke`** — clears `mirrorStroke` unconditionally alongside the existing unconditional clears (`_pendingFill`, `_sprayUndoSaved`), the same two-finger-navigation safety net every other stroke type already relies on.

### Fill is excluded structurally, not by a special case

Fill commits on `onPointerDown` rather than building an `activeStroke` — see the existing pointer-down fill branch, which returns before any stroke object exists. Mirror-stroke construction happens after that branch, so fill never reaches it; there is no `if (tool != fill)` guard anywhere in the mirror logic, because the control flow already makes fill's exclusion unconditional.

### The mirror axis guide

`DrawingCanvasPainter._paintMirrorGuide()` draws a single vertical line at `size.width / 2` in plain display coordinates, called after `canvas.restore()` — deliberately outside the raster transform block every other layer shares (see Committed Image versus Active Stroke above). Drawing it inside that block, like every other layer, would rotate the guide along with the canvas and defeat its purpose: the whole point is that the fold axis the guide represents does not rotate, so the guide itself cannot either.

The guide renders whenever `CanvasState.mirrorGuideVisible` is true — a standing flag distinct from `mirrorStroke`, which only exists during an active gesture and says nothing about whether mirror mode is merely turned on with nothing currently being drawn. `mirrorGuideVisible` is synced from `EditorState.mirrorMode` into the controller by a `BlocListener` in `EditorScreen`, mirroring the existing grid-visibility sync (`setGridVisible`) rather than the read-at-draw-time pattern `pixelArtMode` uses — the guide line needs to render even with no stroke active, which a purely gesture-scoped flag cannot express.

The guide is drawn in `Colors.black` at low alpha rather than white: the canvas substrate (`CanvasConstants.canvasColor`) is opaque white, so a light guide colour would be nearly invisible against the paper it is meant to be seen over.

### Hub integration

Pixel Art and Mirror are both direct-tap toggles at the hub root — tapping either calls its cubit setter and closes the hub immediately, with no sub-level to drill into (unlike Tools, Color, Size, and Grid, which each expand). This surfaced a latent close-animation race specific to `togglePixelArtMode`: because `EditorCubit.setPixelArtMode(true)` also forces `tool: DrawingTool.brush` and `gridVisible: true` in the same emit, and root's node set depends on the active tool (`_showsColor`/`_sizesFor`), firing that emit before the hub's collapse animation finished rebuilt the still-visible arc with a different node count mid-collapse — visible as a flash/fan-out. `EditorHub._closeHubThen()` fixes this by awaiting the reverse animation's own `Future` before running the toggle's side effects, so the mutation lands only once nothing is animating. Both Pixel Art and Mirror route through this helper for consistency, though Mirror's own toggle (`setMirrorMode`) has no such side effect today.

Root grew from five category nodes to six with Mirror's addition, which pushed the arc layout past the node-count thresholds tuned for the previous five. See the `hubArcRadiusFive`/`hubArcRadiusSixInner`/`hubArcRadiusSixOuter` entries under Key Constants below for how the arc's per-count radius is chosen, and why 6 nodes uses a dedicated asymmetric 2-inner/4-outer split rather than either the single-row or the general two-row formula.

---

## Flood Fill

`floodFill()` (`engine/flood_fill.dart`) is an iterative 4-connected fill over the raw RGBA byte buffer, run on a background isolate via `compute` so a large fill never janks the UI. It is written as a top-level function with a plain-Dart `FloodFillParams` bundle precisely so it can cross the isolate boundary cleanly.

### The anti-aliasing problem

A fill is easy in the interior and hard at the edge. Stroke edges are anti-aliased — a ring of pixels blended between the region color and the stroke color. A hard per-channel tolerance cutoff cannot win:

- **Tolerance too low** → the fill stops short of the AA ring, leaving a visible unfilled halo around every shape.
- **Tolerance too high** → the fill bleeds through the AA ring and eats into the stroke.

Raising the tolerance does not fix this, because the distance from the region color at the 50%-blend point scales with the stroke's saturation — there is no single tolerance value that is correct for every stroke color.

### Two rejected approaches

- **Just raise the tolerance.** Fails for the saturation reason above.
- **Fixed-radius spatial dilation** (grow the filled region by N pixels). Rejected: it eats a constant N pixels into the boundary regardless of stroke width, so it fully consumes thin 2–3px outlines while barely denting 12px ones. This was verified wrong with a 1-D simulation before being discarded.

### The fix: proportional edge blending

Every pixel the fill reaches but rejects on tolerance is treated as an AA edge pixel and blended toward the fill color **in proportion to how close that pixel already was to the target color**:

```dart
worstDiff = max(|r−tr|, |g−tg|, |b−tb|, |a−ta|)   // worst channel
closeness = 1.0 - worstDiff / 255.0                // 0 = pure boundary, 1 = target
pixel = lerp(pixel, fillColor, closeness)
```

A faint fringe pixel (mostly target color) gets mostly filled; a solid boundary pixel (far from target) is barely touched. Crucially this is a **per-pixel decision based only on that pixel's own color** — there is no spatial stepping, so it can never reach further than the single genuine ring of blended edge pixels. That is what makes it width-independent where dilation was not: it physically cannot punch through a stroke no matter how thin it is. Using the **worst** channel (not an average) means a pixel that is close to target in one channel but far in another is correctly read as "mostly boundary" rather than fooling the blend into filling it.

A `processedMask` ensures each edge pixel is blended at most once even when the fill reaches it from several directions, and the input buffer is copied rather than mutated so the caller's snapshot stays intact.

### Opaque buffer invariant

The fill writes the result of `srcOver` compositing — blending the fill color over the existing pixel — rather than stamping the fill color's raw RGBA directly. Writing a fill color with alpha < 255 directly into the buffer stores genuinely transparent pixels, which look correct on screen (the white desk behind the canvas shows through) but break on export and in gallery thumbnails where there is no white background to composite against. The same failure mode affected the eraser via `BlendMode.clear` and was fixed the same way: the raster buffer must stay fully opaque, and any transparency must be simulated by compositing against the existing pixel at write time.

Since the canvas is always opaque (`dstA = 255`), the per-channel `srcOver` formula reduces to:

```dart
out = (fillChannel * fillA + dstChannel * (255 - fillA)) / 255
outA = 255
```

This is applied at both write sites in the fill: the main fill path and the edge-blend path.

`CanvasCompositor.commitFill` extracts pixels with `ImageByteFormat.rawStraightRgba`, **not** `rawRgba`. The raw format returns premultiplied channels, where the blend math above would be comparing color values that have already been scaled by alpha and would give wrong closeness ratios. Straight (un-premultiplied) RGBA gives the true channel values the comparison and `lerp` assume. The fill seed coordinate is `round`ed and `clamp`ed rather than truncated, so the click lands on the intended pixel.

---

## Undo and Redo

History is a stack of committed `ui.Image` snapshots — full raster states, not replayable operations. This is simple and exact: undo is just swapping the displayed image for the previous one.

Every committed action (stroke, shape, fill, clear) funnels through one private method, `_pushUndo`:

```dart
_undoStack.add(image);
if (_undoStack.length > maxHistorySteps) _undoStack.removeAt(0);
_redoStack.clear();   // a new action invalidates the redo branch
_dirty = true;        // single point where the drawing becomes dirty
```

`undo()` pushes the current image onto the redo stack and pops the previous one back; `redo()` is the mirror. Both set `isDirty = true` — leaving the canvas dirty after an undo is intentional and matches desktop editors (Photoshop, Figma), where undoing is itself an unsaved change.

`maxHistorySteps` is 20, giving comfortable headroom over a minimal undo depth. The cap is deliberate because each snapshot is a full-buffer RGBA image at the pixel budget (~3.5 MB at 874,800 px × 4 bytes), so an unbounded stack would grow memory without limit.

`clear()` is a single undoable action — it pushes the current state, then swaps in a blank canvas at the *current* shape (clearing an imported wide canvas keeps it wide). `reset()` is different: it wipes both stacks and the dirty flag and rebuilds the canvas to fill the current editor area, so a new drawing returns to a screen-filling shape regardless of what an import left behind — the same state as a cold launch. `loadImage()` is parallel to `reset()` but with content instead of blank, and it adopts the loaded image's dimensions as the new raster size so the coordinate mapper, clear, and spray clamps all follow the imported shape.

---

## Editor Load Path and State Management

The editor lives in a tab inside `AppShell`, alongside the gallery and settings. `AppShell` is not the app's first screen — `main.dart` sets `MaterialApp.home` to `SplashScreen`, which shows the app icon, wordmark, and a loading indicator for a fixed duration before calling `Navigator.pushReplacement` to `AppShell`. The delay is a deliberate branding pause rather than a wait on real work: `initDependencies()` in `main()` already completes, awaited, before `runApp()` is called, so by the time `SplashScreen` exists there is nothing left in flight to wait on. `pushReplacement` (not a plain push) means there is no back-stack entry leading to the splash screen.

The challenge is letting the gallery open a drawing **into that same editor tab** without pushing a second `EditorScreen` onto the navigator — two live editors would mean two canvas controllers and two undo stacks.

### EditorCubit as an app-scoped singleton

`EditorCubit` is registered in `get_it` as a lazy singleton, so the gallery and the editor tab share one instance. It owns tool/color/size selection and a small load protocol. It **never touches `CanvasController` directly** — it only raises a signal that `EditorScreen` reacts to.

The load protocol:

- `requestLoad(bytes, filePath)` sets `pendingLoad` (a record of the PNG bytes and the source path).
- `AppShell` listens for `pendingLoad` going non-null and switches the bottom-nav index to the editor tab.
- `EditorScreen`'s own listener applies the bytes to `CanvasController` and then calls `acknowledgeLoad(filePath)`, which records the active file and clears `pendingLoad`.
- `cancelLoad()` clears the pending signal without changing the file path — used when the user backs out of the unsaved-changes dialog.
- `notifyNew()` / `notifySaved(path)` keep `currentFilePath` correct so the save flow knows whether to offer "overwrite" or only "save as new".

`currentFilePath` also encodes the save model: when it is null the canvas holds an imported image or a brand-new drawing (save-as-new only); when it is non-null the canvas holds an existing gallery drawing (the save choice — overwrite vs new — is shown).

### Tutorial replay race

`AppShell` also switches to the editor tab when `SettingsState.pendingTutorial` rises (the "show tutorial again" path from Settings). The clearing of that flag is left to `EditorScreen` *after* it has recorded the request for the session — `AppShell` clearing it first was a confirmed race where the tab switched but the overlay never showed, because the flag was gone before `EditorScreen`'s listener ran.

### Other Cubits

`SettingsCubit` and `GalleryCubit` are also lazy singletons (shared settings; one gallery list). `AppShell` provides all three with `BlocProvider.value` so navigating between tabs never disposes them.

---

## Persistence and Gallery

Drawings are saved as PNG files in a dedicated folder inside the app documents directory, resolved once and cached by `LocalDrawingDataSource`.

PNG is chosen because it is lossless — re-opening a saved drawing for editing introduces no generation loss, which a JPEG round-trip would. Filenames carry the creation time down to the millisecond:

```text
drawing_20260612_143205_342.png
```

The millisecond component prevents collisions on rapid saves, and the timestamp doubles as a sortable identity.

`SavedDrawingModel.fromFile` parses `createdAt` **from the filename**, not from filesystem mtime — mtime can change on a copy or a backup restore, which would scramble the gallery's creation-date order. `updatedAt` is set to the live mtime instead, and is part of the entity's `Equatable` props. That is what lets the gallery detect an overwrite (same path, same creation time, new mtime) and refresh the stale thumbnail. The gallery sorts newest-first by `createdAt`.

`save()` writes a new timestamped file; `overwrite(path, bytes)` rewrites an existing one in place; `loadAll()` enumerates and sorts the folder; `delete(path)` removes a file (multi-select delete calls it per selected file).

---

## Dependency Injection

All registrations are in `lib/injection_container.dart`, run in `main()` before `runApp()`.

| Registration | Type | Reason |
| --- | --- | --- |
| `SharedPreferences` | Eager singleton | Must be awaited before any cubit reads it |
| `SettingsCubit` | Lazy singleton | App-wide settings shared across tabs |
| `LocalDrawingDataSource` | Lazy singleton | One cached drawings directory handle |
| `DrawingRepository` | Lazy singleton | One implementation over the data source |
| `GalleryCubit` | Lazy singleton | One shared gallery list |
| `EditorCubit` | Lazy singleton | Shared so the gallery can load into the editor tab without a second route |

`CanvasController` is intentionally **not** registered here — it is created and disposed by `EditorScreen` so its lifetime tracks the screen, not the app.

---

## Key Constants

All canvas tuning lives in `CanvasConstants` (`lib/core/constants/canvas_constants.dart`); storage and filename rules live in `AppConstants`. UI layout, animation, and timing for the hub and the splash screen live in `UiConstants` (`lib/core/constants/ui_constants.dart`).

### CanvasConstants

| Constant | Value | What it controls |
| --- | --- | --- |
| `rasterShortSide` / `rasterLongSide` | 810 / 1080 | Default 3:4 buffer dimensions (blank-canvas fallback) |
| `rasterPixelBudget` | 874,800 | Max raster area; imports and new canvases scale to fit within it |
| `canvasColor` | `0xFFFFFFFF` | Default white substrate; eraser restores to this |
| `canvasMarginColor` | `0xFF333333` | Letterbox margin around a bounded canvas, lighter than the scaffold |
| `canvasBorderColor` / `canvasBorderWidth` | `0x33FFFFFF` / 1 | Border around the canvas rect so the drawable area stands out |
| `brushSizes` | 4 / 10 / 20 | Selectable brush and highlighter widths (raster px) |
| `shapeOutlineWidths` | 3 / 6 / 12 | Selectable shape outline widths (raster px) |
| `spraySizes` | 20 / 40 /60 | Spray scatter radius (not dot size) |
| `sprayDensity` | 30 | Dots scattered per spray tick |
| `maxHistorySteps` | 20 | Undo depth cap, sized for memory rather than left unbounded |
| `fillColorTolerance` | 32 | Per-channel match tolerance before edge blending kicks in |
| `presetColors` | 8 colors | Quick-access palette in the radial swatch menu |
| `gridCellSizes` | 16 / 32 / 64 | Selectable grid cell sizes (raster px); also the pixel art stamp size |
| `defaultGridCellSize` | 32 | Shared default spacing for `EditorState` and `GridSettings.disabled` |
| `timestampPattern` | `yyyyMMdd_HHmmss_SSS` | Filename timestamp; ms component avoids save collisions |

### UiConstants

`UiConstants` (`lib/core/constants/ui_constants.dart`) holds layout, animation, and styling values for the hub and the splash screen. Tool and raster tuning belongs in `CanvasConstants` above.

The onboarding overlay is deliberately **not** covered here. Its spacing became orientation-dependent when the card was made height-bounded and scrollable, which a flat constant list cannot express, so it owns its own layout values as a self-contained widget.

| Constant | Value | What it controls |
| --- | --- | --- |
| `hubHandleSize` | 64 | Diameter of the main hub handle button |
| `hubNodeSize` | 44 | Diameter of each arc node button |
| `hubEdgeMargin` | 24 | Distance from the screen edge to the hub handle |
| `hubArcRadiusInner` | 105 | Inner arc row radius for the general two-row split (7+ nodes) |
| `hubArcRadiusSingle` | 115 | Arc row radius when only one row is shown (up to 4 nodes) |
| `hubArcRadiusFive` | 153 | Single-row radius at exactly 5 nodes; derived to match the proven 4-node adjacent-node clearance |
| `hubArcRadiusSixInner` / `hubArcRadiusSixOuter` | 80 / 140 | Dedicated 2-inner/4-outer split radii for exactly 6 nodes (root, after Mirror's addition); hand-tuned rather than derived — see Mirror Mode → Hub integration above |
| `hubArcRadiusOuter` | 190 | Outer arc row radius for the general two-row split (7+ nodes) |
| `hubPixelArtNodeRadius` | 3 | Corner radius of hub nodes while pixel art mode is active |
| `hubPixelArtRadiusScale` | 1.41 | Arc radius multiplier in pixel art mode, so square nodes keep circles' non-overlap clearance |
| `hubArcDuration` | 280ms | Hub open/close arc animation duration |
| `hubHandleFadeDuration` | 150ms | Handle icon opacity fade duration |
| `hubSurface` | `0xFF242424` | Hub node and handle interior color; hardcoded so it never themes to white |
| `hubHandleRing` / `hubHandleRingWidth` | `0x66FFFFFF` / 2 | Contrast ring on the handle so it stays visible on the dark editor margin |
| `hubScrimOpacity` | 0.08 | Scrim opacity behind open hub arc nodes |
| `hubIconOpacity` | 0.9 | Hub node icon opacity |
| `hubColorNodeBorderOpacity` | 0.85 | Border opacity for the color category node |
| `splashDuration` | 1400ms | Time the splash screen is shown before navigating to `AppShell` |
| `splashIconSize` | 96 | Width and height of the splash icon mark |
