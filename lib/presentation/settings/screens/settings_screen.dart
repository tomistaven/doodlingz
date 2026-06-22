import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          return ListView(
            children: [
              const _SectionHeader('Appearance'),
              _ThemeOption(
                label: 'System default',
                icon: Icons.brightness_auto,
                selected: state.themeMode == ThemeMode.system,
                onTap: () =>
                    context.read<SettingsCubit>().setTheme(ThemeMode.system),
              ),
              _ThemeOption(
                label: 'Light',
                icon: Icons.light_mode,
                selected: state.themeMode == ThemeMode.light,
                onTap: () =>
                    context.read<SettingsCubit>().setTheme(ThemeMode.light),
              ),
              _ThemeOption(
                label: 'Dark',
                icon: Icons.dark_mode,
                selected: state.themeMode == ThemeMode.dark,
                onTap: () =>
                    context.read<SettingsCubit>().setTheme(ThemeMode.dark),
              ),
              const Divider(),
              const _SectionHeader('Editor'),
              SwitchListTile(
                secondary: const Icon(Icons.swap_horiz),
                title: const Text('Move tool hub to right side'),
                value: state.hubOnRight,
                onChanged: (value) =>
                    context.read<SettingsCubit>().setHubOnRight(value: value),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.lightbulb_outline),
                title: const Text('Show tutorial on startup'),
                subtitle: const Text('Displays the guide when opening the app'),
                value: state.showTutorialOnStartup,
                onChanged: (value) =>
                    context.read<SettingsCubit>().setShowTutorialOnStartup(value: value),
              ),
              ListTile(
                leading: const Icon(Icons.replay),
                title: const Text('Show tutorial again'),
                subtitle: const Text('Opens the guide immediately'),
                onTap: () {
                  context.read<SettingsCubit>().triggerTutorial();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return ListTile(
      leading: Icon(icon, color: selected ? accent : null),
      title: Text(label),
      trailing: selected ? Icon(Icons.check_rounded, color: accent) : null,
      onTap: onTap,
    );
  }
}