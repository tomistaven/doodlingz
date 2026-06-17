import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gal/gal.dart';

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
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final CanvasController _controller;

  bool _initRequested = false;

  /// Completes when [CanvasController.initialise] returns.
  /// Load requests that arrive before init finishes await this before
  /// calling [CanvasController.loadImage], preventing a race between the
  /// cold-launch blank creation and an incoming image swap.
  final Completer<void> _initCompleter = Completer<void>();

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
    await _initCompleter.future;
    if (!mounted) return;

    final image = await CanvasCompositor.fromBytes(
      bytes,
      CanvasConstants.portraitCanvasSize,
    );
    if (!mounted) return;

    _controller.loadImage(image);
    if (mounted) {
      context.read<EditorCubit>().acknowledgeLoad(filePath);
    }
  }

  Future<void> _save() async {
    final cubit = context.read<EditorCubit>();
    final currentFilePath = cubit.state.currentFilePath;

    if (currentFilePath == null) {
      await _saveNew(cubit);
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
      await sl<DrawingRepository>().overwrite(currentFilePath, bytes);
      _controller.markSaved();
    } else {
      await _saveNew(cubit, bytes: bytes);
      return;
    }

    sl<GalleryCubit>().load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drawing saved')),
      );
    }
  }

  Future<void> _saveNew(EditorCubit cubit, {Uint8List? bytes}) async {
    final pngBytes = bytes ?? await _controller.toPngBytes();
    final saved = await sl<DrawingRepository>().save(pngBytes);
    _controller.markSaved();
    cubit.notifySaved(saved.filePath);
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

  Future<void> _export() async {
    final isDirty = _controller.value.isDirty;

    final choice = await showDialog<_ExportChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export to gallery?'),
        content: Text(
          isDirty
              ? 'You have unsaved changes. Save before exporting?'
              : 'Export this drawing to your device gallery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_ExportChoice.cancel),
            child: const Text('Cancel'),
          ),
          if (isDirty)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_ExportChoice.exportOnly),
              child: const Text('Export anyway'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              isDirty ? _ExportChoice.saveAndExport : _ExportChoice.exportOnly,
            ),
            child: Text(isDirty ? 'Save & export' : 'Export'),
          ),
        ],
      ),
    );

    if (choice == null || choice == _ExportChoice.cancel) return;

    if (choice == _ExportChoice.saveAndExport) {
      await _save();
      if (_controller.value.isDirty) return;
    }

    await _exportBytes();
  }

  Future<void> _exportBytes() async {
    final bytes = await _controller.toPngBytes();
    const album = 'Doodlingz';

    try {
      await Gal.putImageBytes(bytes, album: album);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exported to gallery')),
        );
      }
    } on GalException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gallery access denied')),
        );
      }
    }
  }

  Future<void> _newDrawing() async {
    final isDirty = _controller.value.isDirty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new drawing?'),
        content: Text(
          isDirty
              ? 'Your current drawing has unsaved changes that will be lost.'
              : 'This clears the canvas and starts fresh.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('New drawing'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await _controller.reset();
      if (mounted) context.read<EditorCubit>().notifyNew();
    }
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
              onPressed: _save,
            ),
            IconButton(
              icon: const Icon(Icons.ios_share),
              onPressed: _export,
            ),
            PopupMenuButton<_EditorMenu>(
              onSelected: (item) {
                switch (item) {
                  case _EditorMenu.newDrawing:
                    _newDrawing();
                  case _EditorMenu.clear:
                    _clear();
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

enum _ExportChoice { cancel, exportOnly, saveAndExport }

enum _EditorMenu { newDrawing, clear }