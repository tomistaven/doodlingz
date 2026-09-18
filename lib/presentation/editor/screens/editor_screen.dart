import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
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

  bool _navigating = false;
  int _rawPointers = 0;
  static final bool _logGestures = false;

  final ValueNotifier<String> _diagnostics = ValueNotifier<String>(
    'waiting for pointer',
  );

  final ValueNotifier<Offset?> _stylusCursor = ValueNotifier<Offset?>(null);
  final ValueNotifier<bool> _isStylusDown = ValueNotifier<bool>(false);

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
    _diagnostics.dispose();
    _stylusCursor.dispose();
    _isStylusDown.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onPointerDownRaw(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      _isStylusDown.value = true;
    }
    
    _rawPointers++;
    if (_rawPointers >= 2 && !_navigating) {
      _navigating = true;
      _zoomDiag('second pointer down -> navigation, cancelling stroke');
      _controller.cancelStroke();
    }
    _onPointerEvent(event, 'DOWN ');
  }

  void _onPointerMoveRaw(PointerMoveEvent event) {
    _onPointerEvent(event, 'MOVE ');
  }

  void _onPointerHoverRaw(PointerHoverEvent event) {
    _onPointerEvent(event, 'HOVER');
  }

  void _onPointerUpRaw(PointerEvent event) {
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      _isStylusDown.value = false;
    }
    
    if (_rawPointers > 0) _rawPointers--;
    if (_rawPointers == 0) _navigating = false;
    _onPointerEvent(event, 'UP   ');
  }

  void _onPointerEvent(PointerEvent event, String phase) {
    _updateStylusCursor(event);
    _updateDiagnostics(event, phase);
  }

  void _updateStylusCursor(PointerEvent event) {
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      // If a different input device (like touch) is used, clear the stylus cursor
      if (_stylusCursor.value != null) {
        _stylusCursor.value = null;
      }
      return;
    }
    _stylusCursor.value = event.localPosition;
  }

  void _updateDiagnostics(PointerEvent event, String phase) {
    if (!context.read<SettingsCubit>().state.diagnosticsOverlayEnabled) {
      return;
    }
    final kindLabel = switch (event.kind) {
      PointerDeviceKind.stylus => 'Stylus',
      PointerDeviceKind.invertedStylus => 'Stylus(inv)',
      PointerDeviceKind.touch => 'Touch',
      PointerDeviceKind.mouse => 'Mouse',
      PointerDeviceKind.trackpad => 'Trackpad',
      PointerDeviceKind.unknown => 'Unknown',
    };
    _diagnostics.value =
        '$phase $kindLabel  P:${event.pressure.toStringAsFixed(3)}\n'
        '(${event.localPosition.dx.round()}, '
        '${event.localPosition.dy.round()})';
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
      mirror: editorState.mirrorMode,
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_navigating) {
      _controller.updateView(
        scale: details.scale,
        rotation: details.rotation,
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
        child: BlocListener<EditorCubit, EditorState>(
          listenWhen: (previous, current) =>
              previous.mirrorMode != current.mirrorMode,
          listener: (context, state) {
            _controller.setMirrorGuideVisible(state.mirrorMode);
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
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureCanvasInitialised(constraints);
        final areaSize = Size(constraints.maxWidth, constraints.maxHeight);
        _controller.setEditorArea(areaSize);
        return Listener(
          onPointerHover: _onPointerHoverRaw,
          child: Stack(
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
                              onPointerDown: _onPointerDownRaw,
                              onPointerMove: _onPointerMoveRaw,
                              onPointerUp: _onPointerUpRaw,
                              onPointerCancel: _onPointerUpRaw,
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
              _StylusCursor(position: _stylusCursor, isDown: _isStylusDown),
              BlocBuilder<SettingsCubit, SettingsState>(
                buildWhen: (previous, current) =>
                    previous.diagnosticsOverlayEnabled !=
                    current.diagnosticsOverlayEnabled,
                builder: (context, settings) {
                  if (!settings.diagnosticsOverlayEnabled) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    top: 8,
                    left: 8,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ValueListenableBuilder<String>(
                          valueListenable: _diagnostics,
                          builder: (_, text, _) => Text(
                            text,
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              height: 1.35,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
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
          ),
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

class _StylusCursor extends StatelessWidget {
  const _StylusCursor({required this.position, required this.isDown});

  final ValueNotifier<Offset?> position;
  final ValueNotifier<bool> isDown;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset?>(
      valueListenable: position,
      builder: (_, offset, _) {
        if (offset == null) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: isDown,
          builder: (_, down, _) {
            final double size = down ? 12.0 : 24.0;
            return Positioned(
              left: offset.dx - size / 2,
              top: offset.dy - size / 2,
              child: IgnorePointer(
                child: CustomPaint(
                  size: Size.square(size),
                  painter: _StylusCursorPainter(isDown: down),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StylusCursorPainter extends CustomPainter {
  _StylusCursorPainter({required this.isDown});
  
  final bool isDown;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    final shadow = Paint()
      ..color = Colors.black45
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
      
    final outline = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw the main circle
    canvas.drawCircle(center, radius, shadow);
    canvas.drawCircle(center, radius, outline);

    // Draw the center dot only if hovering (stylus up)
    if (!isDown) {
      final dotFill = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final dotShadow = Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
        
      canvas.drawCircle(center, 2, dotFill);
      canvas.drawCircle(center, 2, dotShadow);
    }
  }

  @override
  bool shouldRepaint(_StylusCursorPainter oldDelegate) {
    return oldDelegate.isDown != isDown;
  }
}