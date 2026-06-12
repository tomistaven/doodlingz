import 'dart:typed_data';

import '../../domain/entities/saved_drawing.dart';
import '../../domain/repositories/drawing_repository.dart';
import '../datasources/local_drawing_data_source.dart';

/// Implements [DrawingRepository] by delegating to [LocalDrawingDataSource].
///
/// Exists as a separate class so the domain interface and the disk I/O
/// concern stay decoupled — the data source can be swapped or mocked
/// without touching the interface.
class DrawingRepositoryImpl implements DrawingRepository {
  const DrawingRepositoryImpl(this._dataSource);

  final LocalDrawingDataSource _dataSource;

  @override
  Future<SavedDrawing> save(Uint8List pngBytes) =>
      _dataSource.save(pngBytes);

  @override
  Future<SavedDrawing> overwrite(String filePath, Uint8List pngBytes) =>
      _dataSource.overwrite(filePath, pngBytes);

  @override
  Future<List<SavedDrawing>> loadAll() => _dataSource.loadAll();

  @override
  Future<Uint8List> loadBytes(String filePath) =>
      _dataSource.loadBytes(filePath);

  @override
  Future<void> delete(String filePath) => _dataSource.delete(filePath);
}