import 'dart:io';

import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/saved_drawing.dart';

/// Maps between [File] system metadata and the [SavedDrawing] domain entity.
class SavedDrawingModel {
  const SavedDrawingModel._();

  static final _timestampFormat = DateFormat(AppConstants.timestampPattern);

  /// Constructs a [SavedDrawing] from a PNG [File] on disk.
  ///
  /// The creation timestamp is parsed from the filename rather than relying
  /// on filesystem mtime, which can change on copy or backup restore.
  /// [updatedAt] always reflects the current mtime so overwrites are detected.
  static SavedDrawing fromFile(File file) {
    final name = file.uri.pathSegments.last;
    final id = name.replaceAll('.${AppConstants.fileExtension}', '');
    final timestampStr = id.replaceFirst(AppConstants.filePrefix, '');

    DateTime createdAt;
    try {
      createdAt = _timestampFormat.parse(timestampStr);
    } catch (_) {
      createdAt = file.lastModifiedSync();
    }

    return SavedDrawing(
      id: id,
      filePath: file.path,
      createdAt: createdAt,
      updatedAt: file.lastModifiedSync(),
    );
  }
}
