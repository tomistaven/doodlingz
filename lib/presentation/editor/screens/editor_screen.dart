import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/canvas_constants.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../controller/canvas_controller.dart';
import '../controller/canvas_state.dart';
import '../cubit/editor_cubit.dart';
import '../cubit/editor_state.dart';
import '../engine/canvas_compositor.dart';
import '../engine/canvas_fit.dart';
import '../painter/drawing_canvas_painter.dart';
import '../widgets/editor_hub.dart';
import '../widgets/onboarding_overlay.dart';
import 'editor_actions.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with EditorActions {
  late final CanvasController _controller;

  bool _initRequested = false;
  bool _tutorialDismissedThisSession = false;
  bool _tutorialRequestedThisSession = false;

  // True for the rest of a gesture once it has become multi-touch, so a pinch
  // never reverts to drawing. Lifting one finger out of a pinch keeps the
  // gesture navigational, so release can't resurrect a stroke and commit a
  // stray mark. Driven by raw pointer count, reset when all fingers lift.
  bool _navigating = false;

  // Raw pointer count from a Listener, not the scale recogniser. When two
  // fingers land a fraction apart the recogniser reports start -> end -> start
  // rather than one continuous gesture, and that middle end would commit the
  // first finger's stroke as a stray dot. Raw down events fire before the arena
  // re-resolves, so the second finger cancels the stroke before any commit.
  int _rawPointers = 0;

  // Hand-flip to true on-device to trace gesture transitions in the log. Baked
  // in because escalation handling is the one part of this feature prone to the
  // stray-mark regression, and a transition trace pinpoints it immediately.
  static final bool _logGestures = false;

  /// Completes when [CanvasController.initialise] returns.
  /// Load requests that arrive before init finishes await this before
  /// calling [CanvasController.loadImage], preventing a race between the
  /// cold-launch blank creation and an incoming image swap.
  final Completer<void> _initCompleter = Completer<void>();

  @override
  CanvasController get controller => _controller;

  @override
  void initState() {
    super.initState();
    _controller = CanvasController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerDownRaw() {
    _rawPointers++;
    if (_rawPointers >= 2 && !_navigating) {
      _navigating = true;
      _zoomDiag('second pointer down -> navigation, cancelling stroke');
      _controller.cancelStroke();
    }
  }

  void _onPointerUpRaw() {
    if (_rawPointers > 0) _rawPointers--;
    if (_rawPointers == 0) _navigating = false;
  }

  void _onScaleStart(ScaleStartDetails details, EditorState editorState) {
    _controller.beginView();
    if (_navigating) {
      _zoomDiag('start: navigation');
      return;
    }
    _zoomDiag('start: draw');
    _controller.onPointerDown(
      details.localFocalPoint,
      editorState.tool,
      editorState.color,
      editorState.strokeSize,
      isPixelArt: editorState.pixelArtMode,
      pixelCellSize: editorState.gridCellSize,
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_navigating) {
      _controller.updateView(
        scale: details.scale,
        focalPoint: details.localFocalPoint,
        focalDelta: details.focalPointDelta,
      );
      return;
    }
    _controller.onPointerMove(details.localFocalPoint);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_navigating) {
      _zoomDiag('end: navigation');
      return;
    }
    _zoomDiag('end: commit stroke');
    _controller.onPointerUp();
  }

  void _zoomDiag(String message) {
    if (_logGestures) debugPrint('[zoom] $message');
  }

  void _ensureCanvasInitialised(BoxConstraints constraints) {
    if (_initRequested) return;
    _initRequested = true;

    final areaSize = Size(constraints.maxWidth, constraints.maxHeight);
    final rasterSize = CanvasConstants.rasterSizeForArea(areaSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialiseCanvas(rasterSize, _canvasDisplaySize(areaSize, rasterSize));
    });
  }

  // The canvas widget is constrained to the raster's aspect ratio, so the size
  // the coordinate mapper sees is the fitted rect, not the whole editor area.
  Size _canvasDisplaySize(Size areaSize, Size rasterSize) {
    return fitRasterInDisplay(
      rasterSize: rasterSize,
      displaySize: areaSize,
    ).destination.size;
  }

  Future<void> _initialiseCanvas(Size rasterSize, Size displaySize) async {
    if (!mounted) return;
    await _controller.initialise(
      rasterSize: rasterSize,
      displaySize: displaySize,
    );
    _initCompleter.complete();
  }

  Future<void> _handlePendingLoad(Uint8List bytes, String? filePath) async {
    final cubit = context.read<EditorCubit>();

    if (_controller.value.isDirty) {
      final choice = await showDialog<_LoadChoice>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text(
            'You have unsaved changes. Save before opening this drawing?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_LoadChoice.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_LoadChoice.discard),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_LoadChoice.save),
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (choice == null || choice == _LoadChoice.cancel) {
        cubit.cancelLoad();
        return;
      }

      if (choice == _LoadChoice.save) {
        await save();
        // save() can itself be cancelled at the bottom sheet; if the canvas
        // is still dirty the user backed out, so abort the load too.
        if (!mounted || _controller.value.isDirty) {
          cubit.cancelLoad();
          return;
        }
      }
    }

    await _initCompleter.future;
    if (!mounted) return;

    final image = await CanvasCompositor.fromBytes(bytes);
    if (!mounted) return;

    _controller.loadImage(image);
    if (mounted) cubit.acknowledgeLoad(filePath);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<EditorCubit, EditorState>(
      listenWhen: (previous, current) =>
          current.pendingLoad != null && previous.pendingLoad == null,
      listener: (context, state) {
        _handlePendingLoad(
          state.pendingLoad!.bytes,
          state.pendingLoad!.filePath,
        );
      },
      child: BlocListener<EditorCubit, EditorState>(
        listenWhen: (previous, current) =>
            previous.gridVisible != current.gridVisible ||
            previous.gridCellSize != current.gridCellSize,
        listener: (context, state) {
          _controller.setGridVisible(state.gridVisible);
          _controller.setGridCellSize(state.gridCellSize);
        },
        child: BlocListener<SettingsCubit, SettingsState>(
          listenWhen: (previous, current) =>
              current.pendingTutorial && !previous.pendingTutorial,
          listener: (context, state) {
            setState(() {
              _tutorialDismissedThisSession = false;
              _tutorialRequestedThisSession = true;
            });
            context.read<SettingsCubit>().clearPendingTutorial();
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Doodlingz'),
              actions: [
                ValueListenableBuilder<CanvasState>(
                  valueListenable: _controller,
                  builder: (_, state, _) => IconButton(
                    icon: const Icon(Icons.undo),
                    onPressed: state.canUndo ? _controller.undo : null,
                  ),
                ),
                ValueListenableBuilder<CanvasState>(
                  valueListenable: _controller,
                  builder: (_, state, _) => IconButton(
                    icon: const Icon(Icons.redo),
                    onPressed: state.canRedo ? _controller.redo : null,
                  ),
                ),
                IconButton(icon: const Icon(Icons.save), onPressed: save),
                IconButton(
                  icon: const Icon(Icons.save_alt),
                  onPressed: export,
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showEditorMenu(context),
                ),
              ],
            ),
            body: _buildCanvas(),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureCanvasInitialised(constraints);
        final areaSize = Size(constraints.maxWidth, constraints.maxHeight);
        _controller.setEditorArea(areaSize);
        return Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(color: CanvasConstants.canvasMarginColor),
            ),
            BlocBuilder<EditorCubit, EditorState>(
              builder: (context, editorState) {
                return ValueListenableBuilder<CanvasState>(
                  valueListenable: _controller,
                  builder: (_, state, _) {
                    final raster = _controller.rasterSize;
                    // Keep the mapper's display size in step with the fitted
                    // rect whenever an import reshapes the raster.
                    _controller.updateDisplaySize(
                      _canvasDisplaySize(areaSize, raster),
                    );
                    return Center(
                      child: AspectRatio(
                        aspectRatio: raster.width / raster.height,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: CanvasConstants.canvasBorderColor,
                              width: CanvasConstants.canvasBorderWidth,
                            ),
                          ),
                          child: Listener(
                            onPointerDown: (_) => _onPointerDownRaw(),
                            onPointerUp: (_) => _onPointerUpRaw(),
                            onPointerCancel: (_) => _onPointerUpRaw(),
                            child: GestureDetector(
                              onScaleStart: (d) =>
                                  _onScaleStart(d, editorState),
                              onScaleUpdate: _onScaleUpdate,
                              onScaleEnd: _onScaleEnd,
                              child: ColoredBox(
                                color: CanvasConstants.canvasColor,
                                child: CustomPaint(
                                  painter: DrawingCanvasPainter(state: state),
                                  size: Size.infinite,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const Positioned.fill(child: EditorHub()),
            BlocBuilder<SettingsCubit, SettingsState>(
              builder: (context, settings) {
                if (_tutorialDismissedThisSession ||
                    (!settings.showTutorialOnStartup &&
                        !_tutorialRequestedThisSession)) {
                  return const SizedBox.shrink();
                }
                return Positioned.fill(
                  child: OnboardingOverlay(
                    onDismiss: () {
                      setState(() {
                        _tutorialDismissedThisSession = true;
                        _tutorialRequestedThisSession = false;
                      });
                    },
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditorMenu(BuildContext context) async {
    final action = await showModalBottomSheet<VoidCallback>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('New drawing'),
              onTap: () => Navigator.of(context).pop(newDrawing),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Clear canvas'),
              onTap: () => Navigator.of(context).pop(clear),
            ),
          ],
        ),
      ),
    );
    action?.call();
  }
}

enum _LoadChoice { cancel, discard, save }