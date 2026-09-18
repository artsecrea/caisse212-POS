import 'package:flutter/material.dart';

/// How one external platform is shown: its logo, its brand colour, its name.
///
/// One table, used by every screen that shows where an order came from, so a
/// Glovo order looks the same in the queue, on the counter list and in the
/// detail pane. Adding a platform is a row here and an asset, nothing else.
class OrderSource {
  final String label;
  final Color color;

  /// The platform's own logo. Null for sources with no mark of their own
  /// (a web order, an unrecognised platform), which fall back to [icon].
  final String? asset;
  final IconData icon;

  const OrderSource({
    required this.label,
    required this.color,
    this.asset,
    required this.icon,
  });

  /// Resolved case-insensitively, with an unknown source degrading to a
  /// neutral cloud rather than being hidden — an order from a platform this
  /// build has not heard of still has to be visible on the counter.
  factory OrderSource.of(String? source) {
    switch ((source ?? '').toUpperCase()) {
      case 'GLOVO':
        return const OrderSource(
          label: 'Glovo',
          color: Color(0xFFFFC244),
          asset: 'assets/images/glovo.png',
          icon: Icons.pedal_bike,
        );
      case 'KOOUL':
        return const OrderSource(
          label: 'Kooul',
          color: Color(0xFFFB3B4F),
          asset: 'assets/images/kooul.png',
          icon: Icons.delivery_dining,
        );
      case 'DEALUP':
        return const OrderSource(
          label: 'DealUp',
          color: Color(0xFF34A853),
          asset: 'assets/images/dealup.png',
          icon: Icons.storefront_outlined,
        );
      case 'WHATSAPP':
        return const OrderSource(
          label: 'WhatsApp',
          color: Color(0xFF25D366),
          icon: Icons.chat,
        );
      case 'WEB':
        return const OrderSource(
          label: 'Web',
          color: Color(0xFF42A5F5),
          icon: Icons.language,
        );
      default:
        return OrderSource(
          label: (source == null || source.isEmpty) ? 'External' : source,
          color: const Color(0xFF78909C),
          icon: Icons.cloud_outlined,
        );
    }
  }
}

/// The platform's logo in a rounded tile.
///
/// The logos are square and carry their own background (Glovo's yellow,
/// Kooul's red), so they are clipped rather than padded — a brand mark inset on
/// a tinted tile of a *different* colour reads as broken. Sources without a
/// logo keep the tinted-icon treatment, which is why both paths live here.
class OrderSourceBadge extends StatelessWidget {
  final String? source;
  final double size;

  const OrderSourceBadge({super.key, required this.source, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final s = OrderSource.of(source);
    final radius = BorderRadius.circular(size * 0.22);

    if (s.asset != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          s.asset!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          // A missing asset must never take the screen down with it — the
          // order still has to be actionable.
          errorBuilder: (_, __, ___) => _fallback(s, radius),
        ),
      );
    }
    return _fallback(s, radius);
  }

  Widget _fallback(OrderSource s, BorderRadius radius) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: s.color.withValues(alpha: 0.14),
          borderRadius: radius,
          border: Border.all(color: s.color.withValues(alpha: 0.35)),
        ),
        child: Icon(s.icon, color: s.color, size: size * 0.45),
      );
}

/// The platform's name as a small tinted chip.
class OrderSourceLabel extends StatelessWidget {
  final String? source;
  const OrderSourceLabel({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    final s = OrderSource.of(source);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: s.color.withValues(alpha: 0.35)),
      ),
      child: Text(
        s.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          // The brand colours are mid-tones chosen to sit on a tint of
          // themselves; on a dark surface they need lifting to stay legible.
          color: Theme.of(context).brightness == Brightness.dark
              ? Color.alphaBlend(s.color.withValues(alpha: 0.85), Colors.white)
              : s.color,
        ),
      ),
    );
  }
}
