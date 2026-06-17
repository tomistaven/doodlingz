import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/repositories/drawing_repository.dart';
import 'gallery_state.dart';

class GalleryCubit extends Cubit<GalleryState> {
  GalleryCubit(this._repository) : super(const GalleryLoading());

  final DrawingRepository _repository;

  Future<void> load() async {
    emit(const GalleryLoading());
    try {
      final drawings = await _repository.loadAll();
      emit(GalleryLoaded(drawings));
    } catch (e) {
      emit(GalleryError(e.toString()));
    }
  }

  Future<void> delete(String filePath) async {
    try {
      await _repository.delete(filePath);
      await load();
    } catch (e) {
      emit(GalleryError(e.toString()));
    }
  }

  Future<void> deleteMany(List<String> filePaths) async {
    try {
      for (final path in filePaths) {
        await _repository.delete(path);
      }
      await load();
    } catch (e) {
      emit(GalleryError(e.toString()));
    }
  }

  Future<Uint8List> loadBytes(String filePath) =>
      _repository.loadBytes(filePath);
}