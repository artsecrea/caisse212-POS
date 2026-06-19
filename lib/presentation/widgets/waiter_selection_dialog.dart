import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../data/database/app_database.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import 'waiter_profile_dialog.dart';

class WaiterSelectionDialog extends ConsumerStatefulWidget {
  final int? currentTableId;
  final int? currentWaiterId;

  const WaiterSelectionDialog({
    super.key,
    this.currentTableId,
    this.currentWaiterId,
  });

  @override
  ConsumerState<WaiterSelectionDialog> createState() => _WaiterSelectionDialogState();
}

class _WaiterSelectionDialogState extends ConsumerState<WaiterSelectionDialog> {
  String _searchQuery = '';
  int? _selectedAreaId;
  int? _hoveredWaiterId;

  @override
  void initState() {
    super.initState();
    // If a table is selected, get its area to filter waiters
    _initializeAreaFromTable();
  }

  Future<void> _initializeAreaFromTable() async {
    if (widget.currentTableId != null) {
      final database = ref.read(databaseProvider);
      final table = await (database.select(database.areaTables)
        ..where((tbl) => tbl.id.equals(widget.currentTableId!)))
        .getSingleOrNull();
      if (table != null && table.areaId != null && mounted) {
        setState(() {
          _selectedAreaId = table.areaId;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final areasAsync = ref.watch(areasProvider);
    final currentOrder = ref.watch(orderProvider);

    return Dialog(
      // Drop the deprecated `dialogBackgroundColor` — M3 DialogTheme handles
      // surface tinting for both modes automatically.
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.person_pin, size: 28, color: cs.primary),
                const SizedBox(width: 12),
                Text(
                  l10n.translate('select_waiter'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Unselect button if waiter is selected. Treat "remove
                // waiter from order" as a destructive-ish action — use the
                // M3 errorContainer pair so it stands out without going
                // full red (which would clash with cancel/delete buttons).
                if (currentOrder.waiterId != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop({'action': 'unselect'});
                      },
                      icon: const Icon(Icons.clear, size: 18),
                      label: Text(l10n.translate('unselect')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.errorContainer,
                        foregroundColor: cs.onErrorContainer,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Area filter chips
            areasAsync.when(
              data: (areas) {
                if (areas.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.translate('filter_by_area')}:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // All chip
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(l10n.translate('all')),
                              selected: _selectedAreaId == null,
                              onSelected: (selected) {
                                setState(() => _selectedAreaId = null);
                              },
                              selectedColor: cs.primary,
                              backgroundColor: cs.surfaceContainerHigh,
                              labelStyle: TextStyle(
                                color: _selectedAreaId == null
                                    ? cs.onPrimary
                                    : cs.onSurface,
                                fontWeight: _selectedAreaId == null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          // Area chips
                          ...areas.map((area) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(area.name),
                              selected: _selectedAreaId == area.id,
                              onSelected: (selected) {
                                setState(() => _selectedAreaId = selected ? area.id : null);
                              },
                              selectedColor: cs.primary,
                              backgroundColor: cs.surfaceContainerHigh,
                              labelStyle: TextStyle(
                                color: _selectedAreaId == area.id
                                    ? cs.onPrimary
                                    : cs.onSurface,
                                fontWeight: _selectedAreaId == area.id
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // Search bar
            TextField(
              decoration: InputDecoration(
                hintText: l10n.translate('search_waiter'),
                hintStyle: TextStyle(
                  color: cs.onSurfaceVariant,
                ),
                prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                filled: true,
                fillColor: cs.surfaceContainerHigh,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
              },
            ),
            const SizedBox(height: 16),

            // Waiter grid
            Expanded(
              child: _buildWaiterGrid(context, ref, isDark, l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaiterGrid(BuildContext context, WidgetRef ref, bool isDark, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final waitersAsync = ref.watch(waitersByAreaProvider(_selectedAreaId));

    return waitersAsync.when(
      data: (waiters) {
        // Filter by search query
        final filteredWaiters = waiters.where((waiter) {
          if (_searchQuery.isEmpty) return true;
          final fullName = '${waiter.firstName} ${waiter.lastName ?? ''}'.toLowerCase();
          return fullName.contains(_searchQuery);
        }).toList();

        if (filteredWaiters.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_off,
                  size: 64,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.translate('no_waiters_found'),
                  style: TextStyle(
                    fontSize: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 0.95,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: filteredWaiters.length,
          itemBuilder: (context, index) {
            final waiter = filteredWaiters[index];
            return _buildWaiterCard(context, ref, waiter, isDark, l10n);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          'Error: $error',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }

  Widget _buildWaiterCard(BuildContext context, WidgetRef ref, Waiter waiter, bool isDark, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final currentOrder = ref.watch(orderProvider);
    final isSelected = currentOrder.waiterId == waiter.id;
    final isHovered = _hoveredWaiterId == waiter.id;
    final statsAsync = ref.watch(waiterStatsProvider(waiter.id));
    final waiterAreasAsync = ref.watch(waiterAreasProvider(waiter.id));
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    // Tonal stat colors — semantic (orange = pending, red = owed) with
    // shade variants so contrast stays legible in both light and dark mode.
    final ordersHotColor =
        isDark ? Colors.orange.shade300 : Colors.orange.shade800;
    final ordersIdleColor = cs.onSurfaceVariant.withValues(alpha: 0.6);
    final unpaidColor =
        isDark ? Colors.red.shade300 : Colors.red.shade700;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredWaiterId = waiter.id),
      onExit: (_) => setState(() => _hoveredWaiterId = null),
      child: GestureDetector(
        onTap: () {
          final waiterName = '${waiter.firstName} ${waiter.lastName ?? ''}'.trim();
          Navigator.of(context).pop({
            'action': 'select',
            'waiterId': waiter.id,
            'waiterName': waiterName,
          });
        },
        // Long-press = open the waiter profile (balance / history / settle)
        // instead of selecting them for the current order. Resolves area
        // names off the cached areas + waiterAreas providers so the dialog
        // header reads "Bar · Lounge" without a fresh fetch.
        onLongPress: () async {
          final waiterName =
              '${waiter.firstName} ${waiter.lastName ?? ''}'.trim();
          final areaIds = await ref.read(waiterAreasProvider(waiter.id).future);
          final allAreas = await ref.read(areasProvider.future);
          final areaNames = areaIds.isEmpty
              ? <String>[]
              : allAreas
                  .where((a) => areaIds.contains(a.id))
                  .map((a) => a.name)
                  .toList();
          if (!context.mounted) return;
          await showDialog<void>(
            context: context,
            builder: (_) => WaiterProfileDialog(
              waiterId: waiter.id,
              waiterName: waiterName,
              waiterImageUrl: waiter.imageUrl,
              areaNames: areaNames,
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primaryContainer.withValues(alpha: 0.6)
                : isHovered
                    ? cs.surfaceContainerHigh
                    : cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? cs.primary
                  : isHovered
                      ? cs.primary.withValues(alpha: 0.5)
                      : cs.outlineVariant,
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: isHovered || isSelected
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar. Guard the URL — an empty string from `imageUrl`
              // resolves to the working directory as `file:///…` and throws
              // "No host specified in URI" deep in NetworkImage.
              Builder(builder: (_) {
                final raw = waiter.imageUrl?.trim() ?? '';
                final hasValidUrl = raw.startsWith('http://') ||
                    raw.startsWith('https://');
                return CircleAvatar(
                  radius: 24,
                  backgroundColor: isSelected
                      ? cs.primary
                      : cs.surfaceContainerHighest,
                  backgroundImage:
                      hasValidUrl ? NetworkImage(raw) : null,
                  child: hasValidUrl
                      ? null
                      : Text(
                          waiter.firstName[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? cs.onPrimary : cs.onSurface,
                          ),
                        ),
                );
              }),
              const SizedBox(height: 6),

              // Name
              Text(
                '${waiter.firstName} ${waiter.lastName ?? ''}'.trim(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 4),

              // Stats
              statsAsync.when(
                data: (stats) {
                  final totalOrders = stats['totalOrders'] as int;
                  final unpaidTotal = stats['unpaidTotal'] as double;
                  return Column(
                    children: [
                      // Orders count
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long,
                            size: 12,
                            color: totalOrders > 0
                                ? ordersHotColor
                                : ordersIdleColor,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$totalOrders',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: totalOrders > 0
                                  ? ordersHotColor
                                  : ordersIdleColor,
                            ),
                          ),
                        ],
                      ),
                      if (unpaidTotal > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          currencyFormatter.format(unpaidTotal),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: unpaidColor,
                          ),
                        ),
                      ],
                    ],
                  );
                },
                loading: () => const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),

              // Areas served indicator
              waiterAreasAsync.when(
                data: (areaIds) {
                  if (areaIds.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        l10n.translate('serves_all_areas'),
                        style: TextStyle(
                          fontSize: 8,
                          fontStyle: FontStyle.italic,
                          // Tonal "success" tone — switches per-mode so
                          // contrast holds against the card surface.
                          color: isDark
                              ? Colors.green.shade300
                              : Colors.green.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}






