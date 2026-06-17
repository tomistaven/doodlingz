import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../domain/entities/saved_drawing.dart';
import '../../../injection_container.dart';
import '../../editor/cubit/editor_cubit.dart';
import '../cubit/gallery_cubit.dart';
import '../cubit/gallery_state.dart';
import '../widgets/drawing_grid_tile.dart';
import 'drawing_viewer_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with AutomaticKeepAliveClientMixin {
  final _picker = ImagePicker();

  /// Null when not in selection mode; non-null (possibly empty) when active.
  Set<String>? _selected;

  bool get _selecting => _selected != null;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    sl<GalleryCubit>().load();
  }

  void _enterSelection(String firstPath) {
    setState(() => _selected = {firstPath});
  }

  void _exitSelection() {
    setState(() => _selected = null);
  }

  void _toggleSelection(String filePath) {
    setState(() {
      if (_selected!.contains(filePath)) {
        _selected!.remove(filePath);
      } else {
        _selected!.add(filePath);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final paths = _selected!.toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${paths.length} drawing${paths.length == 1 ? '' : 's'}?'),
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

    _exitSelection();
    await sl<GalleryCubit>().deleteMany(paths);
  }

  Future<void> _openDrawing(SavedDrawing drawing) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DrawingViewerScreen(drawing: drawing),
      ),
    );

    sl<GalleryCubit>().load();
  }

  Future<void> _importFromDevice() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    sl<EditorCubit>().requestLoad(bytes, null);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return BlocProvider.value(
      value: sl<GalleryCubit>(),
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelection,
                ),
                title: Text(
                  '${_selected!.length} selected',
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete selected',
                    onPressed:
                        _selected!.isEmpty ? null : _deleteSelected,
                  ),
                ],
              )
            : AppBar(
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
                  itemBuilder: (_, index) {
                    final drawing = drawings[index];
                    final isSelected =
                        _selected?.contains(drawing.filePath) ?? false;
                    return DrawingGridTile(
                      drawing: drawing,
                      isSelected: isSelected,
                      onTap: _selecting
                          ? () => _toggleSelection(drawing.filePath)
                          : () => _openDrawing(drawing),
                      onLongPress: _selecting
                          ? () => _toggleSelection(drawing.filePath)
                          : () => _enterSelection(drawing.filePath),
                    );
                  },
                ),
            };
          },
        ),
      ),
    );
  }
}