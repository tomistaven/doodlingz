import 'dart:typed_data';

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

  /// Signals that a drawing should be loaded into the canvas.
  ///
  /// Sets [EditorState.pendingLoad] so [EditorScreen] can react via
  /// BlocListener and apply the bytes to [CanvasController]. The cubit
  /// never touches the controller directly.
  void requestLoad(Uint8List bytes, String? filePath) {
    emit(state.copyWith(pendingLoad: (bytes: bytes, filePath: filePath)));
  }

  /// Called by [EditorScreen] once the controller has consumed the pending load.
  /// Records the active file path and clears the pending signal.
  void acknowledgeLoad(String? filePath) {
    emit(
      state.copyWith(
        clearPendingLoad: true,
        clearFilePath: filePath == null,
        currentFilePath: filePath,
      ),
    );
  }

  /// Clears file path and any pending load — used when starting a new drawing.
  void notifyNew() {
    emit(state.copyWith(clearFilePath: true, clearPendingLoad: true));
  }

  /// Updates the current file path after a save-as-new operation so the next
  /// save can offer the overwrite option against the correct file.
  void notifySaved(String filePath) {
    emit(state.copyWith(currentFilePath: filePath));
  }

  /// Cancels a pending load without touching [currentFilePath].
  /// Called when the user dismisses the dirty-canvas confirm dialog.
  void cancelLoad() {
    emit(state.copyWith(clearPendingLoad: true));
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
