import 'package:equatable/equatable.dart';

import '../../../../domain/entities/saved_drawing.dart';

sealed class GalleryState extends Equatable {
  const GalleryState();

  @override
  List<Object> get props => [];
}

class GalleryLoading extends GalleryState {
  const GalleryLoading();
}

class GalleryLoaded extends GalleryState {
  const GalleryLoaded(this.drawings);

  final List<SavedDrawing> drawings;

  @override
  List<Object> get props => [drawings];
}

class GalleryError extends GalleryState {
  const GalleryError(this.message);

  final String message;

  @override
  List<Object> get props => [message];
}
