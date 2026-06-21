import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gal/gal.dart';

import '../../../domain/repositories/drawing_repository.dart';
import '../../../injection_container.dart';
import '../../gallery/cubit/gallery_cubit.dart';
import '../controller/canvas_controller.dart';
import '../cubit/editor_cubit.dart';
import 'editor_screen.dart';

/// Canvas action methods for [EditorScreen].
///
/// Extracted to keep [EditorScreen] focused on canvas initialisation, load
/// handling, and the widget tree. All methods here are async prompt flows
/// that show bottom sheets or dialogs and then mutate the canvas or storage.
mixin EditorActions on State<EditorScreen> {
  CanvasController get controller;

  Future<void> save() async {
    final cubit = context.read<EditorCubit>();
    final currentFilePath = cubit.state.currentFilePath;

    if (currentFilePath == null) {
      await saveNew(cubit);
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

    final bytes = await controller.toPngBytes();

    if (choice == _SaveChoice.overwrite) {
      await sl<DrawingRepository>().overwrite(currentFilePath, bytes);
      controller.markSaved();
      await FileImage(File(currentFilePath)).evict();
    } else {
      await saveNew(cubit, bytes: bytes);
      return;
    }

    sl<GalleryCubit>().load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drawing saved')),
      );
    }
  }

  Future<void> saveNew(EditorCubit cubit, {Uint8List? bytes}) async {
    final pngBytes = bytes ?? await controller.toPngBytes();
    final saved = await sl<DrawingRepository>().save(pngBytes);
    controller.markSaved();
    cubit.notifySaved(saved.filePath);
    sl<GalleryCubit>().load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drawing saved')),
      );
    }
  }

  Future<void> clear() async {
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
      await controller.clear();
    }
  }

  Future<void> export() async {
    final isDirty = controller.value.isDirty;

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
                leading: const Icon(Icons.save_alt),
                title: const Text('Export anyway'),
                subtitle: const Text('Exports without saving.'),
                onTap: () =>
                    Navigator.of(context).pop(_ExportChoice.exportOnly),
              ),
            if (!isDirty)
              ListTile(
                leading: const Icon(Icons.save_alt),
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
      await save();
      if (controller.value.isDirty) return;
    }

    await _exportBytes();
  }

  Future<void> _exportBytes() async {
    final bytes = await controller.toPngBytes();
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

  Future<void> newDrawing() async {
    final isDirty = controller.value.isDirty;

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
      await controller.reset();
      if (mounted) context.read<EditorCubit>().notifyNew();
    }
  }
}

enum _SaveChoice { saveNew, overwrite }

enum _ExportChoice { cancel, exportOnly, saveAndExport }