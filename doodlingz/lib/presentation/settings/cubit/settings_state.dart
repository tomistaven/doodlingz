import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class SettingsState extends Equatable {
  const SettingsState({
    required this.themeMode,
    required this.hubOnRight,
  });

  final ThemeMode themeMode;

  /// When true the editor hub is anchored to the bottom-right corner,
  /// mirroring the layout for left-handed users.
  final bool hubOnRight;

  static SettingsState initial() => const SettingsState(
        themeMode: ThemeMode.system,
        hubOnRight: false,
      );

  SettingsState copyWith({ThemeMode? themeMode, bool? hubOnRight}) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        hubOnRight: hubOnRight ?? this.hubOnRight,
      );

  @override
  List<Object> get props => [themeMode, hubOnRight];
}