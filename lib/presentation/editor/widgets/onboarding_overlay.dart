import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  int _currentPage = 0;
  bool _isClosing = false;

  void _nextPage() {
    setState(() => _currentPage = 1);
  }

  void _previousPage() {
    setState(() => _currentPage = 0);
  }

  void _close() {
    setState(() => _isClosing = true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Detect landscape to tighten up vertical spacing
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: _isClosing ? 0.0 : 1.0),
      duration: const Duration(milliseconds: 300),
      curve: _isClosing ? Curves.easeIn : Curves.easeOutBack,
      onEnd: () {
        if (_isClosing) widget.onDismiss();
      },
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.55 * value.clamp(0.0, 1.0)),
            child: SafeArea(
              child: Center(
                child: Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: Padding(
                    // Reduce outer vertical padding heavily in landscape
                    padding: EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: isLandscape ? 8.0 : 24.0,
                    ),
                    // Cap the card height so a tall page (or a short landscape
                    // screen) scrolls its content instead of overflowing the
                    // viewport or covering the tool hub beneath it.
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 450,
                        maxHeight: isLandscape
                            ? MediaQuery.sizeOf(context).height * 0.95
                            : 480,
                      ),
                      child: Material(
                        color: const Color(0xFF242424),
                        borderRadius: BorderRadius.circular(16),
                        elevation: 8,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            isLandscape ? 16 : 28,
                            24,
                            isLandscape ? 12 : 20,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentPage == 0
                                    ? 'Welcome to Doodlingz'
                                    : 'Tool Reference',
                                style: textTheme.titleLarge?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: isLandscape ? 12 : 20),
                              // Loose fit so the card shrinks to the content when
                              // it fits, and the inner scroll view caps it when it
                              // doesn't; the title and buttons stay pinned.
                              Flexible(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: _currentPage == 0
                                      ? const _PageOneContent()
                                      : const _PageTwoContent(),
                                ),
                              ),
                              SizedBox(height: isLandscape ? 16 : 24),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  if (_currentPage == 1)
                                    TextButton(
                                      onPressed: _previousPage,
                                      child: const Text('Back'),
                                    )
                                  else
                                    const SizedBox.shrink(),
                                  FilledButton(
                                    onPressed: _currentPage == 0
                                        ? _nextPage
                                        : _close,
                                    child: Text(
                                      _currentPage == 0 ? 'Next' : 'Got it',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PageOneContent extends StatefulWidget {
  const _PageOneContent();

  @override
  State<_PageOneContent> createState() => _PageOneContentState();
}

class _PageOneContentState extends State<_PageOneContent> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      key: const ValueKey('page1'),
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView(
        controller: _scrollController,
        shrinkWrap: true,
        children: const [
          _HintRow(
            icon: Icons.circle_outlined,
            text: 'Tap the hub button to open the tool menu.',
          ),
          _HintRow(
            icon: Icons.draw_outlined,
            text: 'Tap the tool icon to browse and switch tools.',
          ),
          _HintRow(
            icon: Icons.palette_outlined,
            text: 'Tap the colour icon to pick a colour or open the wheel.',
          ),
          _HintRow(
            icon: Icons.line_weight,
            text: 'Tap the size icon to change brush or stroke width.',
          ),
          _HintRow(
            icon: Icons.undo,
            text: 'Use Undo and Redo in the toolbar at the top.',
          ),
          _HintRow(
            icon: Icons.pinch,
            text:
                'Pinch with two fingers to zoom, and drag with two '
                'fingers to pan.',
          ),
          _HintRow(
            icon: Icons.rotate_right,
            text:
                'Twist with two fingers to rotate the canvas. It snaps '
                'back to upright near straight.',
          ),
          _HintRow(
            icon: Icons.grid_on,
            text:
                'Tap the grid icon to show a grid and change its cell '
                'size.',
          ),
          _HintRow(
            icon: Icons.videogame_asset,
            text:
                'Pixel art mode snaps a square brush to the grid. Brush '
                'and eraser only.',
          ),
        ],
      ),
    );
  }
}

class _PageTwoContent extends StatefulWidget {
  const _PageTwoContent();

  @override
  State<_PageTwoContent> createState() => _PageTwoContentState();
}

class _PageTwoContentState extends State<_PageTwoContent> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      key: const ValueKey('page2'),
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView(
        controller: _scrollController,
        shrinkWrap: true,
        children: const [
          _HintRow(icon: Icons.brush, text: 'Brush: Freehand drawing'),
          _HintRow(
            icon: Symbols.format_ink_highlighter,
            text: 'Highlighter: Semi-transparent freehand',
          ),
          _HintRow(icon: Icons.grain, text: 'Spray: Airbrush effect'),
          _HintRow(
            icon: Symbols.ink_eraser,
            text: 'Eraser: Restores canvas to white',
          ),
          _HintRow(
            icon: Icons.format_color_fill,
            text: 'Fill: Flood-fills a region',
          ),
          _HintRow(icon: Icons.horizontal_rule, text: 'Line: Straight line'),
          _HintRow(
            icon: Icons.crop_square,
            text: 'Rectangle: Drag to draw a rectangle',
          ),
          _HintRow(
            icon: Icons.circle_outlined,
            text: 'Ellipse: Drag to draw an ellipse',
          ),
          _HintRow(
            icon: Icons.change_history,
            text: 'Triangle: Drag to draw a triangle',
          ),
        ],
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.white70),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}