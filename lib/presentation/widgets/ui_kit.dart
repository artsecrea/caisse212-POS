/// Shared UI building blocks so every page looks and behaves the same.
///
/// All widgets read colors from the active [ColorScheme] — no hardcoded
/// palette — so they adapt to light/dark automatically. Use these instead of
/// re-inventing headers, cards, chips, and action bars per screen.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A consistent section header: leading icon in a tinted square, a title, and
/// an optional subtitle + trailing action. Replaces the ad-hoc
/// icon + Text + Text rows scattered across the settings/management screens.
class SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? accent;

  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = accent ?? scheme.primary;
    return Row(
      children: [
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: Icon(icon, color: c, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// A padded, hairline-bordered panel — the standard container for grouped
/// content. Matches the global card theme but lets callers control padding and
/// an optional tap target.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color ?? scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.8),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Small status pill (e.g. order status, paid/unpaid). Pass a [color] and it
/// derives a soft background so labels stay readable in both themes.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A bottom action bar that stays visible above content — for the "keep action
/// buttons visible / fewer clicks" pattern. Give it the primary action(s); it
/// pins them to the bottom of a screen or dialog with a subtle top divider and
/// safe-area padding.
class StickyActionBar extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final MainAxisAlignment alignment;

  const StickyActionBar({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
    this.alignment = MainAxisAlignment.end,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: padding,
          child: Row(
            mainAxisAlignment: alignment,
            children: _withGaps(children),
          ),
        ),
      ),
    );
  }

  List<Widget> _withGaps(List<Widget> items) {
    if (items.length < 2) return items;
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i != items.length - 1) out.add(const SizedBox(width: 12));
    }
    return out;
  }
}

/// An inline "tap to edit" field: shows a labelled value with a pencil, and
/// swaps to a text field on tap — the "possibility to edit" pattern without a
/// modal round-trip. Calls [onSubmit] with the new value on done.
class InlineEditable extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onSubmit;
  final TextInputType keyboardType;
  final IconData? icon;

  const InlineEditable({
    super.key,
    required this.label,
    required this.value,
    required this.onSubmit,
    this.keyboardType = TextInputType.text,
    this.icon,
  });

  @override
  State<InlineEditable> createState() => _InlineEditableState();
}

class _InlineEditableState extends State<InlineEditable> {
  bool _editing = false;
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant InlineEditable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    setState(() => _editing = false);
    widget.onSubmit(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: _editing
                ? TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: widget.keyboardType,
                    decoration: InputDecoration(labelText: widget.label),
                    onSubmitted: (_) => _commit(),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.value.isEmpty ? '—' : widget.value,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
          ),
          IconButton(
            icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
            color: _editing ? scheme.primary : scheme.onSurfaceVariant,
            onPressed: () => _editing ? _commit() : setState(() => _editing = true),
          ),
        ],
      ),
    );
  }
}
