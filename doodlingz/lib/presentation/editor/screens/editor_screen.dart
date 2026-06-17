import 'dart:typed_data';
import 'dart:ui' as ui;

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
    _controller.markSaved();

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
    _controller.markSaved();

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
      await _saveWithChoice();
      // _saveWithChoice can be cancelled at its own sheet; if so the drawing
      // is still dirty and we abort rather than export an unsaved drawing.
      if (_controller.value.isDirty) return;
    }

    await _exportBytes();
  }

  Future<void> _exportBytes() async {
    final bytes = await _controller.toPngBytes();

    // Album groups exported drawings together in the device gallery.
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
              icon: const Icon(Icons.save),
              onPressed: _saveWithChoice,
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