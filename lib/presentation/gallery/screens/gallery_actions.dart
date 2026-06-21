import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../injection_container.dart';
import '../../editor/cubit/editor_cubit.dart';
import '../cubit/gallery_cubit.dart';
import 'gallery_screen.dart';

/// Action methods for [GalleryScreen].
///
/// Extracted to keep [GalleryScreen] focused on state management and the
/// widget tree. All methods here are async flows that show dialogs or
/// interact with device APIs.
mixin GalleryActions on State<GalleryScreen> {
  Set<String>? get selected;
  void exitSelection();

  final _picker = ImagePicker();

  Future<void> deleteSelected() async {
    final paths = selected!.toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete ${paths.length} drawing${paths.length == 1 ? '' : 's'}?',
        ),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    exitSelection();
    await sl<GalleryCubit>().deleteMany(paths);
  }

  Future<void> importFromDevice() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    sl<EditorCubit>().requestLoad(bytes, null);
  }
}