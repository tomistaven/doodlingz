# Doodlingz

A mobile drawing app that lets you sketch, paint, and save your ideas anywhere — no internet, no stylus required.

---

## Screenshots

| Editor | Tool Hub | Color Picker | Settings |
|---|---|---|---|
| ![](screenshots/01_editor.png) | ![](screenshots/02_hub.png) | ![](screenshots/03_color.png) | ![](screenshots/04_settings.png) |

---

## Table of Contents

- [Project Overview](#project-overview)
- [Feature Summary](#feature-summary)
- [Architecture](#architecture)
- [Dependencies](#dependencies)
- [Setup and Installation](#setup-and-installation)
- [Reviewer Guide](#reviewer-guide)
- [Usage Guide](#usage-guide)
- [Design Decisions and Challenges](#design-decisions-and-challenges)

---

## Project Overview

Doodlingz is a Flutter drawing application for Android. It gives you a full-screen white canvas with a minimal dark-chrome UI that stays out of the way while you draw. Tools are accessed through a nested radial hub in the corner of the screen, keeping the entire canvas surface available for drawing. Drawings are saved as PNG files to local device storage. The app works fully offline and requires no account or external services.

---

## Feature Summary

### Core Features

| Feature | Description |
|---|---|
| Brush | Freehand drawing in 3 sizes |
| Eraser | Restores pixels to white canvas color in 3 sizes |
| Spray / Airbrush | Scattered dot spray in 2 sizes |
| Fill | Flood-fill any enclosed region or the whole canvas |
| Straight line | Drag to draw a line, preview shown while dragging |
| Rectangle | Drag to size; draw squares by dragging diagonally |
| Ellipse | Drag to size; draw circles by dragging diagonally |
| Color picker | 8 preset swatches + full wheel picker with hex input and opacity |
| Undo | 20-step undo history |
| Save | Saves drawing as PNG to local storage with timestamp filename |

### Extra Features

| Feature | Notes |
|---|---|
| Triangle shape tool | Drag to size, same gesture model as rectangle and ellipse |
| Highlighter tool | Semi-transparent brush stroke |
| Reviewer-ready APK | Pre-built APK on Google Drive, three install methods documented below |

### Bonus Features

| Feature | What it does |
|---|---|
| **Redo** | Full redo stack — restores steps undone in the current session |
| **Left-handed mode** | Mirrors the tool hub to the bottom-right corner via a Settings toggle |

---

## Architecture

The project uses Flutter Clean Architecture with three layers:

```
lib/
  core/           Constants, theme, utilities shared across layers
  domain/         Business rules — entities and repository interfaces only, no Flutter imports
  data/           Data sources, models, repository implementations
  presentation/   BLoC/Cubit state management, screens, widgets
```

**Domain layer** — defines `DrawingTool`, `SavedDrawing`, and the `DrawingRepository` interface. No Flutter imports. Pure Dart.

**Data layer** — implements `LocalDrawingDataSource` (PNG read/write via `path_provider`) and `DrawingRepositoryImpl`. Knows about `dart:io` and `intl`; no Flutter widgets.

**Presentation layer** — `EditorCubit` (tool/color/size), `SettingsCubit` (theme/handedness). Screens and widgets never call repositories directly.

**Dependency injection** — `get_it` service locator. `SettingsCubit` and repositories registered as lazy singletons. `EditorCubit` created directly in `EditorScreen` (screen-scoped, not a singleton).

**Canvas pipeline** — drawing operations use a hybrid model: vector preview rendered live via `CustomPainter` during a gesture, then committed to a fixed `ui.Image` raster buffer on pointer-up. Undo snapshots the raster buffer after each commit. Flood fill runs on a background isolate via `compute()`.

---

## Dependencies

| Package | Purpose |
|---|---|
| `flutter_bloc` | Cubit state management across all screens |
| `equatable` | Value equality for Cubit states — prevents unnecessary rebuilds |
| `get_it` | Dependency injection via service locator |
| `shared_preferences` | Persists theme mode and hub handedness setting |
| `path_provider` | Resolves the app documents directory for PNG storage |
| `intl` | `DateFormat` for timestamp-based filenames |
| `google_fonts` | Inter typeface |
| `flex_color_picker` | Color wheel dialog with hex input and opacity slider |

---

## Setup and Installation

Most reviewers should use the pre-built APK in the Reviewer Guide below. These steps are for building from source.

### Prerequisites

- Flutter 3.29 or later
- Dart 3.7 or later
- Android SDK with a connected device or emulator (Android 6.0 / API 23 minimum)

### Steps

```bash
git clone [repo URL]
cd doodlingz
flutter pub get
flutter run
```

No code generation step required — the project has no `build_runner` dependency.

### Building a release APK

```bash
flutter build apk --release
```

The output APK is at `build/app/outputs/flutter-apk/app-release.apk`.

---

## Reviewer Guide

A pre-built APK is provided so the app can be tested without installing Flutter.

**APK download:** [Google Drive — doodlingz.apk](LINK_HERE)

---

### Option 1: Install directly on an Android device

**Step 1 — Allow installation from outside the Play Store**

1. Open **Settings** on your device.
2. Search for **"Install unknown apps"** or go to **Security → Install unknown apps**.
3. Find **Chrome** and toggle **Allow from this source** on.

**Step 2 — Download and install**

1. On your Android phone, open **Chrome** and tap the Google Drive link above. Tap **Download**.
2. Open the **Files** app → **Downloads**.
3. Tap **doodlingz.apk** → **Install**. If Play Protect warns you, tap **Install anyway**.
4. Find **Doodlingz** in your app drawer and launch it.

---

### Option 2: Lightweight emulator (BlueStacks or NoxPlayer)

**BlueStacks:**
1. Download from [bluestacks.com](https://www.bluestacks.com) and install.
2. Drag and drop the APK onto the BlueStacks window — it installs automatically.
3. Launch **Doodlingz** from the My Apps tab.

**NoxPlayer:**
1. Download from [bignox.com](https://www.bignox.com) and install.
2. Drag and drop the APK onto the NoxPlayer window, or use the APK installer in the toolbar.
3. Launch **Doodlingz** from the home screen.

---

### Option 3: Browser-based emulator (Appetize.io)

1. Go to [appetize.io](https://appetize.io).
2. Click **Upload** and select the APK.
3. Click **Run** to start the virtual device in your browser.
4. Click = tap, click-and-drag = swipe.

Sessions time out after a few minutes of inactivity on the free tier. Refresh and click Run again to restart.

---

## Usage Guide

### Drawing on the canvas

The white canvas fills the screen. Draw by dragging your finger. The tool hub handle sits in the bottom corner — tap it to open tool, color, and size controls.

### Tool hub

Tap the circular handle in the bottom corner to open the hub. The root level shows three category nodes: **Tools** (draw icon), **Color** (filled circle), and **Size** (line weight icon). Tap a category to expand it into its options. Tap a node to select it and close the hub. Tap the handle again or the scrim to close without changing anything.

- While in a sub-level, the handle icon shows a back arrow — tap it to return to the root level.
- The size node is hidden when the fill tool is active.

### Shapes

Select line, rectangle, ellipse, or triangle from the Tools level. Tap and drag on the canvas — a live preview shows as you drag, and the shape is committed when you lift your finger.

### Undo and redo

Undo and redo buttons are in the app bar. Up to 20 undo steps are stored per session. The redo stack is cleared when you make a new drawing action after undoing.

### Saving

Tap the save icon in the app bar. The drawing is saved as a PNG to local storage. A snackbar confirms the save.

### Settings

Tap the settings icon in the bottom navigation bar. Choose between system default, light, and dark theme. Toggle **Move tool hub to right side** to mirror the hub to the bottom-right corner for left-handed use.

---

## Design Decisions and Challenges

### Fixed raster buffer instead of a resizing canvas

The drawing buffer is fixed at 810×1080 pixels (portrait) regardless of device screen size or orientation. The display layer scales this buffer to fill the available space. This means brush sizes, fill operations, and undo snapshots are all consistent across devices — a "medium" brush is the same number of raster pixels on a small phone and a large tablet. The alternative (a canvas that reshapes to match the screen) would change stroke proportions and invalidate the undo history on orientation change.

### Hybrid vector-preview / raster-commit pipeline

During a gesture, strokes are drawn as vectors via `CustomPainter` for smooth, zero-lag preview. On pointer-up the stroke is committed to a `dart:ui` `ui.Image` raster buffer. This gives responsive drawing feedback without accumulating an ever-growing vector list that would slow repaints on long sessions.

### Flood fill on a background isolate

Flood fill is iterative (queue-based, not recursive) and runs via `compute()` on a background isolate. Recursive fill overflows the stack on large regions; running on the main isolate would freeze the UI for the duration of the fill. The iterative approach on a background isolate keeps the UI responsive and handles full-canvas fills cleanly.

### Radial hub instead of a fixed tool panel

A fixed toolbar along the bottom or side of the screen permanently reduces the drawable canvas area. The radial hub only occupies screen space when open, keeping the full canvas available while drawing. The hub is anchored to a corner so the arc of nodes is reachable with a single thumb movement without crossing the canvas.

### Eraser as white brush

The eraser restores pixels to the canvas's fixed white color rather than using a transparency erase. This matches the task requirement ("restore the affected area to the canvas's default color") and avoids the complexity of an alpha channel in the raster pipeline.