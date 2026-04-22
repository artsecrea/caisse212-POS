import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// CAISSE212 branded logo widget with "by artecrea" subtitle.
/// Uses the artecrea logo SVG rendered in purple.
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // SVG Logo in purple
        SvgPicture.asset(
          'assets/images/caisse212_icon.svg',
          width: size,
          height: size,
          colorFilter: const ColorFilter.mode(
            Color(0xFF7B1FA2), // Purple 700
            BlendMode.srcIn,
          ),
        ),
        SizedBox(height: size * 0.15),
        // CAISSE212 text
        Text(
          'CAISSE212',
          style: TextStyle(
            fontSize: size * 0.35,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF7B1FA2), // Purple 700
            letterSpacing: 2,
          ),
        ),
        if (showByLine) ...[
          SizedBox(height: size * 0.05),
          Text(
            'by artecrea',
            style: TextStyle(
              fontSize: size * 0.14,
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              letterSpacing: 1.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}


