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

  void _ensureCanvasInitialised(BoxConstraints constraints) {
    final displaySize = Size(constraints.maxWidth, constraints.maxHeight);
    _controller.updateDisplaySize(displaySize);

    if (_initRequested) return;
    _initRequested = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialiseCanvas(displaySize);
    });
  }

  Future<void> _initialiseCanvas(Size displaySize) async {
    if (!mounted) return;
    await _controller.initialise(
      rasterSize: CanvasConstants.portraitCanvasSize,
      displaySize: displaySize,
    );
    _initCompleter.complete();
  }

  Future<void> _handlePendingLoad(
    Uint8List bytes,
    String? filePath,
  ) async {
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

    final image = await CanvasCompositor.fromBytes(
      bytes,
      CanvasConstants.portraitCanvasSize,
    );
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
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: save,
              ),
              IconButton(
                icon: const Icon(Icons.ios_share),
                onPressed: export,
              ),
              PopupMenuButton<_EditorMenu>(
                onSelected: (item) {
                  switch (item) {
                    case _EditorMenu.newDrawing:
                      newDrawing();
                    case _EditorMenu.clear:
                      clear();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _EditorMenu.newDrawing,
                    child: ListTile(
                      leading: Icon(Icons.note_add_outlined),
                      title: Text('New drawing'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _EditorMenu.clear,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Clear canvas'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: _buildCanvas(),
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureCanvasInitialised(constraints);
        return Stack(
          children: [
            BlocBuilder<EditorCubit, EditorState>(
              builder: (context, editorState) {
                return GestureDetector(
                  onPanStart: (d) => _controller.onPointerDown(
                    d.localPosition,
                    editorState.tool,
                    editorState.color,
                    editorState.strokeSize,
                  ),
                  onPanUpdate: (d) =>
                      _controller.onPointerMove(d.localPosition),
                  onPanEnd: (_) => _controller.onPointerUp(),
                  child: ValueListenableBuilder<CanvasState>(
                    valueListenable: _controller,
                    builder: (_, state, _) => CustomPaint(
                      painter: DrawingCanvasPainter(state: state),
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                    ),
                  ),
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
}

enum _EditorMenu { newDrawing, clear }

enum _LoadChoice { cancel, discard, save }