import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../models/saved_drawing_model.dart';
import '../../domain/entities/saved_drawing.dart';

/// Reads and writes drawing PNG files on the device's local storage.
///
/// All files are kept in a dedicated sub-directory inside the app's
/// documents directory so they are isolated from other app data and
/// easy to enumerate for the gallery.
class LocalDrawingDataSource {
  Directory? _drawingsDir;

  Future<Directory> _getDrawingsDir() async {
    if (_drawingsDir != null) return _drawingsDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/${AppConstants.drawingsFolder}');
    if (!await dir.exists()) await dir.create(recursive: true);
    _drawingsDir = dir;
    return dir;
  }

  Future<SavedDrawing> save(Uint8List pngBytes) async {
    final dir = await _getDrawingsDir();
    final timestamp =
        DateFormat(AppConstants.timestampPattern).format(DateTime.now());
    final file = File('${dir.path}/${AppConstants.fileName(timestamp)}');
    await file.writeAsBytes(pngBytes, flush: true);
    return SavedDrawingModel.fromFile(file);
  }

  Future<SavedDrawing> overwrite(
      String filePath, Uint8List pngBytes) async {
    final file = File(filePath);
    await file.writeAsBytes(pngBytes, flush: true);
    return SavedDrawingModel.fromFile(file);
  }

  Future<List<SavedDrawing>> loadAll() async {
    final dir = await _getDrawingsDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.${AppConstants.fileExtension}'))
        .toList();

    final drawings = files.map(SavedDrawingModel.fromFile).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return drawings;
  }

  Future<Uint8List> loadBytes(String filePath) async {
    final file = File(filePath);
    return file.readAsBytes();
  }

  Future<void> delete(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }
}