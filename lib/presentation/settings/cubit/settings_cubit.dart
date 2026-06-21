import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._prefs) : super(SettingsState.initial()) {
    _loadAll();
  }

  final SharedPreferences _prefs;

  static const _themeKey = 'theme_mode';
  static const _hubOnRightKey = 'hub_on_right';
  static const _showTutorialKey = 'show_tutorial_on_startup';

  void _loadAll() {
    final stored = _prefs.getString(_themeKey);
    final mode = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    emit(
      state.copyWith(
        themeMode: mode,
        hubOnRight: _prefs.getBool(_hubOnRightKey) ?? false,
        showTutorialOnStartup: _prefs.getBool(_showTutorialKey) ?? true,
        pendingTutorial: false,
      ),
    );
  }

  void setTheme(ThemeMode mode) {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    _prefs.setString(_themeKey, value);
    emit(state.copyWith(themeMode: mode));
  }

  void setHubOnRight({required bool value}) {
    _prefs.setBool(_hubOnRightKey, value);
    emit(state.copyWith(hubOnRight: value));
  }

  void setShowTutorialOnStartup({required bool value}) {
    _prefs.setBool(_showTutorialKey, value);
    emit(state.copyWith(showTutorialOnStartup: value));
  }

  /// Fires a signal that AppShell picks up to switch tabs and show the overlay.
  void triggerTutorial() {
    emit(state.copyWith(pendingTutorial: true));
  }

  /// Clears the signal after AppShell has processed it.
  void clearPendingTutorial() {
    emit(state.copyWith(pendingTutorial: false));
  }
}