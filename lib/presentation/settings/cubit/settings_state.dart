import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class SettingsState extends Equatable {
  const SettingsState({
    required this.themeMode,
    required this.hubOnRight,
    required this.showTutorialOnStartup,
    required this.pendingTutorial,
  });

  final ThemeMode themeMode;

  /// When true, the editor hub is anchored to the bottom-right corner,
  /// mirroring the layout for left-handed users.
  final bool hubOnRight;

  /// When true, the onboarding overlay shows automatically on every launch.
  final bool showTutorialOnStartup;

  /// Flag used to signal AppShell to navigate to the Editor and trigger the overlay.
  final bool pendingTutorial;

  static SettingsState initial() => const SettingsState(
    themeMode: ThemeMode.system,
    hubOnRight: false,
    showTutorialOnStartup: true,
    pendingTutorial: false,
  );

  SettingsState copyWith({
    ThemeMode? themeMode,
    bool? hubOnRight,
    bool? showTutorialOnStartup,
    bool? pendingTutorial,
  }) => SettingsState(
    themeMode: themeMode ?? this.themeMode,
    hubOnRight: hubOnRight ?? this.hubOnRight,
    showTutorialOnStartup: showTutorialOnStartup ?? this.showTutorialOnStartup,
    pendingTutorial: pendingTutorial ?? this.pendingTutorial,
  );

  @override
  List<Object> get props => [
        themeMode,
        hubOnRight,
        showTutorialOnStartup,
        pendingTutorial,
      ];
}