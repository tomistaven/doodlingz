import 'dart:typed_data';

import '../entities/saved_drawing.dart';

/// Contract for persisting and retrieving drawings from local storage.
///
/// The data layer provides the implementation; cubits depend only on this
/// interface via dependency injection.
abstract class DrawingRepository {
  /// Saves raw PNG bytes to local storage.
  ///
  /// Returns the created [SavedDrawing] metadata on success.
  Future<SavedDrawing> save(Uint8List pngBytes);

  /// Overwrites an existing file at [filePath] with new PNG bytes.
  ///
  /// Used by the editor's save-as-same-file flow.
  Future<SavedDrawing> overwrite(String filePath, Uint8List pngBytes);

  /// Returns all saved drawings ordered by [SavedDrawing.createdAt] descending.
  Future<List<SavedDrawing>> loadAll();

  /// Reads the raw PNG bytes for a single drawing by its file path.
  ///
  /// Used when opening a saved drawing for editing.
  Future<Uint8List> loadBytes(String filePath);

  /// Permanently deletes the file at [filePath].
  Future<void> delete(String filePath);
}