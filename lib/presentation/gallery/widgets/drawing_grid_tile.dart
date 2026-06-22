import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/saved_drawing.dart';

/// A single tile in the gallery grid.
///
/// Shows the drawing as a full-bleed thumbnail with a date label overlaid at
/// the bottom. Supports tap, long-press, and a selection highlight overlay for
/// multi-select mode.
class DrawingGridTile extends StatelessWidget {
  const DrawingGridTile({
    super.key,
    required this.drawing,
    required this.onTap,
    required this.onLongPress,
    this.isSelected = false,
  });

  final SavedDrawing drawing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelected;

  static final _dateFormat = DateFormat('dd MMM yyyy  HH:mm');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              key: ValueKey(
                '${drawing.filePath}_${drawing.updatedAt.millisecondsSinceEpoch}',
              ),
              image: FileImage(File(drawing.filePath)),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                  child: Text(
                    _dateFormat.format(drawing.createdAt),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            if (isSelected)
              Positioned.fill(
                child: ColoredBox(
                  color: colorScheme.primary.withValues(alpha: 0.35),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.check_circle,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
