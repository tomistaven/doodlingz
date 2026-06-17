import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class SettingsState extends Equatable {
  const SettingsState({
    required this.themeMode,
    required this.hubOnRight,
    required this.showHints,
    required this.onboardingSeen,
  });

  final ThemeMode themeMode;

  /// When true the editor hub is anchored to the bottom-right corner,
  /// mirroring the layout for left-handed users.
  final bool hubOnRight;

  /// When true the editor shows tool tooltips and the first-run overlay.
  final bool showHints;

  /// Tracks whether the first-run onboarding overlay has been dismissed.
  /// Persisted so the overlay only appears once unless explicitly replayed.
  final bool onboardingSeen;

  static SettingsState initial() => const SettingsState(
    themeMode: ThemeMode.system,
    hubOnRight: false,
    showHints: true,
    onboardingSeen: false,
  );

  SettingsState copyWith({
    ThemeMode? themeMode,
    bool? hubOnRight,
    bool? showHints,
    bool? onboardingSeen,
  }) => SettingsState(
    themeMode: themeMode ?? this.themeMode,
    hubOnRight: hubOnRight ?? this.hubOnRight,
    showHints: showHints ?? this.showHints,
    onboardingSeen: onboardingSeen ?? this.onboardingSeen,
  );

  @override
  List<Object> get props => [themeMode, hubOnRight, showHints, onboardingSeen];
}