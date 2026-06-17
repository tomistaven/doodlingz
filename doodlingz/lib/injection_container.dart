import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/datasources/local_drawing_data_source.dart';
import 'data/repositories/drawing_repository_impl.dart';
import 'domain/repositories/drawing_repository.dart';
import 'presentation/editor/cubit/editor_cubit.dart';
import 'presentation/gallery/cubit/gallery_cubit.dart';
import 'presentation/settings/cubit/settings_cubit.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // SharedPreferences must be awaited before anything that reads it.
  final prefs = await SharedPreferences.getInstance();
  sl.registerSingleton<SharedPreferences>(prefs);

  sl.registerLazySingleton<SettingsCubit>(
    () => SettingsCubit(sl<SharedPreferences>()),
  );

  sl.registerLazySingleton<LocalDrawingDataSource>(LocalDrawingDataSource.new);

  sl.registerLazySingleton<DrawingRepository>(
    () => DrawingRepositoryImpl(sl<LocalDrawingDataSource>()),
  );

  sl.registerLazySingleton<GalleryCubit>(
    () => GalleryCubit(sl<DrawingRepository>()),
  );

  // App-scoped so gallery and viewer can trigger loads into the editor tab
  // without pushing a second EditorScreen onto the navigator stack.
  sl.registerLazySingleton<EditorCubit>(EditorCubit.new);
}