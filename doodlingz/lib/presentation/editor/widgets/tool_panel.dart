import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/drawing_tool.dart';
import '../cubit/editor_cubit.dart';
import '../cubit/editor_state.dart';

class ToolPanel extends StatelessWidget {
  const ToolPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BlocBuilder<EditorCubit, EditorState>(
            builder: (context, state) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: DrawingTool.values.map((tool) {
                    final isSelected = state.tool == tool;
                    return _ToolButton(
                      icon: _iconFor(tool),
                      tooltip: _labelFor(tool),
                      isSelected: isSelected,
                      onTap: () => context.read<EditorCubit>().selectTool(tool),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.outline.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(DrawingTool tool) {
    switch (tool) {
      case DrawingTool.brush:
        return Icons.brush;
      case DrawingTool.highlighter:
        return Icons.edit;
      case DrawingTool.spray:
        return Icons.blur_on;
      case DrawingTool.eraser:
        return Icons.auto_fix_normal;
      case DrawingTool.fill:
        return Icons.format_color_fill;
      case DrawingTool.line:
        return Icons.remove;
      case DrawingTool.rectangle:
        return Icons.crop_square;
      case DrawingTool.ellipse:
        return Icons.circle_outlined;
      case DrawingTool.triangle:
        return Icons.change_history;
    }
  }

  String _labelFor(DrawingTool tool) {
    switch (tool) {
      case DrawingTool.brush:
        return 'Brush';
      case DrawingTool.highlighter:
        return 'Highlighter';
      case DrawingTool.spray:
        return 'Spray';
      case DrawingTool.eraser:
        return 'Eraser';
      case DrawingTool.fill:
        return 'Fill';
      case DrawingTool.line:
        return 'Line';
      case DrawingTool.rectangle:
        return 'Rectangle';
      case DrawingTool.ellipse:
        return 'Ellipse';
      case DrawingTool.triangle:
        return 'Triangle';
    }
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = isSelected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: iconColor, size: 24),
        ),
      ),
    );
  }
}