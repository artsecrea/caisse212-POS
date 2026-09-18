import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Caisse212 branded logo widget.
/// [size] controls the height of the main logo; width scales proportionally.
/// [showByLine] toggles the "by artecrea" line below.
class Caisse212Logo extends StatelessWidget {
  final double size;
  final bool showByLine;

  const Caisse212Logo({
    super.key,
    this.size = 80,
    this.showByLine = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bylineColor = isDark ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Full caisse212 logo (icon + wordmark in one SVG)
        SvgPicture.asset(
          'assets/images/caisse212.svg',
          height: size,
          fit: BoxFit.contain,
        ),
        if (showByLine) ...[
          SizedBox(height: size * 0.12),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'by ',
                style: TextStyle(
                  fontSize: size * 0.16,
                  color: bylineColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
              SvgPicture.asset(
                'assets/images/logo.svg',
                height: size * 0.22,
                colorFilter: ColorFilter.mode(
                  isDark
                      ? Theme.of(context).colorScheme.outline
                      : const Color(0xFF7B1FA2),
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                'artecrea',
                style: TextStyle(
                  fontSize: size * 0.16,
                  color: isDark
                      ? Theme.of(context).colorScheme.outline
                      : const Color(0xFF7B1FA2),
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
