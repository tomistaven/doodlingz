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
  static const _showHintsKey = 'show_hints';
  static const _onboardingSeenKey = 'onboarding_seen';

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
        showHints: _prefs.getBool(_showHintsKey) ?? true,
        onboardingSeen: _prefs.getBool(_onboardingSeenKey) ?? false,
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

  void setShowHints({required bool value}) {
    _prefs.setBool(_showHintsKey, value);
    emit(state.copyWith(showHints: value));
  }

  void markOnboardingSeen() {
    _prefs.setBool(_onboardingSeenKey, true);
    emit(state.copyWith(onboardingSeen: true));
  }

  /// Resets the onboarding flag so the overlay shows again on the next editor
  /// visit. Useful for reviewers and users who want to revisit the tutorial.
  void replayOnboarding() {
    _prefs.setBool(_onboardingSeenKey, false);
    emit(state.copyWith(onboardingSeen: false));
  }
}