import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../utils/app_localizations.dart';
import 'adaptive_text_field.dart';

/// Serial picker for a serial-tracked product, shown in place of the components
/// panel — a tracked unit never carries components, so the space is free.
///
/// Built for a finger, not a mouse: 64px-tall rows in a single scrolling column,
/// the whole row is the target, and the selected unit is marked with a filled
/// check plus a border rather than a subtle tint. The scan field takes focus on
/// open, so a hardware scanner works with no tap at all — and typing narrows the
/// same list, so scanning and searching are one mental model.
class SerialPickerPanel extends ConsumerStatefulWidget {
  final int productId;

  /// Serials already committed to other lines of this same order. They are
  /// already `isAvailable: false` in the DB, but this keeps the picker honest
  /// even before a reservation lands.
  final Set<int> excludeSerialIds;

  /// The serial currently on the line being edited, so re-opening the picker
  /// shows its own choice as selected rather than as missing.
  final int? selectedSerialId;

  final ValueChanged<Serial?> onSelected;

  const SerialPickerPanel({
    super.key,
    required this.productId,
    required this.onSelected,
    this.excludeSerialIds = const {},
    this.selectedSerialId,
  });

  @override
  ConsumerState<SerialPickerPanel> createState() => _SerialPickerPanelState();
}

class _SerialPickerPanelState extends ConsumerState<SerialPickerPanel> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Focused on open so a scanner's keystrokes land here without a tap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// A scan ends with Enter. If exactly one unit matches, take it — that is the
  /// point of scanning — then clear the field ready for the next unit.
  void _onSubmitted(List<Serial> visible) {
    if (visible.length == 1) {
      widget.onSelected(visible.single);
      _searchController.clear();
      setState(() => _query = '');
      _searchFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final serialsAsync = ref.watch(availableSerialsProvider(widget.productId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          child: Row(
            children: [
              Icon(Icons.qr_code_2, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.translate('select_serial'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ),
              serialsAsync.maybeWhen(
                data: (all) {
                  final n = _selectable(all).length;
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: n == 0
                          ? cs.error.withValues(alpha: 0.15)
                          : cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l10n
                          .translate('n_in_stock')
                          .replaceAll('{0}', n.toString()),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: n == 0 ? cs.error : cs.primary,
                      ),
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: AdaptiveKeyboardTextField(
            controller: _searchController,
            focusNode: _searchFocus,
            decoration: InputDecoration(
              hintText: l10n.translate('scan_or_search_serial'),
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
            onSubmitted: (_) => serialsAsync.whenData(
                (all) => _onSubmitted(_visible(_selectable(all)))),
          ),
        ),
        Expanded(
          child: serialsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _message(
              icon: Icons.error_outline,
              text: l10n.translate('serials_load_failed'),
              color: cs.error,
            ),
            data: (all) {
              final selectable = _selectable(all);
              if (selectable.isEmpty) {
                // Distinct from "no match": there is genuinely nothing to sell,
                // and the fix is a stock action, not a better search term.
                return _message(
                  icon: Icons.inventory_2_outlined,
                  text: l10n.translate('no_serials_available'),
                  subtitle: l10n.translate('no_serials_available_hint'),
                  color: cs.error,
                );
              }
              final visible = _visible(selectable);
              if (visible.isEmpty) {
                return _message(
                  icon: Icons.search_off,
                  text: l10n.translate('no_serial_matches'),
                  subtitle: _searchController.text.trim(),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final serial = visible[i];
                  final isSelected = serial.id == widget.selectedSerialId;
                  return _SerialRow(
                    serial: serial,
                    isSelected: isSelected,
                    // Tapping the selected row clears it, so a mis-tap is
                    // recoverable without closing the dialog.
                    onTap: () => widget.onSelected(isSelected ? null : serial),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Available minus the units already spoken for by other lines of this order.
  List<Serial> _selectable(List<Serial> all) {
    final keep = <Serial>[];
    for (final s in all) {
      if (s.id != widget.selectedSerialId &&
          widget.excludeSerialIds.contains(s.id)) {
        continue;
      }
      keep.add(s);
    }
    return keep;
  }

  List<Serial> _visible(List<Serial> selectable) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return selectable;
    return selectable.where((s) {
      return s.serialNumber.toLowerCase().contains(q) ||
          (s.code ?? '').toLowerCase().contains(q) ||
          (s.batchCode ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Widget _message({
    required IconData icon,
    required String text,
    String? subtitle,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color ?? cs.outline),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color ?? cs.onSurfaceVariant,
              ),
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SerialRow extends StatelessWidget {
  final Serial serial;
  final bool isSelected;
  final VoidCallback onTap;

  const _SerialRow({
    required this.serial,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? cs.primary.withValues(alpha: 0.12)
          : cs.surfaceContainerHighest.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          // 64px: a comfortable finger target, and tall enough for the serial
          // plus its batch line without either being cramped.
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? cs.primary : cs.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.qr_code_2,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serial.serialNumber,
                      // Monospace: serials are long digit/letter strings read
                      // character by character against a printed label.
                      style: TextStyle(
                        fontSize: 16,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        color: isSelected ? cs.primary : cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((serial.batchCode ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        serial.batchCode!,
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
