import 'package:flutter/material.dart';

class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({
    super.key,
    required this.onDismiss,
  });

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
            child: Center(
              child: Transform.scale(
                scale: 0.8 + (0.2 * value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Material(
                    color: const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(16),
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
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
                          const SizedBox(height: 20),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _currentPage == 0
                                ? const _PageOneContent()
                                : const _PageTwoContent(),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (_currentPage == 1)
                                TextButton(
                                  onPressed: _previousPage,
                                  child: const Text('Back'),
                                )
                              else
                                const SizedBox.shrink(),
                              FilledButton(
                                onPressed: _currentPage == 0 ? _nextPage : _close,
                                child: Text(_currentPage == 0 ? 'Next' : 'Got it'),
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
        );
      },
    );
  }
}

class _PageOneContent extends StatelessWidget {
  const _PageOneContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      key: ValueKey('page1'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _HintRow(icon: Icons.circle_outlined, text: 'Tap the hub button to open the tool menu.'),
        _HintRow(icon: Icons.draw_outlined, text: 'Tap the tool icon to browse and switch tools.'),
        _HintRow(icon: Icons.palette_outlined, text: 'Tap the colour icon to pick a colour or open the wheel.'),
        _HintRow(icon: Icons.line_weight, text: 'Tap the size icon to change brush or stroke width.'),
        _HintRow(icon: Icons.undo, text: 'Use Undo and Redo in the toolbar at the top.'),
      ],
    );
  }
}

class _PageTwoContent extends StatelessWidget {
  const _PageTwoContent();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('page2'),
      height: 240, 
      child: ListView(
        shrinkWrap: true,
        children: const [
          _HintRow(icon: Icons.brush, text: 'Brush: Freehand drawing'),
          _HintRow(icon: Icons.edit, text: 'Highlighter: Semi-transparent freehand'),
          _HintRow(icon: Icons.blur_on, text: 'Spray: Airbrush effect'),
          _HintRow(icon: Icons.auto_fix_normal, text: 'Eraser: Restores canvas to white'),
          _HintRow(icon: Icons.format_color_fill, text: 'Fill: Flood-fills a region'),
          _HintRow(icon: Icons.remove, text: 'Line: Straight line'),
          _HintRow(icon: Icons.crop_square, text: 'Rectangle: Drag to draw a rectangle'),
          _HintRow(icon: Icons.circle_outlined, text: 'Ellipse: Drag to draw an ellipse'),
          _HintRow(icon: Icons.change_history, text: 'Triangle: Drag to draw a triangle'),
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