# Doodlingz — Technical Overview

This document covers the architecture, the raster pipeline, each drawing tool, the flood-fill algorithm, undo/redo, the editor load path, and the persistence layer. The README covers features and setup; this covers the code.

---

## Table of Contents

- [Architecture](#architecture)
- [The Raster Pipeline](#the-raster-pipeline)
- [Coordinate Mapping](#coordinate-mapping)
- [Drawing Tools](#drawing-tools)
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

A note on layer placement: the raster engine (`canvas_compositor.dart`, `flood_fill.dart`, `coordinate_mapper.dart`, `canvas_fit.dart`, `stroke.dart`) lives under `presentation/editor/engine/` rather than in core. It is `dart:ui` rendering code tied to the editor screen, not app-wide configuration, so it sits with the feature that owns it.

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

`DrawingCanvasPainter` does exactly this: it draws the committed image first, then — if an active stroke exists — paints it as vectors above. The preview paint logic and the commit paint logic are deliberately kept identical per tool (same path construction, same blend modes, same spray dots) so what the user sees during the gesture is exactly what gets baked in.

### CanvasController and ValueNotifier

`CanvasController` (`controller/canvas_controller.dart`) extends `ValueNotifier<CanvasState>` rather than being a BLoC. Pointer-move events fire at the display refresh rate; routing each one through a BLoC would emit a new state object and run comparison logic every frame, flooding the platform channel. `ValueNotifier` is the Flutter primitive built for exactly this high-frequency case, and a `ValueListenableBuilder` rebuilds only the canvas widget. BLoC is still used everywhere else (tool selection, gallery, settings).

The controller is **owned and created directly by `EditorScreen`**, not registered in `get_it`. Its lifetime is tied to the screen, which avoids the stale-singleton trap where a `get_it` instance survives a screen dispose and comes back holding old pixels.

### CanvasState

`CanvasState` is the immutable snapshot the controller publishes:

```dart
final ui.Image    committedImage;   // last fully baked raster
final Stroke?     activeStroke;      // in-progress vector overlay, or null
final bool        canUndo;
final bool        canRedo;
final bool        isDirty;           // pixels changed since last save/load/reset
final ViewTransform view;            // user zoom/pan; identity = plain contain-fit
```

Because a pointer-move produces a new state every frame, the fields are kept minimal — the heavy `ui.Image` is passed by reference, not copied.

### Budget-bounded raster buffer

All drawing happens against a pixel buffer, not the on-screen widget size. The buffer's *shape* is not fixed, but its *area* is: it always stays within a pixel budget of **810 × 1080 = 874,800 pixels** (`rasterPixelBudget`). What occupies that budget depends on how the canvas was created:

- A **blank new drawing** is shaped to the editor area's aspect ratio (`rasterSizeForArea`), so it fills the screen without letterboxing. On a tall phone that is roughly 683 × 1280; the 3:4 presets (`portraitCanvasSize` / `landscapeCanvasSize`) remain as the pre-layout default and fallback.
- An **imported image** keeps its own aspect ratio, scaled down only until its area is under budget (`CanvasCompositor.fromBytes`). A wide panorama becomes a wide buffer; a tall photo becomes a tall one.

Bounding the *area* rather than the *dimensions* is what actually keeps flood-fill cost and per-snapshot memory constant — those scale with pixel count, not shape. Tool sizes are still expressed in *raster* pixels, so a 10px brush is a consistent fraction of the buffer. The display layer scales the buffer to fit the available space with a single uniform scale (never separate per-axis scales, which would distort), and the committed image is drawn with `FilterQuality.high` to smooth that scale.

---

## Coordinate Mapping

Because the buffer and the display area can have different aspect ratios, the canvas is fitted into its display area with a single uniform scale and centred — the `BoxFit.contain` model. A single helper, `fitRasterInDisplay()` (`engine/canvas_fit.dart`), computes that base fit and is the **one** source of truth shared by the painter and the coordinate mapper.

When the user zooms or pans, a `ViewTransform` (zoom factor + pan offset) is composed on top of the base fit by `fitRasterWithView()` in the same file. Both the painter and the mapper call this composed version — never the base fit directly while a transform is active — so the rendered image and the touch mapping stay locked to the same geometry. `ViewTransform.applyGesture()` handles the focal-anchored zoom math (keeping the content under the pinch fingers fixed as the zoom changes) and clamps the pan so the canvas cannot be dragged off-screen.

`localToRaster()` (`engine/coordinate_mapper.dart`) inverts the composed fit to convert a pointer position in the rendered widget's local space into a raster coordinate:

```dart
fit = fitRasterWithView(rasterSize, displaySize, zoom, pan)  // composed fit
rx = ((localPosition.dx - fit.destination.left) / fit.scale).clamp(0, rasterSize.width  - 1)
ry = ((localPosition.dy - fit.destination.top)  / fit.scale).clamp(0, rasterSize.height - 1)
```

The clamp guarantees every returned coordinate is a valid index into the raw byte buffer regardless of zoom level. When the view is at identity (zoom 1, pan zero), `fitRasterWithView` returns the untouched base fit, so there is no overhead for the common no-zoom case. The painter clips to the canvas widget bounds at the top of `paint()` so zoomed pixels can never spill over the paper border into the desk margin.

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

This is deliberate. The task requires the eraser to *restore the affected area to the canvas's default color*, and the whole app assumes opaque canvases — gallery thumbnails and the re-open-for-edit flow both expect a solid background. An earlier attempt using `BlendMode.clear` with `saveLayer` sandboxing was reverted: it would have punched real holes in the buffer and produced transparent PNG exports, breaking that assumption. Painting white is the correct model here.

Because the eraser's color is fixed, the hub's color node is suppressed when the eraser is active (`_showsColor()` in `editor_hub.dart`) — showing a color picker for a tool that ignores it would confuse the user.

### Spray

This is the tool that most often trips people up on this task, because the obvious implementation — drawing one big translucent circle that scales with the tool size — looks like a blurry stamp, not an airbrush. Doodlingz scatters individual dots instead, with two details doing the work:

**The tool "size" is the scatter radius, not the dot size.** The two spray sizes (20 and 40) set how wide the cloud of dots spreads from the finger. The dots themselves are always a fine fixed 1.2px radius. So a bigger spray covers a wider area with the same fine grain, exactly like opening up an airbrush nozzle.

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

The task requires 5 steps; `maxHistorySteps` is 20. The headroom is deliberately capped because each snapshot is a full-buffer RGBA image at the pixel budget (~3.5 MB at 874,800 px × 4 bytes), so an unbounded stack would grow memory without limit.

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

All canvas tuning lives in `CanvasConstants` (`lib/core/constants/canvas_constants.dart`); storage and filename rules live in `AppConstants`. UI layout, animation, and timing for everything outside the canvas — the hub, overlays, and the splash screen — lives in `UiConstants` (`lib/core/constants/ui_constants.dart`).

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
| `spraySizes` | 20 / 40 | Spray scatter radius (not dot size) |
| `sprayDensity` | 30 | Dots scattered per spray tick |
| `maxHistorySteps` | 20 | Undo depth cap (task floor is 5; capped for memory) |
| `fillColorTolerance` | 32 | Per-channel match tolerance before edge blending kicks in |
| `presetColors` | 8 colors | Quick-access palette in the radial swatch menu |
| `timestampPattern` | `yyyyMMdd_HHmmss_SSS` | Filename timestamp; ms component avoids save collisions |

### UiConstants

`UiConstants` (`lib/core/constants/ui_constants.dart`) holds layout, animation, and styling values for widgets outside the canvas — the hub, overlays, and splash screen. Tool and raster tuning belongs in `CanvasConstants` above; this is everything else.

| Constant | Value | What it controls |
| --- | --- | --- |
| `hubHandleSize` | 64 | Diameter of the main hub handle button |
| `hubNodeSize` | 44 | Diameter of each arc node button |
| `hubEdgeMargin` | 24 | Distance from the screen edge to the hub handle |
| `hubArcRadiusInner` | 105 | Inner arc row radius when two rows are shown |
| `hubArcRadiusSingle` | 115 | Arc row radius when only one row is shown |
| `hubArcRadiusOuter` | 190 | Outer arc row radius when two rows are shown |
| `hubArcDuration` | 280ms | Hub open/close arc animation duration |
| `hubHandleFadeDuration` | 150ms | Handle icon opacity fade duration |
| `hubSurface` | `0xFF242424` | Hub node and handle interior color; hardcoded so it never themes to white |
| `hubHandleRing` / `hubHandleRingWidth` | `0x66FFFFFF` / 2 | Contrast ring on the handle so it stays visible on the dark editor margin |
| `hubScrimOpacity` | 0.08 | Scrim opacity behind open hub arc nodes |
| `hubIconOpacity` | 0.9 | Hub node icon opacity |
| `hubColorNodeBorderOpacity` | 0.85 | Border opacity for the color category node |
| `overlayAnimDuration` | 300ms | Onboarding overlay scale+fade animation duration |
| `overlayScrimOpacity` | 0.55 | Peak scrim opacity behind the onboarding card |
| `overlayCardRadius` | 16 | Onboarding card corner radius |
| `overlayCardPadding` | `EdgeInsets.fromLTRB(24, 28, 24, 20)` | Padding inside the onboarding card |
| `overlayHorizontalMargin` | 32 | Horizontal margin between the onboarding card and screen edges |
| `overlayToolListHeight` | 240 | Fixed height of the tool-reference list on page 2 of the overlay |
| `splashDuration` | 1400ms | Time the splash screen is shown before navigating to `AppShell` |
| `splashIconSize` | 96 | Width and height of the splash icon mark |
