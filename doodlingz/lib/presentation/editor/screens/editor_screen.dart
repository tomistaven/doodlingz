import 'package:flutter/material.dart';

import '../../../core/constants/canvas_constants.dart';
import '../../../domain/repositories/drawing_repository.dart';
import '../../../injection_container.dart';
import '../controller/canvas_controller.dart';
import '../painter/drawing_canvas_painter.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../../domain/entities/drawing_tool.dart';
import '../engine/canvas_compositor.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.existingImageBytes});

  /// Non-null when opening a saved drawing for editing.
  final Uint8List? existingImageBytes;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final CanvasController _controller;

  DrawingTool _tool = DrawingTool.brush;
  // ignore: prefer_final_fields
  Color _color = CanvasConstants.defaultToolColor;
  double _size = CanvasConstants.brushSizes[1];

  @override
  void initState() {
    super.initState();
    _controller = CanvasController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initialiseCanvas(BoxConstraints constraints) async {
    if (_controller.value.committedImage.width > 1) return;

    final displaySize = Size(constraints.maxWidth, constraints.maxHeight);
    final rasterSize = CanvasConstants.portraitCanvasSize;

    ui.Image? existing;
    if (widget.existingImageBytes != null) {
      existing = await CanvasCompositor.fromBytes(widget.existingImageBytes!);
    }

    await _controller.initialise(
      rasterSize: rasterSize,
      displaySize: displaySize,
      existingImage: existing,
    );
  }

  Future<void> _save() async {
    final bytes = await _controller.toPngBytes();
    await sl<DrawingRepository>().save(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drawing saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doodlingz'),
        actions: [
          ValueListenableBuilder<CanvasState>(
            valueListenable: _controller,
            builder: (_, state, _) => IconButton(
              icon: const Icon(Icons.undo),
              onPressed: state.canUndo ? _controller.undo : null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildToolRow(),
          Expanded(child: _buildCanvas()),
        ],
      ),
    );
  }

  Widget _buildToolRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: DrawingTool.values.map((tool) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(tool.name),
              selected: _tool == tool,
              onSelected: (_) => setState(() {
                _tool = tool;
                _size = _toolSize(tool);
              }),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _initialiseCanvas(constraints);
        return GestureDetector(
          onPanStart: (d) => _controller.onPointerDown(
            d.localPosition,
            _tool,
            _color,
            _size,
          ),
          onPanUpdate: (d) => _controller.onPointerMove(d.localPosition),
          onPanEnd: (_) => _controller.onPointerUp(),
          child: ValueListenableBuilder<CanvasState>(
            valueListenable: _controller,
            builder: (_, state, _) => CustomPaint(
              painter: DrawingCanvasPainter(state: state),
              size: Size(constraints.maxWidth, constraints.maxHeight),
            ),
          ),
        );
      },
    );
  }

  double _toolSize(DrawingTool tool) {
    switch (tool) {
      case DrawingTool.spray:
        return CanvasConstants.spraySizes[0];
      case DrawingTool.eraser:
        return CanvasConstants.brushSizes[2];
      default:
        return CanvasConstants.brushSizes[1];
    }
  }
}