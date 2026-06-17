import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gal/gal.dart';

import '../../../core/constants/canvas_constants.dart';
import '../../../domain/repositories/drawing_repository.dart';
import '../../../injection_container.dart';
import '../../gallery/cubit/gallery_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../controller/canvas_controller.dart';
import '../cubit/editor_cubit.dart';
import '../cubit/editor_state.dart';
import '../engine/canvas_compositor.dart';
import '../painter/drawing_canvas_painter.dart';
import '../widgets/editor_hub.dart';
import '../widgets/onboarding_overlay.dart';

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
        await _save();
        // _save can itself be cancelled at the bottom sheet; if the canvas
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
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(context).pop(),
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
      await FileImage(File(currentFilePath)).evict();
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
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Clear canvas',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: const Text('Wipes to white. You can undo this.'),
              onTap: () => Navigator.of(context).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );

    if (confirmed ?? false) {
      await _controller.clear();
    }
  }

  Future<void> _export() async {
    final isDirty = _controller.value.isDirty;

    final choice = await showModalBottomSheet<_ExportChoice>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDirty)
              ListTile(
                leading: const Icon(Icons.save),
                title: const Text('Save & export'),
                subtitle: const Text('Saves your drawing, then exports it.'),
                onTap: () =>
                    Navigator.of(context).pop(_ExportChoice.saveAndExport),
              ),
            if (isDirty)
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Export anyway'),
                subtitle: const Text('Exports without saving.'),
                onTap: () =>
                    Navigator.of(context).pop(_ExportChoice.exportOnly),
              ),
            if (!isDirty)
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Export to device gallery'),
                onTap: () =>
                    Navigator.of(context).pop(_ExportChoice.exportOnly),
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(context).pop(_ExportChoice.cancel),
            ),
          ],
        ),
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

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.note_add_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'New drawing',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: Text(
                isDirty
                    ? 'Unsaved changes will be lost.'
                    : 'Clears the canvas and starts fresh.',
              ),
              onTap: () => Navigator.of(context).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
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
            BlocBuilder<SettingsCubit, SettingsState>(
              builder: (context, settings) {
                if (!settings.showHints || settings.onboardingSeen) {
                  return const SizedBox.shrink();
                }
                return const Positioned.fill(child: OnboardingOverlay());
              },
            ),
          ],
        );
      },
    );
  }
}

enum _SaveChoice { saveNew, overwrite }

enum _ExportChoice { cancel, exportOnly, saveAndExport }

enum _EditorMenu { newDrawing, clear }

enum _LoadChoice { cancel, discard, save }