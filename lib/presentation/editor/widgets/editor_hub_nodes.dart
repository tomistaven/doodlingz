import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../domain/entities/drawing_tool.dart';
import '../cubit/editor_cubit.dart';
import '../cubit/editor_state.dart';
import 'editor_hub.dart';

/// Node-builder methods for [EditorHub].
///
/// Extracted to keep [EditorHub]'s main file focused on arc geometry,
/// animation, and positioning. The mixin contract exposes the hub state
/// and action callbacks that node builders need.
mixin HubNodes on State<EditorHub> {
  bool get hubOpen;
  HubLevel get hubLevel;
  void closeHub();
  void goTo(HubLevel level);
  void selectTool(DrawingTool tool);
  void selectColor(Color color);
  void selectSize(double size);
  void toggleGridVisible(bool visible);
  void selectGridCellSize(double cellSize);
  void togglePixelArtMode(bool enabled);
  void toggleMirrorMode(bool enabled);

  void openCustomPicker() {
    final cubit = context.read<EditorCubit>();
    closeHub();

    showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: Dialog(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surface.withValues(alpha: 0.00),
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
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
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

  Widget buildCategoryNode({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    bool selected = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: buildCircle(
        onTap: onTap,
        color: UiConstants.hubSurface,
        borderColor: selected ? colorScheme.primary : colorScheme.outline,
        borderWidth: selected ? 3 : 1.5,
        child: Icon(
          icon,
          color: selected
              ? colorScheme.primary
              : Colors.white.withValues(alpha: UiConstants.hubIconOpacity),
          size: 22,
        ),
      ),
    );
  }

  Widget buildColorCategoryNode(Color current) {
    final iconColor = current.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white;
    return Tooltip(
      message: 'Colour',
      preferBelow: false,
      child: buildCircle(
        onTap: () => goTo(HubLevel.colors),
        color: current,
        borderColor: Colors.white.withValues(
          alpha: UiConstants.hubColorNodeBorderOpacity,
        ),
        child: Icon(Icons.palette, color: iconColor, size: 22),
      ),
    );
  }

  Widget buildToolNode(DrawingTool tool, bool isSelected) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: labelFor(tool),
      preferBelow: false,
      child: buildCircle(
        onTap: () => selectTool(tool),
        color: UiConstants.hubSurface,
        borderColor: isSelected ? colorScheme.primary : colorScheme.outline,
        borderWidth: isSelected ? 3 : 1.5,
        child: Icon(
          iconFor(tool),
          color: isSelected ? colorScheme.primary : Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget buildSwatchNode(Color color, bool isSelected) {
    final colorScheme = Theme.of(context).colorScheme;
    return buildCircle(
      onTap: () => selectColor(color),
      color: color,
      borderColor: isSelected
          ? colorScheme.primary
          : colorScheme.outline.withValues(alpha: 0.5),
      borderWidth: isSelected ? 3 : 1.5,
    );
  }

  Widget buildCustomNode() {
    final colorScheme = Theme.of(context).colorScheme;
    return buildCircle(
      onTap: openCustomPicker,
      color: colorScheme.surface,
      borderColor: colorScheme.outline,
      child: Icon(
        Icons.palette_outlined,
        size: 20,
        color: colorScheme.onSurface,
      ),
    );
  }

  Widget buildSizeNode(double size, List<double> allSizes, double currentSize) {
    final isSelected = size == currentSize;
    final colorScheme = Theme.of(context).colorScheme;
    final maxSize = allSizes.reduce((a, b) => a > b ? a : b);
    final dotRadius = 4.0 + (size / maxSize) * 12.0;

    return buildCircle(
      onTap: () => selectSize(size),
      color: UiConstants.hubSurface,
      borderColor: isSelected ? colorScheme.primary : colorScheme.outline,
      borderWidth: isSelected ? 3 : 1.5,
      child: Container(
        width: dotRadius * 2,
        height: dotRadius * 2,
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget buildGridToggleNode(bool visible) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: visible ? 'Hide grid' : 'Show grid',
      preferBelow: false,
      child: buildCircle(
        onTap: () => toggleGridVisible(!visible),
        color: UiConstants.hubSurface,
        borderColor: visible ? colorScheme.primary : colorScheme.outline,
        borderWidth: visible ? 3 : 1.5,
        child: Icon(
          Icons.grid_on,
          color: visible ? colorScheme.primary : Colors.white,
          size: 22,
        ),
      ),
    );
  }

  /// Same visual shape as [buildSizeNode] but calling [selectGridCellSize]
  /// rather than [selectSize] — a dedicated node so grid cell selection can
  /// never be misrouted into changing the active tool's stroke size.
  Widget buildGridCellSizeNode(
    double cellSize,
    List<double> allSizes,
    double currentCellSize,
  ) {
    final isSelected = cellSize == currentCellSize;
    final colorScheme = Theme.of(context).colorScheme;
    final maxSize = allSizes.reduce((a, b) => a > b ? a : b);
    final dotRadius = 4.0 + (cellSize / maxSize) * 12.0;

    return buildCircle(
      onTap: () => selectGridCellSize(cellSize),
      color: UiConstants.hubSurface,
      borderColor: isSelected ? colorScheme.primary : colorScheme.outline,
      borderWidth: isSelected ? 3 : 1.5,
      child: Container(
        width: dotRadius * 2,
        height: dotRadius * 2,
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  /// Renders a hub node, circular by default. Reads pixel art mode directly
  /// via [context.watch] rather than taking a parameter, so every one of this
  /// mixin's ~8 node builders gets the shape change for free — a mode this
  /// visible should be a single universal switch, not a flag threaded through
  /// every call site with room for one to be missed.
  Widget buildCircle({
    required VoidCallback onTap,
    required Color color,
    required Color borderColor,
    double borderWidth = 1.5,
    Widget? child,
  }) {
    final pixelArt = context.watch<EditorCubit>().state.pixelArtMode;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: UiConstants.hubNodeSize,
        height: UiConstants.hubNodeSize,
        decoration: BoxDecoration(
          color: color,
          shape: pixelArt ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: pixelArt
              ? BorderRadius.circular(UiConstants.hubPixelArtNodeRadius)
              : null,
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: hubNodeShadow,
        ),
        child: child == null ? null : Center(child: child),
      ),
    );
  }

  IconData handleIcon(DrawingTool tool) {
    if (hubOpen) {
      return hubLevel == HubLevel.root ? Icons.close : Icons.arrow_back;
    }
    return iconFor(tool);
  }

  IconData iconFor(DrawingTool tool) {
    switch (tool) {
      case DrawingTool.brush:
        return Icons.brush;
      case DrawingTool.highlighter:
        return Symbols.format_ink_highlighter;
      case DrawingTool.spray:
        return Icons.grain;
      case DrawingTool.eraser:
        return Symbols.ink_eraser;
      case DrawingTool.fill:
        return Icons.format_color_fill;
      case DrawingTool.line:
        return Icons.horizontal_rule;
      case DrawingTool.rectangle:
        return Icons.crop_square;
      case DrawingTool.ellipse:
        return Icons.circle_outlined;
      case DrawingTool.triangle:
        return Icons.change_history;
    }
  }

  String labelFor(DrawingTool tool) {
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

  static const List<BoxShadow> hubNodeShadow = [
    BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(2, 2)),
  ];
}