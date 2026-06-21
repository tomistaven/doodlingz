import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/canvas_constants.dart';
import '../../../core/constants/ui_constants.dart';
import '../../../domain/entities/drawing_tool.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/editor_cubit.dart';
import '../cubit/editor_state.dart';
import 'editor_hub_nodes.dart';

// Public so the HubNodes mixin can reference it across files.
enum HubLevel { root, tools, colors, sizes }

/// Floating radial control hub for the editor.
///
/// Anchors to the bottom-left corner by default. When [SettingsState.hubOnRight]
/// is true the entire hub mirrors to the bottom-right corner for left-handed use.
///
/// Node-building logic lives in [HubNodes].
class EditorHub extends StatefulWidget {
  const EditorHub({super.key});

  @override
  State<EditorHub> createState() => _EditorHubState();
}

class _EditorHubState extends State<EditorHub>
    with SingleTickerProviderStateMixin, HubNodes {
  static const double _handleSize = UiConstants.hubHandleSize;
  static const double _nodeSize = UiConstants.hubNodeSize;
  static const double _baseMargin = UiConstants.hubEdgeMargin;

  late final AnimationController _animController;

  bool _isOpen = false;
  HubLevel _currentLevel = HubLevel.root;

  @override
  bool get hubOpen => _isOpen;

  @override
  HubLevel get hubLevel => _currentLevel;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: UiConstants.hubArcDuration,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onHandleTap() {
    if (!_isOpen) {
      setState(() {
        _isOpen = true;
        _currentLevel = HubLevel.root;
      });
      _animController.forward(from: 0);
    } else if (_currentLevel != HubLevel.root) {
      setState(() => _currentLevel = HubLevel.root);
      _animController.forward(from: 0);
    } else {
      closeHub();
    }
  }

  @override
  void closeHub() {
    setState(() => _isOpen = false);
    _animController.reverse();
  }

  @override
  void goTo(HubLevel level) {
    setState(() => _currentLevel = level);
    _animController.forward(from: 0);
  }

  @override
  void selectTool(DrawingTool tool) {
    context.read<EditorCubit>().selectTool(tool);
    closeHub();
  }

  @override
  void selectColor(Color color) {
    context.read<EditorCubit>().selectColor(color);
    closeHub();
  }

  @override
  void selectSize(double size) {
    context.read<EditorCubit>().selectSize(size);
    closeHub();
  }

  List<double> _sizesFor(DrawingTool tool) {
    switch (tool) {
      case DrawingTool.spray:
        return CanvasConstants.spraySizes;
      case DrawingTool.line:
      case DrawingTool.rectangle:
      case DrawingTool.ellipse:
      case DrawingTool.triangle:
        return CanvasConstants.shapeOutlineWidths;
      case DrawingTool.fill:
        return [];
      default:
        return CanvasConstants.brushSizes;
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The arc's default radii assume portrait's generous body height. In
        // landscape the body is much shorter, so the outer-row nodes can run
        // past the top of the body and get clipped under the app bar. Scale
        // the radii down only when the default reach wouldn't fit; portrait
        // is unaffected since it always has headroom to spare.
        //
        // Curves.easeOutBack overshoots its target by ~8% mid-animation
        // before settling, so the open animation briefly extends past the
        // node's final resting radius. Budget for that overshoot here, or
        // the topmost node clips for a frame even though it fits at rest.
        const double openAnimationOvershoot = 1.08;
        final handleBottomMargin = _baseMargin + padding.bottom;
        final maxReach = handleBottomMargin +
            _handleSize / 2 +
            UiConstants.hubArcRadiusOuter * openAnimationOvershoot +
            _nodeSize / 2;
        final radiusScale = constraints.maxHeight < maxReach
            ? (constraints.maxHeight / maxReach).clamp(0.5, 1.0)
            : 1.0;

        return _buildHub(context, padding, screenWidth, radiusScale);
      },
    );
  }

  Widget _buildHub(
    BuildContext context,
    EdgeInsets padding,
    double screenWidth,
    double radiusScale,
  ) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, settings) {
        final hubOnRight = settings.hubOnRight;

        final handleBottom = _baseMargin + padding.bottom;
        final double handleEdge;
        final double handleCentreX;

        if (hubOnRight) {
          handleEdge = _baseMargin + padding.right;
          handleCentreX = screenWidth - handleEdge - _handleSize / 2;
        } else {
          handleEdge = _baseMargin + padding.left;
          handleCentreX = handleEdge + _handleSize / 2;
        }

        final handleCentreY = handleBottom + _handleSize / 2;

        return BlocBuilder<EditorCubit, EditorState>(
          builder: (context, state) {
            return AnimatedBuilder(
              animation: _animController,
              builder: (context, _) {
                final showArc = _isOpen || _animController.value > 0;
                return Stack(
                  children: [
                    if (_isOpen)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: closeHub,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: UiConstants.hubScrimOpacity),
                          ),
                        ),
                      ),
                    if (showArc)
                      ..._buildArcNodes(
                        state: state,
                        cx: handleCentreX,
                        cy: handleCentreY,
                        hubOnRight: hubOnRight,
                        radiusScale: radiusScale,
                      ),
                    _buildHandle(
                      state: state,
                      edge: handleEdge,
                      bottom: handleBottom,
                      hubOnRight: hubOnRight,
                    ),
                  ],
                );
              },
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
    required bool hubOnRight,
    required double radiusScale,
  }) {
    final nodes = _nodeContentsForLevel(state);
    final count = nodes.length;
    final t =
        Curves.easeOutBack.transform(_animController.value.clamp(0.0, 1.0));
    final opacity = _animController.value.clamp(0.0, 1.0);

    return [
      for (var i = 0; i < count; i++)
        _positionNode(
          index: i,
          count: count,
          t: t,
          opacity: opacity,
          cx: cx,
          cy: cy,
          hubOnRight: hubOnRight,
          radiusScale: radiusScale,
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
    required bool hubOnRight,
    required double radiusScale,
    required Widget child,
  }) {
    final bool useTwoRows = count > 5;
    final int innerCount = useTwoRows ? (count / 2).floor() : count;
    final bool isOuter = index >= innerCount;
    final int rowCount = isOuter ? (count - innerCount) : innerCount;
    final int rowIndex = isOuter ? index - innerCount : index;

    final double targetRadius = (useTwoRows
            ? (isOuter ? UiConstants.hubArcRadiusOuter : UiConstants.hubArcRadiusInner)
            : UiConstants.hubArcRadiusSingle) *
        radiusScale;
    final double distance = targetRadius * t;

    const double minAngle = math.pi / 36;
    const double maxAngle = 17 * math.pi / 36;
    const double availableSweep = maxAngle - minAngle;

    double actualStep;
    double startAngle;

    if (count == 2) {
      actualStep = math.pi / 3;
      startAngle = math.pi / 12;
    } else if (count == 3 && !useTwoRows) {
      actualStep = availableSweep / (rowCount - 1);
      startAngle = minAngle;
    } else if (rowCount == 1) {
      actualStep = 0;
      startAngle = math.pi / 4;
    } else {
      actualStep = availableSweep / (rowCount - 1);
      startAngle = minAngle;
    }

    final double angle = startAngle + (rowIndex * actualStep);

    // For the right-side anchor the arc sweeps up-left, so the x component
    // is negated to mirror the geometry across the vertical axis.
    final double rx = math.cos(angle) * distance * (hubOnRight ? -1 : 1);
    final double uy = math.sin(angle) * distance;

    return Positioned(
      left: cx + rx - _nodeSize / 2,
      bottom: cy + uy - _nodeSize / 2,
      child: Opacity(
        opacity: opacity,
        child: IgnorePointer(ignoring: !_isOpen, child: child),
      ),
    );
  }

  List<Widget> _nodeContentsForLevel(EditorState state) {
    final sizes = _sizesFor(state.tool);
    switch (_currentLevel) {
      case HubLevel.root:
        return [
          buildCategoryNode(
            icon: Icons.draw,
            onTap: () => goTo(HubLevel.tools),
            tooltip: 'Tools',
          ),
          buildColorCategoryNode(state.color),
          if (sizes.isNotEmpty)
            buildCategoryNode(
              icon: Icons.line_weight,
              onTap: () => goTo(HubLevel.sizes),
              tooltip: 'Size',
            ),
        ];
      case HubLevel.tools:
        return DrawingTool.values
            .map((tool) => buildToolNode(tool, state.tool == tool))
            .toList();
      case HubLevel.colors:
        return [
          ...CanvasConstants.presetColors
              .map((color) => buildSwatchNode(color, state.color == color)),
          buildCustomNode(),
        ];
      case HubLevel.sizes:
        return sizes
            .map((size) => buildSizeNode(size, sizes, state.strokeSize))
            .toList();
    }
  }

  Widget _buildHandle({
    required EditorState state,
    required double edge,
    required double bottom,
    required bool hubOnRight,
  }) {
    return Positioned(
      left: hubOnRight ? null : edge,
      right: hubOnRight ? edge : null,
      bottom: bottom,
      child: Tooltip(
        message: _isOpen
            ? (_currentLevel == HubLevel.root ? 'Close' : 'Back')
            : labelFor(state.tool),
        preferBelow: false,
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
                  color: Color.fromRGBO(0, 0, 0, _isOpen ? 0.35 : 0.15),
                  blurRadius: _isOpen ? 10 : 4,
                  spreadRadius: _isOpen ? 1 : 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AnimatedOpacity(
              opacity: _isOpen ? 1.0 : 0.9,
              duration: UiConstants.hubHandleFadeDuration,
              child: Container(
                decoration: BoxDecoration(
                  color: UiConstants.hubSurface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: UiConstants.hubHandleRing,
                    width: UiConstants.hubHandleRingWidth,
                  ),
                ),
                child: Center(
                  child: Icon(
                    handleIcon(state.tool),
                    color: Colors.white.withValues(alpha: UiConstants.hubIconOpacity),
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}