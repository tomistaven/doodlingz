import 'package:get_it/get_it.dart';

import 'data/datasources/local_drawing_data_source.dart';
import 'data/repositories/drawing_repository_impl.dart';
import 'domain/repositories/drawing_repository.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // Data sources — lazy singletons: one instance shared across the app,
  // created on first use.
  sl.registerLazySingleton<LocalDrawingDataSource>(
    LocalDrawingDataSource.new,
  );

  // Repositories
  sl.registerLazySingleton<DrawingRepository>(
    () => DrawingRepositoryImpl(sl<LocalDrawingDataSource>()),
  );
}