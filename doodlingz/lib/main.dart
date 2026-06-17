import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'injection_container.dart';
import 'presentation/settings/cubit/settings_cubit.dart';
import 'presentation/settings/cubit/settings_state.dart';
import 'presentation/shell/app_shell.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDependencies();
  runApp(const DoodlingzApp());
}

/// Root widget. Reads [SettingsCubit] to drive [MaterialApp.themeMode] so
/// the entire app re-themes reactively when the user changes the setting.
class DoodlingzApp extends StatelessWidget {
  const DoodlingzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: sl<SettingsCubit>(),
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, settings) {
          return MaterialApp(
            title: 'Doodlingz',
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: settings.themeMode,
            home: const AppShell(),
          );
        },
      ),
    );
  }
}