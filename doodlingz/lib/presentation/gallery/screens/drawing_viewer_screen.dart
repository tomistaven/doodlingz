import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/saved_drawing.dart';
import '../../../injection_container.dart';
import '../../editor/cubit/editor_cubit.dart';
import '../cubit/gallery_cubit.dart';

/// Read-only full-screen view of a single saved drawing.
///
/// Editing is an explicit action: it loads the drawing into the app-scoped
/// EditorCubit and pops back to the shell, which switches to the editor tab.
class DrawingViewerScreen extends StatefulWidget {
  const DrawingViewerScreen({super.key, required this.drawing});

  final SavedDrawing drawing;

  @override
  State<DrawingViewerScreen> createState() => _DrawingViewerScreenState();
}

class _DrawingViewerScreenState extends State<DrawingViewerScreen> {
  static final _dateFormat = DateFormat('dd MMM yyyy  HH:mm');

  late Future<Uint8List> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = sl<GalleryCubit>().loadBytes(widget.drawing.filePath);
  }

  void _edit(Uint8List bytes) {
    sl<EditorCubit>().requestLoad(bytes, widget.drawing.filePath);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
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

    if (confirmed != true) return;

    await sl<GalleryCubit>().delete(widget.drawing.filePath);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_dateFormat.format(widget.drawing.createdAt)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: _delete,
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _bytesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(child: Text('Could not load this drawing'));
          }

          final bytes = snapshot.data!;
          return Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
                child: FloatingActionButton.extended(
                  onPressed: () => _edit(bytes),
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}