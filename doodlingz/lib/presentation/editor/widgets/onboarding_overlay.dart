import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../settings/cubit/settings_cubit.dart';

/// Full-screen onboarding overlay shown on first editor launch.
///
/// Visibility is gated externally — callers only mount this widget when
/// [SettingsState.showHints] is true and [SettingsState.onboardingSeen] is
/// false. The overlay fades out on dismiss and calls [markOnboardingSeen]
/// once the animation completes.
class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({super.key});

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  bool _visible = true;

  void _dismiss() {
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 320),
      onEnd: () {
        if (!_visible && mounted) {
          context.read<SettingsCubit>().markOnboardingSeen();
        }
      },
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Material(
              color: const Color(0xFF242424),
              borderRadius: BorderRadius.circular(16),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome to Doodlingz',
                      style: textTheme.titleLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _HintRow(
                      icon: Icons.circle_outlined,
                      text: 'Tap the hub button to open the tool menu.',
                    ),
                    _HintRow(
                      icon: Icons.draw_outlined,
                      text: 'Tap the tool icon to browse and switch tools.',
                    ),
                    _HintRow(
                      icon: Icons.palette_outlined,
                      text: 'Tap the colour icon to pick a colour or open the '
                          'wheel.',
                    ),
                    _HintRow(
                      icon: Icons.line_weight,
                      text: 'Tap the size icon to change brush or stroke '
                          'width.',
                    ),
                    _HintRow(
                      icon: Icons.undo,
                      text: 'Use Undo and Redo in the toolbar at the top.',
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _dismiss,
                        child: const Text('Got it'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.white70),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}