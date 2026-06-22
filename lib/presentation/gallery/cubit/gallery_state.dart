import 'package:equatable/equatable.dart';

import '../../../../domain/entities/saved_drawing.dart';

/// States emitted by [GalleryCubit].
sealed class GalleryState extends Equatable {
  const GalleryState();

  @override
  List<Object> get props => [];
}

/// Emitted while drawings are being loaded from storage.
class GalleryLoading extends GalleryState {
  const GalleryLoading();
}

/// Emitted when drawings have loaded successfully.
/// [drawings] is ordered by creation date descending.
class GalleryLoaded extends GalleryState {
  const GalleryLoaded(this.drawings);

  final List<SavedDrawing> drawings;

  @override
  List<Object> get props => [drawings];
}

/// Emitted when loading or a delete operation fails.
class GalleryError extends GalleryState {
  const GalleryError(this.message);

  final String message;

  @override
  List<Object> get props => [message];
}
