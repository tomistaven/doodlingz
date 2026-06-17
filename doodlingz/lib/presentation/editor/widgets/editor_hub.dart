import 'dart:math' as math;

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/canvas_constants.dart';
import '../../../domain/entities/drawing_tool.dart';
import '../cubit/editor_cubit.dart';
import '../cubit/editor_state.dart';

enum _HubLevel { root, tools, colors }

/// Bottom-left floating control hub for the editor.
class EditorHub extends StatefulWidget {
  const EditorHub({super.key});

  @override
  State<EditorHub> createState() => _EditorHubState();
}

class _EditorHubState extends State<EditorHub>
    with SingleTickerProviderStateMixin {
  static const double _handleSize = 64;
  static const double _nodeSize = 44;
  static const double _baseMargin = 24;

  late final AnimationController _controller;
  bool _open = false;
  _HubLevel _level = _HubLevel.root;

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

  void _onHandleTap() {
    if (!_open) {
      setState(() {
        _open = true;
        _level = _HubLevel.root;
      });
      _controller.forward(from: 0);
    } else if (_level != _HubLevel.root) {
      setState(() => _level = _HubLevel.root);
      _controller.forward(from: 0);
    } else {
      _close();
    }
  }

  void _close() {
    setState(() => _open = false);
    _controller.reverse();
  }

  void _goTo(_HubLevel level) {
    setState(() => _level = level);
    _controller.forward(from: 0);
  }

  void _selectTool(DrawingTool tool) {
    context.read<EditorCubit>().selectTool(tool);
    _close();
  }

  void _selectColor(Color color) {
    context.read<EditorCubit>().selectColor(color);
    _close();
  }

  void _openCustomPicker() {
    final cubit = context.read<EditorCubit>();
    _close();

    showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: Dialog(
          // opacity to match your handle
          backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.00),
          // Remove the shadow so the transparency is perfectly clean
          elevation: 0, 
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: BlocBuilder<EditorCubit, EditorState>(
              builder: (context, state) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ColorPicker(
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
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          shape: const StadiumBorder(), 
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28, 
                            vertical: 12,
                          ),
                          elevation: 2, 
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Dynamically pad both bottom AND left so it never covers the system nav bar,
    // regardless of whether the phone is in portrait or landscape orientation.
    final padding = MediaQuery.paddingOf(context);
    final handleBottom = _baseMargin + padding.bottom;
    final handleLeft = _baseMargin + padding.left;

    final handleCentreX = handleLeft + _handleSize / 2;
    final handleCentreY = handleBottom + _handleSize / 2;

    return BlocBuilder<EditorCubit, EditorState>(
      builder: (context, state) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final showArc = _open || _controller.value > 0;
            return Stack(
              children: [
                if (_open)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _close,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                if (showArc)
                  ..._buildArcNodes(
                    state: state,
                    cx: handleCentreX,
                    cy: handleCentreY,
                  ),
                _buildHandle(
                  state: state,
                  left: handleLeft,
                  bottom: handleBottom,
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Widget> _buildArcNodes({
    required EditorState state,
    required double cx,
    required double cy,
  }) {
    final nodes = _nodeContentsForLevel(state);
    final count = nodes.length;
    final t = Curves.easeOutBack.transform(_controller.value.clamp(0.0, 1.0));
    final opacity = _controller.value.clamp(0.0, 1.0);

    return [
      for (var i = 0; i < count; i++)
        _positionNode(
          index: i,
          count: count,
          t: t,
          opacity: opacity,
          cx: cx,
          cy: cy,
          child: nodes[i],
        ),
    ];
  }

  Widget _positionNode({
    required int index,
    required int count,
    required double t,
    required double opacity,
    required double cx,
    required double cy,
    required Widget child,
  }) {
    // If more than 5 items, use two rows.
    final bool useTwoRows = count > 5;
    final int innerCount = useTwoRows ? (count / 2).floor() : count;
    final bool isOuter = index >= innerCount;

    final int rowCount = isOuter ? (count - innerCount) : innerCount;
    final int rowIndex = isOuter ? index - innerCount : index;

    // Outer ring sits further out to give breathing room
    final double targetRadius = useTwoRows ? (isOuter ? 190.0 : 105.0) : 115.0;
    final double distance = targetRadius * t;

    // Define the safe fanning area (5 degrees to 85 degrees)
    const double minAngle = math.pi / 36;
    const double maxAngle = 17 * math.pi / 36;
    const double availableSweep = maxAngle - minAngle;

    double actualStep;
    double startAngle;

    if (count == 2) {
      // FIX: Custom spread for the 2-item Root menu.
      // Places them at 15 degrees and 75 degrees so they anchor the quadrant.
      actualStep = math.pi / 3; // 60 degrees apart
      startAngle = math.pi / 12; // Start at 15 degrees
    } else if (rowCount == 1) {
      actualStep = 0;
      startAngle = math.pi / 4; // Dead center
    } else {
      // Fan out evenly across the available sweep
      actualStep = availableSweep / (rowCount - 1);
      startAngle = minAngle;
    }

    final double angle = startAngle + (rowIndex * actualStep);
    final rx = math.cos(angle) * distance;
    final uy = math.sin(angle) * distance;

    return Positioned(
      left: cx + rx - _nodeSize / 2,
      bottom: cy + uy - _nodeSize / 2,
      child: Opacity(
        opacity: opacity,
        child: IgnorePointer(ignoring: !_open, child: child),
      ),
    );
  }

  List<Widget> _nodeContentsForLevel(EditorState state) {
    switch (_level) {
      case _HubLevel.root:
        return [
          _categoryNode(
            icon: Icons.draw,
            onTap: () => _goTo(_HubLevel.tools),
          ),
          _colorCategoryNode(state.color),
        ];
      case _HubLevel.tools:
        return DrawingTool.values
            .map((tool) => _toolNode(tool, state.tool == tool))
            .toList();
      case _HubLevel.colors:
        return [
          ...CanvasConstants.presetColors.map(
            (color) => _swatchNode(color, state.color == color),
          ),
          _customNode(),
        ];
    }
  }

  Widget _categoryNode({required IconData icon, required VoidCallback onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return _circle(
      onTap: onTap,
      color: const Color(0xFF242424),
      borderColor: colorScheme.outline,
      child: Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 22),
    );
  }

  Widget _colorCategoryNode(Color current) {
    final iconColor =
        current.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

    return _circle(
      onTap: () => _goTo(_HubLevel.colors),
      color: current,
      borderColor: Colors.white.withValues(alpha: 0.85),
      child: Icon(Icons.palette, color: iconColor, size: 22),
    );
  }

  Widget _toolNode(DrawingTool tool, bool isSelected) {
    final colorScheme = Theme.of(context).colorScheme;
    return _circle(
      onTap: () => _selectTool(tool),
      color: const Color(0xFF242424),
      borderColor: isSelected ? colorScheme.primary : colorScheme.outline,
      borderWidth: isSelected ? 3 : 1.5,
      child: Icon(
        _iconFor(tool),
        color: isSelected ? colorScheme.primary : Colors.white,
        size: 22,
      ),
    );
  }

  Widget _swatchNode(Color color, bool isSelected) {
    final colorScheme = Theme.of(context).colorScheme;
    return _circle(
      onTap: () => _selectColor(color),
      color: color,
      borderColor: isSelected
          ? colorScheme.primary
          : colorScheme.outline.withValues(alpha: 0.5),
      borderWidth: isSelected ? 3 : 1.5,
    );
  }

  Widget _customNode() {
    final colorScheme = Theme.of(context).colorScheme;
    return _circle(
      onTap: _openCustomPicker,
      color: colorScheme.surface,
      borderColor: colorScheme.outline,
      child: Icon(
        Icons.palette_outlined,
        size: 20,
        color: colorScheme.onSurface,
      ),
    );
  }

  Widget _circle({
    required VoidCallback onTap,
    required Color color,
    required Color borderColor,
    double borderWidth = 1.5,
    Widget? child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _nodeSize,
        height: _nodeSize,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: _shadow,
        ),
        child: child == null ? null : Center(child: child),
      ),
    );
  }

  Widget _buildHandle({
    required EditorState state,
    required double left,
    required double bottom,
  }) {
    return Positioned(
      left: left,
      bottom: bottom,
      child: GestureDetector(
        onTap: _onHandleTap,
        child: Container(
          width: _handleSize,
          height: _handleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: state.color, width: 4),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, _open ? 0.35 : 0.15),
                blurRadius: _open ? 10 : 4,
                spreadRadius: _open ? 1 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: AnimatedOpacity(
            opacity: _open ? 1.0 : 0.15,
            duration: const Duration(milliseconds: 150),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF242424),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  _handleIcon(state.tool),
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _handleIcon(DrawingTool tool) {
    if (_open) {
      return _level == _HubLevel.root ? Icons.close : Icons.arrow_back;
    }
    return _iconFor(tool);
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

  static const List<BoxShadow> _shadow = [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 6,
      offset: Offset(2, 2),
    ),
  ];
}