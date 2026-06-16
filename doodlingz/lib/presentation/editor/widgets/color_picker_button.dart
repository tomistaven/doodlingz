import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/editor_cubit.dart';
import '../cubit/editor_state.dart';

/// A circular color swatch anchored to the left edge of the canvas.
///
/// Positioned half-outside the canvas frame via a Stack in [EditorScreen].
/// Tapping opens a bottom sheet with the full color wheel.
class ColorPickerButton extends StatelessWidget {
  const ColorPickerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EditorCubit, EditorState>(
      builder: (context, state) {
        return GestureDetector(
          onTap: () => _openBottomSheet(context, state.color),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: state.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(2, 2),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openBottomSheet(BuildContext context, Color current) {
    final cubit = context.read<EditorCubit>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: BlocBuilder<EditorCubit, EditorState>(
            builder: (context, state) {
              return ColorPicker(
                color: state.color,
                onColorChanged: cubit.selectColor,
                pickersEnabled: const {
                  ColorPickerType.wheel: true,
                  ColorPickerType.primary: false,
                  ColorPickerType.accent: false,
                },
                enableOpacity: true,
                enableShadesSelection: false,
                showColorCode: true,
                colorCodeHasColor: true,
              );
            },
          ),
        ),
      ),
    );
  }
}