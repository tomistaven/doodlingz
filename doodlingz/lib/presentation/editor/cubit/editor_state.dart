import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/canvas_constants.dart';
import '../../../domain/entities/drawing_tool.dart';

class EditorState extends Equatable {
  const EditorState({
    required this.tool,
    required this.color,
    required this.strokeSize,
  });

  final DrawingTool tool;
  final Color color;

  /// Brush, shape-outline, or spray radius — in raster pixels.
  final double strokeSize;

  static EditorState initial() => EditorState(
    tool: DrawingTool.brush,
    color: CanvasConstants.defaultToolColor,
    strokeSize: CanvasConstants.brushSizes[1],
  );

  EditorState copyWith({DrawingTool? tool, Color? color, double? strokeSize}) =>
      EditorState(
        tool: tool ?? this.tool,
        color: color ?? this.color,
        strokeSize: strokeSize ?? this.strokeSize,
      );

  @override
  List<Object> get props => [tool, color, strokeSize];
}
