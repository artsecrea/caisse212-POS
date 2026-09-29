import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../utils/app_localizations.dart';

/// Toolbar switch for whether totals on the orders and tickets screens add
/// the delivery fee. One setting behind both screens, so flipping it on one
/// is what the other shows too.
class DeliveryFeeTotalsChip extends ConsumerWidget {
  const DeliveryFeeTotalsChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final include = ref.watch(settingsProvider).totalsIncludeDeliveryFee;
    return Tooltip(
      message: l10n.translate(include
          ? 'totals_include_delivery_fee_on_hint'
          : 'totals_include_delivery_fee_off_hint'),
      child: FilterChip(
        avatar: const Icon(Icons.delivery_dining, size: 18),
        label: Text(l10n.translate('totals_include_delivery_fee')),
        selected: include,
        showCheckmark: false,
        onSelected: (v) => ref
            .read(settingsProvider.notifier)
            .setTotalsIncludeDeliveryFee(v),
      ),
    );
  }
}
