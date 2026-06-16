import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/canvas_constants.dart';
import '../../../domain/entities/drawing_tool.dart';
import 'editor_state.dart';

class EditorCubit extends Cubit<EditorState> {
  EditorCubit() : super(EditorState.initial());

  void selectTool(DrawingTool tool) {
    emit(state.copyWith(tool: tool, strokeSize: _defaultSize(tool)));
  }

  void selectColor(Color color) {
    emit(state.copyWith(color: color));
  }

  void selectSize(double size) {
    emit(state.copyWith(strokeSize: size));
  }

  // Each tool family has a sensible default so switching tools immediately
  // produces an unsurprising mark without the user touching the size selector.
  static double _defaultSize(DrawingTool tool) {
    switch (tool) {
      case DrawingTool.spray:
        return CanvasConstants.spraySizes[0];
      case DrawingTool.eraser:
        return CanvasConstants.brushSizes[2];
      case DrawingTool.line:
      case DrawingTool.rectangle:
      case DrawingTool.ellipse:
      case DrawingTool.triangle:
        return CanvasConstants.shapeOutlineWidths[0];
      default:
        return CanvasConstants.brushSizes[1];
    }
  }
}