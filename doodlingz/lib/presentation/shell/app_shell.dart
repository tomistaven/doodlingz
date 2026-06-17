import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../injection_container.dart';
import '../editor/cubit/editor_cubit.dart';
import '../editor/cubit/editor_state.dart';
import '../editor/screens/editor_screen.dart';
import '../gallery/screens/gallery_screen.dart';
import '../settings/cubit/settings_cubit.dart';
import '../settings/screens/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.brush_outlined),
      selectedIcon: Icon(Icons.brush),
      label: 'Editor',
    ),
    NavigationDestination(
      icon: Icon(Icons.photo_library_outlined),
      selectedIcon: Icon(Icons.photo_library),
      label: 'Gallery',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: sl<SettingsCubit>(),
      child: BlocProvider.value(
        value: sl<EditorCubit>(),
        child: BlocListener<EditorCubit, EditorState>(
          // Switch to the editor tab whenever a load is requested from outside
          // the editor (gallery viewer, device import). The EditorScreen
          // BlocListener then picks up pendingLoad and applies it to the canvas.
          listenWhen: (previous, current) =>
              current.pendingLoad != null && previous.pendingLoad == null,
          listener: (context, state) {
            setState(() => _currentIndex = 0);
          },
          child: Scaffold(
            body: IndexedStack(
              index: _currentIndex,
              children: const [
                EditorScreen(),
                GalleryScreen(),
                SettingsScreen(),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) =>
                  setState(() => _currentIndex = index),
              destinations: _destinations,
            ),
          ),
        ),
      ),
    );
  }
}