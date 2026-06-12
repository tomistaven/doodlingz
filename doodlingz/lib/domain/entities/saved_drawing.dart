import 'package:equatable/equatable.dart';

/// Metadata for a saved drawing as it appears in the gallery.
///
/// Does not hold pixel data — only the information needed to display
/// a gallery tile and locate the file for loading or deletion.
class SavedDrawing extends Equatable {
  const SavedDrawing({
    required this.id,
    required this.filePath,
    required this.createdAt,
  });

  /// Filename without extension — doubles as a stable unique identifier
  /// derived from the creation timestamp.
  final String id;

  /// Absolute path to the PNG file on device storage.
  final String filePath;

  /// Parsed from the filename timestamp; used for gallery sort order.
  final DateTime createdAt;

  @override
  List<Object> get props => [id, filePath, createdAt];
}