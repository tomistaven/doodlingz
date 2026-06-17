import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/canvas_constants.dart';
import '../../../domain/repositories/drawing_repository.dart';
import '../../../injection_container.dart';
import '../../gallery/cubit/gallery_cubit.dart';
import '../controller/canvas_controller.dart';
import '../cubit/editor_cubit.dart';
import '../cubit/editor_state.dart';
import '../engine/canvas_compositor.dart';
import '../painter/drawing_canvas_painter.dart';
import '../widgets/editor_hub.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    this.existingImageBytes,
    this.existingFilePath,
  });

  /// Non-null when opening a saved drawing or imported image for editing.
  final Uint8List? existingImageBytes;

  /// Non-null when the image was opened from the app gallery, enabling the
  /// overwrite save option. Null for imported device images (save as new only).
  final String? existingFilePath;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final CanvasController _controller;
  late final EditorCubit _editorCubit;

  bool _initRequested = false;

  @override
  void initState() {
    super.initState();
    _controller = CanvasController();
    _editorCubit = EditorCubit();
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorCubit.close();
    super.dispose();
  }

  /// Feeds the live display size to the controller every layout pass, and
  /// schedules the one-time async buffer creation exactly once.
  ///
  /// The schedule runs after the frame so the controller's notification never
  /// fires mid-build, and the [_initRequested] guard closes the re-entry window
  /// that earlier let a second layout pass start a concurrent initialise during
  /// the first one's await.
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
    ui.Image? existing;
    if (widget.existingImageBytes != null) {
      existing = await CanvasCompositor.fromBytes(
        widget.existingImageBytes!,
        CanvasConstants.portraitCanvasSize,
      );
    }

    if (!mounted) return;

    await _controller.initialise(
      rasterSize: CanvasConstants.portraitCanvasSize,
      displaySize: displaySize,
      existingImage: existing,
    );
  }

  Future<void> _save() async {
    final bytes = await _controller.toPngBytes();
    await sl<DrawingRepository>().save(bytes);

    // Notify the gallery singleton so the grid refreshes immediately even
    // though EditorScreen is kept alive in IndexedStack.
    sl<GalleryCubit>().load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drawing saved')),
      );
    }
  }

  Future<void> _saveWithChoice() async {
    if (widget.existingFilePath == null) {
      await _save();
      return;
    }

    final choice = await showModalBottomSheet<_SaveChoice>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Save as new drawing'),
              onTap: () => Navigator.of(context).pop(_SaveChoice.saveNew),
            ),
            ListTile(
              leading: const Icon(Icons.save),
              title: const Text('Overwrite existing'),
              onTap: () => Navigator.of(context).pop(_SaveChoice.overwrite),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    final bytes = await _controller.toPngBytes();

    if (choice == _SaveChoice.overwrite) {
      await sl<DrawingRepository>().overwrite(widget.existingFilePath!, bytes);
    } else {
      await sl<DrawingRepository>().save(bytes);
    }

    sl<GalleryCubit>().load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drawing saved')),
      );
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear canvas?'),
        content: const Text('This wipes the canvas to white. You can undo it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _editorCubit,
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
              icon: const Icon(Icons.delete_outline),
              onPressed: _clear,
            ),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveWithChoice,
            ),
          ],
        ),
        body: _buildCanvas(),
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
          ],
        );
      },
    );
  }
}

enum _SaveChoice { saveNew, overwrite }