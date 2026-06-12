import 'package:flutter/material.dart';

import 'injection_container.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDependencies();
  runApp(const DoodlingzApp());
}

class DoodlingzApp extends StatelessWidget {
  const DoodlingzApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ThemeMode will be driven by SettingsCubit once the settings layer
    // exists. Hardcoded to system default until then.
    return const MaterialApp(
      title: 'Doodlingz',
      home: Scaffold(
        body: Center(
          child: Text('Doodlingz'),
        ),
      ),
    );
  }
}