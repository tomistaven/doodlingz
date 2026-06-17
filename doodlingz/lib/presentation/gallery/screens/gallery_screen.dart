import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../domain/entities/saved_drawing.dart';
import '../../../injection_container.dart';
import '../../editor/screens/editor_screen.dart';
import '../cubit/gallery_cubit.dart';
import '../cubit/gallery_state.dart';
import '../widgets/drawing_grid_tile.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with AutomaticKeepAliveClientMixin {
  final _picker = ImagePicker();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    sl<GalleryCubit>().load();
  }

  Future<void> _openDrawing(SavedDrawing drawing) async {
    final cubit = sl<GalleryCubit>();
    final bytes = await cubit.loadBytes(drawing.filePath);

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(
          existingImageBytes: bytes,
          existingFilePath: drawing.filePath,
        ),
      ),
    );

    cubit.load();
  }

  Future<void> _confirmDelete(SavedDrawing drawing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete drawing?'),
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

    if (confirmed == true) {
      sl<GalleryCubit>().delete(drawing.filePath);
    }
  }

  Future<void> _importFromDevice() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(existingImageBytes: bytes),
      ),
    );

    sl<GalleryCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return BlocProvider.value(
      value: sl<GalleryCubit>(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gallery'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              tooltip: 'Import from device',
              onPressed: _importFromDevice,
            ),
          ],
        ),
        body: BlocBuilder<GalleryCubit, GalleryState>(
          builder: (context, state) {
            return switch (state) {
              GalleryLoading() => const Center(
                  child: CircularProgressIndicator(),
                ),
              GalleryError(:final message) => Center(
                  child: Text(
                    'Could not load drawings\n$message',
                    textAlign: TextAlign.center,
                  ),
                ),
              GalleryLoaded(:final drawings) when drawings.isEmpty =>
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.brush_outlined, size: 48),
                      SizedBox(height: 12),
                      Text('No saved drawings yet'),
                    ],
                  ),
                ),
              GalleryLoaded(:final drawings) => GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 3 / 4,
                  ),
                  itemCount: drawings.length,
                  itemBuilder: (_, index) => DrawingGridTile(
                    drawing: drawings[index],
                    onTap: () => _openDrawing(drawings[index]),
                    onDelete: () => _confirmDelete(drawings[index]),
                  ),
                ),
            };
          },
        ),
      ),
    );
  }
}