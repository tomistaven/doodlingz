import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/datasources/local_drawing_data_source.dart';
import 'data/repositories/drawing_repository_impl.dart';
import 'domain/repositories/drawing_repository.dart';
import 'presentation/gallery/cubit/gallery_cubit.dart';
import 'presentation/settings/cubit/settings_cubit.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // SharedPreferences must be awaited before anything that reads it.
  final prefs = await SharedPreferences.getInstance();
  sl.registerSingleton<SharedPreferences>(prefs);

  // SettingsCubit is a lazy singleton — one instance drives themeMode for
  // the entire app lifetime and is provided above AppShell.
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
}
