import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/canvas_constants.dart';
import '../../../domain/entities/drawing_tool.dart';

class EditorState extends Equatable {
  const EditorState({
    required this.tool,
    required this.color,
    required this.strokeSize,
    this.currentFilePath,
    this.pendingLoad,
    this.gridVisible = false,
    this.gridCellSize = CanvasConstants.defaultGridCellSize,
    this.pixelArtMode = false,
    this.mirrorMode = false,
  });

  final DrawingTool tool;
  final Color color;

  /// Brush, shape-outline, or spray radius — in raster pixels.
  final double strokeSize;

  /// File path of the drawing currently loaded in the editor.
  /// Null when the canvas holds an unsaved new drawing.
  final String? currentFilePath;

  /// Non-null when a load has been requested but not yet applied to the canvas.
  /// Cleared by [EditorCubit.acknowledgeLoad] once the controller has consumed it.
  final ({Uint8List bytes, String? filePath})? pendingLoad;

  /// Whether the grid overlay is shown. Synced to [CanvasController] by
  /// [EditorScreen] via a [BlocListener], mirroring the existing tool/color/
  /// size flow rather than the cubit touching the controller directly.
  final bool gridVisible;

  /// Grid cell size in raster pixels. Synced to [CanvasController] the same
  /// way as [gridVisible].
  final double gridCellSize;

  /// Whether pixel art mode is active. Unlike [gridVisible]/[gridCellSize],
  /// this is read directly by [EditorScreen] at draw-time — like [tool],
  /// [color], and [strokeSize] — rather than synced into [CanvasController]
  /// as standing state, since it only ever affects how a stroke is drawn at
  /// the moment it starts.
  final bool pixelArtMode;

  /// Whether mirror mode is active. Same read-at-draw-time shape as
  /// [pixelArtMode]: it only affects how a stroke is built at pointer-down,
  /// so [EditorScreen] passes it straight to [CanvasController.onPointerDown]
  /// rather than syncing it into the controller as standing state.
  final bool mirrorMode;

  static EditorState initial() => EditorState(
    tool: DrawingTool.brush,
    color: CanvasConstants.defaultToolColor,
    strokeSize: CanvasConstants.brushSizes[1],
  );

  EditorState copyWith({
    DrawingTool? tool,
    Color? color,
    double? strokeSize,
    String? currentFilePath,
    ({Uint8List bytes, String? filePath})? pendingLoad,
    bool clearFilePath = false,
    bool clearPendingLoad = false,
    bool? gridVisible,
    double? gridCellSize,
    bool? pixelArtMode,
    bool? mirrorMode,
  }) => EditorState(
    tool: tool ?? this.tool,
    color: color ?? this.color,
    strokeSize: strokeSize ?? this.strokeSize,
    currentFilePath: clearFilePath
        ? null
        : (currentFilePath ?? this.currentFilePath),
    pendingLoad: clearPendingLoad ? null : (pendingLoad ?? this.pendingLoad),
    gridVisible: gridVisible ?? this.gridVisible,
    gridCellSize: gridCellSize ?? this.gridCellSize,
    pixelArtMode: pixelArtMode ?? this.pixelArtMode,
    mirrorMode: mirrorMode ?? this.mirrorMode,
  );

  @override
  List<Object?> get props => [
    tool,
    color,
    strokeSize,
    currentFilePath,
    pendingLoad,
    gridVisible,
    gridCellSize,
    pixelArtMode,
    mirrorMode,
  ];
}