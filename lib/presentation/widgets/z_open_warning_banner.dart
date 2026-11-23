import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/business_day_provider.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/z_rules.dart';
import '../../services/z_service.dart';
import '../../utils/app_localizations.dart';

/// A strip under the top bar while the open Z has been left open too long or
/// past the admin's cutoff time. Only a warning: nothing here closes the Z.
///
/// "Later" hides it for [_snooze]; it comes back on its own, and at once if a
/// new kind of warning starts to apply.
class ZOpenWarningBanner extends ConsumerStatefulWidget {
  const ZOpenWarningBanner({super.key});

  @override
  ConsumerState<ZOpenWarningBanner> createState() => _ZOpenWarningBannerState();
}

class _ZOpenWarningBannerState extends ConsumerState<ZOpenWarningBanner> {
  static const _snooze = Duration(minutes: 30);
  Timer? _tick;
  DateTime? _snoozedUntil;
  Set<ZOpenWarning> _snoozedFor = const {};

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final z = ref.watch(currentZProvider);
    final settings = ref.watch(settingsProvider);
    final startHour = ref.watch(businessDayProvider).startHour;
    if (z == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final label = ZService.labelOf(z);
    final warnings = zOpenWarnings(
      now: now,
      startedAt: z.startedAt,
      zDay: label.zDay,
      startHour: startHour,
      maxOpenHours: settings.zWarnOpenTooLong ? settings.zWarnOpenHours : null,
      cutoff: settings.zWarnPastCutoff ? settings.zWarnCutoffTime : null,
    );
    if (warnings.isEmpty) return const SizedBox.shrink();
    final snoozed = _snoozedUntil != null &&
        now.isBefore(_snoozedUntil!) &&
        _snoozedFor.containsAll(warnings);
    if (snoozed) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final hours = now.difference(z.startedAt).inHours;
    final lines = <String>[
      if (warnings.contains(ZOpenWarning.openTooLong))
        l10n
            .translate('z_warn_open_too_long_msg')
            .replaceAll('{0}', '$hours'),
      if (warnings.contains(ZOpenWarning.pastCutoff))
        l10n
            .translate('z_warn_past_cutoff_msg')
            .replaceAll('{0}', ZService.displayName(z))
            .replaceAll('{1}', settings.zWarnCutoffTime),
    ];

    return Material(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                lines.join('  •  '),
                style: TextStyle(
                    color: cs.onErrorContainer, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _snoozedUntil = DateTime.now().add(_snooze);
                _snoozedFor = warnings;
              }),
              style: TextButton.styleFrom(foregroundColor: cs.onErrorContainer),
              child: Text(l10n.translate('later')),
            ),
          ],
        ),
      ),
    );
  }
}
