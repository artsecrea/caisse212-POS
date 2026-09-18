import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// The label strip that sits **on** a card's image rather than beneath it.
///
/// Shared by the product grid and the category grid so the two can never drift:
/// a till showing product names one way and category names another looks
/// broken, and the legibility work below is fiddly enough that nobody wants to
/// maintain two copies of it.
///
/// Reading text over an arbitrary photograph is the whole problem. Three things
/// solve it, in order of how much work they do:
///
///  1. **The scrim** — a top-to-bottom darkening gradient. This alone is enough
///     to read; a gradient rather than a solid bar because a hard edge cuts the
///     picture in half, which is the look this layout exists to avoid.
///  2. **The blur** — stops a busy image reading as noise *around* the letters.
///  3. **The glyph shadow** — catches the case where a bright highlight lands
///     directly under a stroke, which the other two miss.
class OverlayLabelStrip extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double titleSize;
  final double? subtitleSize;
  final int titleMaxLines;
  final EdgeInsets padding;
  final TextAlign textAlign;

  /// Colour for the title. Defaults to white, which is what the scrim is built
  /// for; a category using its own brand colour can override it.
  final Color titleColor;

  const OverlayLabelStrip({
    super.key,
    required this.title,
    this.subtitle,
    required this.titleSize,
    this.subtitleSize,
    this.titleMaxLines = 2,
    this.padding = const EdgeInsets.fromLTRB(8, 6, 8, 6),
    this.textAlign = TextAlign.start,
    this.titleColor = Colors.white,
  });

  static const List<Shadow> _glyphShadow = [
    Shadow(blurRadius: 3, color: Color(0xCC000000)),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      // Bounds the backdrop filter to this strip. Without it the blur samples
      // — and repaints — the whole card behind it.
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0xB3000000)],
            ),
          ),
          child: Column(
            crossAxisAlignment: textAlign == TextAlign.center
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: textAlign,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: titleSize,
                  height: 1.15,
                  color: titleColor,
                  shadows: _glyphShadow,
                ),
                maxLines: titleMaxLines,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                Text(
                  subtitle!,
                  textAlign: textAlign,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: subtitleSize ?? titleSize - 1,
                    color: Colors.white.withValues(alpha: 0.92),
                    shadows: _glyphShadow,
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
