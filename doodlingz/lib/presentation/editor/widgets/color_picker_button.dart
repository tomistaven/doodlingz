import 'dart:math' as math;

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/canvas_constants.dart';
import '../cubit/editor_cubit.dart';
import '../cubit/editor_state.dart';

/// A left-edge color handle that springs out an arc of preset swatches.
///
/// Tapping the handle toggles the arc open; the final node opens the full
/// wheel picker for arbitrary colors. The menu opens rightward into the
/// canvas so it stays clear of the screen edge.
class ColorPickerButton extends StatefulWidget {
  const ColorPickerButton({super.key});

  @override
  State<ColorPickerButton> createState() => _ColorPickerButtonState();
}

class _ColorPickerButtonState extends State<ColorPickerButton>
    with SingleTickerProviderStateMixin {
  static const double _handleSize = 44;
  static const double _nodeSize = 36;
  static const double _arcRadius = 96;

  late final AnimationController _controller;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _controller.forward() : _controller.reverse();
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _controller.reverse();
  }

  void _onPresetSelected(Color color) {
    context.read<EditorCubit>().selectColor(color);
    _close();
  }

  void _openCustomPicker() {
    final cubit = context.read<EditorCubit>();
    _close();

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

  @override
  Widget build(BuildContext context) {
    final nodeCount = CanvasConstants.presetColors.length + 1;

    // Nodes fan across a rightward arc. The span is kept under a full
    // semicircle so the top and bottom nodes don't collide with the panel
    // above or the screen edge below.
    const startAngle = -math.pi / 2.4;
    const endAngle = math.pi / 2.4;
    final step = (endAngle - startAngle) / (nodeCount - 1);

    return SizedBox(
      width: _arcRadius + _handleSize,
      height: (_arcRadius + _handleSize) * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < nodeCount; i++)
            _buildNode(i, startAngle + step * i),
          _buildHandle(),
        ],
      ),
    );
  }

  Widget _buildNode(int index, double angle) {
    final isCustom = index == CanvasConstants.presetColors.length;
    final centerY = _arcRadius + _handleSize;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(
          _controller.value.clamp(0.0, 1.0),
        );
        final distance = _arcRadius * t;
        final dx = _handleSize / 2 + math.cos(angle) * distance;
        final dy = math.sin(angle) * distance;

        return Positioned(
          left: dx - _nodeSize / 2,
          top: centerY + dy - _nodeSize / 2,
          child: Opacity(
            opacity: _controller.value.clamp(0.0, 1.0),
            child: IgnorePointer(
              ignoring: !_open,
              child: child,
            ),
          ),
        );
      },
      child: isCustom ? _buildCustomNode() : _buildPresetNode(index),
    );
  }

  Widget _buildPresetNode(int index) {
    final color = CanvasConstants.presetColors[index];
    return GestureDetector(
      onTap: () => _onPresetSelected(color),
      child: Container(
        width: _nodeSize,
        height: _nodeSize,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: _nodeShadow,
        ),
      ),
    );
  }

  Widget _buildCustomNode() {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _openCustomPicker,
      child: Container(
        width: _nodeSize,
        height: _nodeSize,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: colorScheme.outline, width: 1.5),
          boxShadow: _nodeShadow,
        ),
        child: Icon(
          Icons.palette_outlined,
          size: 20,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildHandle() {
    final centerY = _arcRadius + _handleSize;
    return Positioned(
      left: 0,
      top: centerY - _handleSize / 2,
      child: BlocBuilder<EditorCubit, EditorState>(
        builder: (context, state) {
          return GestureDetector(
            onTap: _toggle,
            child: Container(
              width: _handleSize,
              height: _handleSize,
              decoration: BoxDecoration(
                color: state.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: _nodeShadow,
              ),
            ),
          );
        },
      ),
    );
  }

  List<BoxShadow> get _nodeShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 6,
          offset: const Offset(2, 2),
        ),
      ];
}