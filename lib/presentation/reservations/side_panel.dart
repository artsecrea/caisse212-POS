import 'package:flutter/material.dart';

/// Opens [child] as a panel sliding in from the end edge, over the agenda,
/// the way salon agendas show an appointment beside the day rather than
/// replacing it. Narrow screens get a bottom sheet instead.
Future<T?> showSidePanel<T>(
  BuildContext context,
  Widget child, {
  double width = 440,
}) {
  final size = MediaQuery.of(context).size;
  if (size.width < 760) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(height: size.height * 0.88, child: child),
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Material(
        elevation: 12,
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: SafeArea(child: child),
        ),
      ),
    ),
    transitionBuilder: (context, anim, _, child) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      return SlideTransition(
        position: Tween(
          begin: Offset(rtl ? -1 : 1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      );
    },
  );
}

/// Header row shared by the panels: title, optional subtitle, close button.
class SidePanelHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  const SidePanelHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 8, 10),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
