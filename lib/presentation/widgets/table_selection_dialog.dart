// filepath: /home/arecrea/prj/posecrea/lib/presentation/widgets/table_selection_dialog.dart

import 'package:flutter/material.dart';
import '../../providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/responsive_utils.dart';
import '../../data/database/app_database.dart' as db;
import 'call_waiter_dialog.dart';

class TableSelectionDialog extends ConsumerStatefulWidget {
  const TableSelectionDialog({Key? key}) : super(key: key);

  @override
  ConsumerState<TableSelectionDialog> createState() => _TableSelectionDialogState();
}

class _TableSelectionDialogState extends ConsumerState<TableSelectionDialog> {
  @override
  void initState() {
    super.initState();
    // Repair the floor before showing it.
    //
    // Occupancy is a pointer that whichever path finished the order is meant
    // to clear, and a path that forgot leaves a table showing occupied with
    // nobody at it — which the cashier can only fix by knowing that a manual
    // clear exists. Recomputing it here means the picker is right whatever
    // happened before it opened. Unawaited: the list is a stream, so a release
    // simply arrives as an update rather than holding the dialog closed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(orderRepositoryProvider)
          .reconcileTableOccupancy(
            freeOnPayment:
                ref.read(settingsProvider).autoClearTableAfterPaying,
          )
          .catchError((Object e) {
        // Never block the picker on a repair: an unrepaired floor is still a
        // usable one.
        debugPrint('Table occupancy sweep failed: $e');
        return 0;
      });
    });
  }

  bool _isGridView = true;
  String _searchQuery = '';
  String _filterOption = 'all'; // all, withOrder, withoutOrder
  int? _selectedAreaId; // null means "All Areas"
  int? _selectedWaiterId; // null means "All waiters"

  /// Armed by the Transfer button, and only then does tapping a table move the
  /// order instead of opening it.
  ///
  /// Deliberately a mode rather than a prompt: asking "transfer or switch?" on
  /// every tap put a question in front of the cashier they had not asked, on
  /// the most-used action in the app. Moving a bill between tables is rare and
  /// deliberate, so it gets a button, and the rest of the time a tap is just a
  /// tap.
  bool _transferMode = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final areasAsync = ref.watch(areasProvider);
    final currentOrder = ref.watch(orderProvider);
    final hasTable = currentOrder.tableId != null;
    final isSavedOrder = currentOrder.orderId != null;
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      backgroundColor: Theme.of(context).dialogBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogWidth(context, 800),
        height: 650,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Text(
                  _transferMode
                      ? l10n.translate('transfer_order')
                      : l10n.translate('select_table'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                // Only offered when there is something to move: a saved order
                // that is currently sitting on a table.
                if (hasTable && isSavedOrder)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _transferMode
                        ? FilledButton.icon(
                            onPressed: () =>
                                setState(() => _transferMode = false),
                            icon: const Icon(Icons.close, size: 18),
                            label: Text(l10n.translate('cancel')),
                          )
                        : OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _transferMode = true),
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: Text(l10n.translate('transfer')),
                          ),
                  ),
                // Show current table info when in transfer mode
                if (hasTable && isSavedOrder)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.blue[900] : Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.blue[700]! : Colors.blue[200]!,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.table_restaurant,
                            size: 16,
                            color: isDark ? Colors.blue[300] : Colors.blue[700],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${l10n.translate('current')}: ${currentOrder.tableName}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.blue[300] : Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Unselect button - only show if a table is selected AND order is NOT saved
                if (hasTable && !isSavedOrder)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop({
                          'action': 'unselect',
                        });
                      },
                      icon: const Icon(Icons.clear, size: 18),
                      label: Text(l10n.translate('unselect_table')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.orange[800]
                            : Colors.orange[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // What the floor is holding. The two figures a cashier taking
            // over a shift asks for first, and the reason the per-table
            // amounts below exist at all.
            const _FloorTotalsBar(),
            const SizedBox(height: 12),

            // Area Selection Chips
            areasAsync.when(
              data: (areas) {
                if (areas.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.translate('select_area')}:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // "All" chip
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(l10n.translate('all')),
                              selected: _selectedAreaId == null,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedAreaId = null;
                                });
                              },
                              selectedColor: Theme.of(context).colorScheme.primary,
                              backgroundColor:
                                  Theme.of(context).colorScheme.surfaceContainerHighest,
                              labelStyle: TextStyle(
                                color: _selectedAreaId == null
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurface,
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
                                setState(() {
                                  _selectedAreaId = selected ? area.id : null;
                                });
                              },
                              selectedColor: Theme.of(context).colorScheme.primary,
                              backgroundColor:
                                  Theme.of(context).colorScheme.surfaceContainerHighest,
                              labelStyle: TextStyle(
                                color: _selectedAreaId == area.id
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurface,
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

            // Search and filter controls
            Row(
              children: [
                Expanded(
                  child: TextField(
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: l10n.translate('search_tables'),
                      hintStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      isDense: true,
                      filled: true,
                      fillColor: isDark
                          ? Theme.of(context).colorScheme.surfaceContainerHighest
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                        // When searching, show all areas
                        if (_searchQuery.isNotEmpty) {
                          _selectedAreaId = null;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                    ),
                  ),
                  child: DropdownButton<String>(
                    value: _filterOption,
                    icon: Icon(
                      Icons.filter_list,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                    underline: Container(),
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(l10n.translate('all_tables')),
                      ),
                      DropdownMenuItem(
                        value: 'withOrder',
                        child: Text(l10n.translate('with_order')),
                      ),
                      DropdownMenuItem(
                        value: 'withoutOrder',
                        child: Text(l10n.translate('available')),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _filterOption = value!;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Who is on the floor. Only the waiters actually holding a
                // table are listed: a roster of everyone who has ever worked
                // here is a scrolling list of dead ends.
                Consumer(builder: (context, ref, _) {
                  final waiters = ref.watch(waitersProvider).valueOrNull ?? [];
                  final onFloor =
                      ref.watch(orderWaiterIdsProvider).valueOrNull?.values.toSet() ??
                          const <int>{};
                  final shown =
                      waiters.where((w) => onFloor.contains(w.id)).toList();
                  if (shown.isEmpty) return const SizedBox.shrink();
                  // A waiter who leaves the floor while their filter is active
                  // would otherwise leave the dropdown on a value it no longer
                  // offers, which throws.
                  final value =
                      shown.any((w) => w.id == _selectedWaiterId)
                          ? _selectedWaiterId
                          : null;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withOpacity(0.5),
                      ),
                    ),
                    child: DropdownButton<int?>(
                      value: value,
                      icon: Icon(
                        Icons.person_outline,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7),
                      ),
                      underline: Container(),
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(l10n.translate('all_waiters')),
                        ),
                        for (final w in shown)
                          DropdownMenuItem<int?>(
                            value: w.id,
                            child: Text(
                                '${w.firstName} ${w.lastName ?? ''}'.trim()),
                          ),
                      ],
                      onChanged: (v) => setState(() => _selectedWaiterId = v),
                    ),
                  );
                }),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _isGridView ? Icons.view_list : Icons.grid_view,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: () {
                    setState(() {
                      _isGridView = !_isGridView;
                    });
                  },
                  tooltip: _isGridView ? l10n.translate('switch_to_list_view') : l10n.translate('switch_to_grid_view'),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Content
            Expanded(
              child: _AvailableTablesTab(
                isGridView: _isGridView,
                searchQuery: _searchQuery,
                filterOption: _filterOption,
                selectedAreaId: _selectedAreaId,
                selectedWaiterId: _selectedWaiterId,
                transferMode: _transferMode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailableTablesTab extends ConsumerWidget {
  final bool isGridView;
  final String searchQuery;
  final String filterOption;
  final int? selectedAreaId;
  final int? selectedWaiterId;
  final bool transferMode;

  const _AvailableTablesTab({
    required this.isGridView,
    required this.searchQuery,
    required this.filterOption,
    required this.selectedAreaId,
    required this.selectedWaiterId,
    required this.transferMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablesAsync = ref.watch(areaTablesProvider);
    final waiterByOrder =
        ref.watch(orderWaiterIdsProvider).valueOrNull ?? const <int, int>{};
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return tablesAsync.when(
      data: (tables) {
        // Apply filters
        var filteredTables = tables.where((table) {
          // Search filter - when searching, show all areas
          if (searchQuery.isNotEmpty) {
            final matchesSearch = table.name.toLowerCase().contains(searchQuery);
            if (!matchesSearch) return false;
          } else {
            // Area filter - only when not searching
            if (selectedAreaId != null && table.areaId != selectedAreaId) {
              return false;
            }
          }

          // Order status filter
          final hasOrder = table.orderId != null;
          if (filterOption == 'withOrder' && !hasOrder) return false;
          if (filterOption == 'withoutOrder' && hasOrder) return false;

          // Waiter filter. An empty table has no waiter, so it cannot match a
          // named one — filtering by waiter is asking "where is Amina", not
          // "which tables might she take".
          if (selectedWaiterId != null) {
            final orderId = table.orderId;
            if (orderId == null) return false;
            if (waiterByOrder[orderId] != selectedWaiterId) return false;
          }

          return true;
        }).toList();

        if (filteredTables.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  searchQuery.isNotEmpty
                      ? l10n.translate('no_tables_match_search')
                      : l10n.translate('no_tables_available'),
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        if (isGridView) {
          return GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              childAspectRatio: 1.25,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: filteredTables.length,
            itemBuilder: (context, index) {
              final table = filteredTables[index];
              return _TableCard(
                table: table,
                isDark: isDark,
                transferMode: transferMode,
              );
            },
          );
        } else {
          return ListView.builder(
            padding: const EdgeInsets.all(4),
            itemCount: filteredTables.length,
            itemBuilder: (context, index) {
              final table = filteredTables[index];
              return _TableListItem(
                table: table,
                isDark: isDark,
                transferMode: transferMode,
              );
            },
          );
        }
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) {
        final l10n = AppLocalizations.of(context)!;
        return Center(
          child: Text(
            '${l10n.translate('error_loading_tables')}: $error',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        );
      },
    );
  }
}

// Table Card Widget for Grid View
/// The name of the waiter on [table], or null when nobody is.
///
/// Read through the order rather than the table: `area_tables` only holds an
/// order id, and the waiter belongs to the order. Shared by the card and the
/// list row so the two views can never disagree about who is on a table.
String? _waiterNameForTable(WidgetRef ref, db.AreaTable table) {
  final orderId = table.orderId;
  if (orderId == null) return null;
  final waiterId = ref.watch(orderWaiterIdsProvider).valueOrNull?[orderId];
  if (waiterId == null) return null;
  final waiters = ref.watch(waitersProvider).valueOrNull;
  if (waiters == null) return null;
  for (final w in waiters) {
    if (w.id == waiterId) {
      final name = '${w.firstName} ${w.lastName ?? ''}'.trim();
      return name.isEmpty ? null : name;
    }
  }
  return null;
}

class _TableCard extends ConsumerWidget {
  final db.AreaTable table;
  final bool isDark;

  final bool transferMode;

  const _TableCard({
    required this.table,
    required this.isDark,
    required this.transferMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasOrder = table.orderId != null;
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyFormatterProvider);
    final due = ref.watch(unpaidTablesProvider).valueOrNull?.byTableId[table.id];

    return InkWell(
      onTap: () async {
        await _handleTableSelection(context, ref, table,
            transferMode: transferMode);
      },
      onLongPress: hasOrder ? () async {
        await _handleTableLongPress(context, ref, table);
      } : null,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        color: hasOrder
            ? (isDark ? Colors.orange[900]!.withOpacity(0.3) : Colors.orange[50])
            : (isDark ? Colors.green[900]!.withOpacity(0.3) : Colors.green[50]),
        elevation: isDark ? 4 : 2,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: hasOrder
                ? (isDark ? Colors.orange[700]! : Colors.orange[200]!)
                : (isDark ? Colors.green[700]! : Colors.green[200]!),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.table_restaurant,
                color: hasOrder
                    ? (isDark ? Colors.orange[400] : Colors.orange[700])
                    : (isDark ? Colors.green[400] : Colors.green[700]),
                size: 36,
              ),
              const SizedBox(height: 4),
              Text(
                table.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              if (_waiterNameForTable(ref, table) case final waiterName?)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    waiterName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.orange[300]
                          : Colors.orange[800],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 2),
              if (due == null)
                Text(
                  '${l10n.translate('capacity')}: ${table.capacity}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
                // What is still owed, in the card's own colour so it reads at
                // a glance from across the counter.
                Text(
                  currency.format(due.due),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.orange[300] : Colors.orange[900],
                  ),
                ),
                // Only worth the line when something HAS been collected —
                // otherwise every occupied table would carry a redundant
                // "paid 0".
                if (due.paid > 0.005)
                  Text(
                    '${l10n.translate('paid')} ${currency.format(due.paid)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.green[300] : Colors.green[800],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Table List Item Widget for List View
class _TableListItem extends ConsumerWidget {
  final db.AreaTable table;
  final bool isDark;

  final bool transferMode;

  const _TableListItem({
    required this.table,
    required this.isDark,
    required this.transferMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasOrder = table.orderId != null;
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyFormatterProvider);
    final due = ref.watch(unpaidTablesProvider).valueOrNull?.byTableId[table.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isDark ? 2 : 1,
      color: isDark
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: hasOrder
              ? (isDark ? Colors.orange[700]!.withOpacity(0.5) : Colors.orange[200]!)
              : (isDark ? Colors.green[700]!.withOpacity(0.5) : Colors.green[200]!),
          width: 1,
        ),
      ),
      child: ListTile(
        onTap: () async {
          await _handleTableSelection(context, ref, table,
              transferMode: transferMode);
        },
        onLongPress: hasOrder ? () async {
          await _handleTableLongPress(context, ref, table);
        } : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: hasOrder
              ? (isDark ? Colors.orange[900]!.withOpacity(0.5) : Colors.orange[100])
              : (isDark ? Colors.green[900]!.withOpacity(0.5) : Colors.green[100]),
          child: Icon(
            Icons.table_restaurant,
            color: hasOrder
                ? (isDark ? Colors.orange[400] : Colors.orange[700])
                : (isDark ? Colors.green[400] : Colors.green[700]),
          ),
        ),
        title: Text(
          table.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          [
            due == null
                ? '${l10n.translate('capacity')}: ${table.capacity} • ${hasOrder ? l10n.translate('has_active_order') : l10n.translate('available')}'
                : '${due.order.code} • '
                    '${l10n.translate('paid')} ${currency.format(due.paid)} • '
                    '${l10n.translate('remaining')} ${currency.format(due.due)}',
            // Same lookup the grid card uses, so the two views agree.
            if (_waiterNameForTable(ref, table) case final w?)
              '${l10n.translate('waiter')}: $w',
          ].join(' • '),
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: hasOrder
                ? (isDark ? Colors.orange[700] : Colors.orange[600])
                : (isDark ? Colors.green[700] : Colors.green[600]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            hasOrder ? l10n.translate('occupied') : l10n.translate('free'),
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// Helper functions
Future<void> _handleTableSelection(
    BuildContext context, WidgetRef ref, db.AreaTable table,
    {bool transferMode = false}) async {
  // Load existing order for this table if any
  final orderRepo = ref.read(orderRepositoryProvider);
  final existingOrder = await orderRepo.getOrderByTable(table.id);
  // Everything below touches the dialog's context, and the lookup above is an
  // await: the picker can be gone by the time it returns.
  if (!context.mounted) return;

  // Transfer was armed explicitly, so a tap MOVES the bill rather than
  // opening the table. Refused onto an occupied one: the repository would
  // refuse it anyway, and saying so here costs the cashier nothing.
  if (transferMode) {
    final currentOrder = ref.read(orderProvider);
    final l10n = AppLocalizations.of(context)!;
    if (table.id == currentOrder.tableId) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.translate('already_on_this_table')),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    if (existingOrder != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.translate('table_has_active_order')),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    Navigator.of(context).pop({
      'id': table.id,
      'name': table.name,
      'action': 'transfer',
      'oldTableId': currentOrder.tableId,
    });
    return;
  }

  // Picking a table just goes to that table. There is no transfer prompt and
  // no "transfer or switch?" question: moving an order between tables is its
  // own deliberate action, not something to be asked about every time somebody
  // taps the floor plan. Whether the cashier's current cart survives is
  // decided downstream, and only genuinely unsaved work stops them.
  if (context.mounted) {
    Navigator.of(context).pop({
      'id': table.id,
      'name': table.name,
      'existingOrder': existingOrder,
    });
  }
}

/// The waiter on [table], read (not watched) for use inside a callback.
///
/// Goes through the order for the same reason [_waiterNameForTable] does:
/// `area_tables` holds only an order id, and the waiter belongs to the order.
({int id, String name})? _waiterOnTable(WidgetRef ref, db.AreaTable table) {
  final orderId = table.orderId;
  if (orderId == null) return null;
  final waiterId = ref.read(orderWaiterIdsProvider).valueOrNull?[orderId];
  if (waiterId == null) return null;
  final waiters = ref.read(waitersProvider).valueOrNull;
  if (waiters == null) return null;
  for (final w in waiters) {
    if (w.id != waiterId) continue;
    final name = '${w.firstName} ${w.lastName ?? ''}'.trim();
    return name.isEmpty ? null : (id: w.id, name: name);
  }
  return null;
}

/// Long-press on an occupied table.
///
/// Clearing the table is what this gesture has always done, and it stays the
/// only outcome unless calls are on AND somebody is actually assigned — a
/// chooser offering to call nobody would be a worse gesture than the one it
/// replaced.
Future<void> _handleTableLongPress(
    BuildContext context, WidgetRef ref, db.AreaTable table) async {
  final l10n = AppLocalizations.of(context)!;
  final waiter = ref.read(settingsProvider).waiterCallEnabled
      ? _waiterOnTable(ref, table)
      : null;

  if (waiter == null) {
    await _handleClearTable(context, ref, table);
    return;
  }

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(table.name),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop('call'),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.campaign),
            title: Text(l10n.translate('call_waiter')),
            subtitle: Text(waiter.name),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop('clear'),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(l10n.translate('clear_table')),
          ),
        ),
      ],
    ),
  );

  if (!context.mounted || choice == null) return;
  if (choice == 'call') {
    await showCallWaiterDialog(
      context,
      waiterId: waiter.id,
      waiterName: waiter.name,
      tableId: table.id,
      tableName: table.name,
    );
    return;
  }
  await _handleClearTable(context, ref, table);
}

Future<void> _handleClearTable(BuildContext context, WidgetRef ref, db.AreaTable table) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final order = await orderRepo.getOrderByTable(table.id);

      if (order == null || order.orderId == null) return;

      // Check if there are unpaid items
      final hasUnpaidItems = order.items.any((item) => item.ticketId == null);

      if (hasUnpaidItems) {
        // Show dialog with options to pay or clear
        final action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.translate('clear_table')),
            content: Text(
              '${table.name} ${l10n.translate('has_unpaid_items')}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: Text(l10n.translate('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 'clear'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: Text(l10n.translate('just_clear')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 'pay'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: Text(l10n.translate('pay_first')),
              ),
            ],
          ),
        );

        if (action == 'pay' && context.mounted) {
          // Navigate back with pay action
          Navigator.of(context).pop({
            'id': table.id,
            'name': table.name,
            'action': 'pay',
            'order': order,
          });
          return;
        } else if (action != 'clear') {
          return; // User cancelled
        }
      } else {
        // All items are paid, just confirm
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.translate('clear_table')),
            content: Text(
              '${l10n.translate('confirm_clear_table')} ${table.name}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.translate('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: Text(l10n.translate('clear')),
              ),
            ],
          ),
        );

        if (confirmed != true) return;
      }

      // Clear the table by setting orderId to null
      if (context.mounted) {
        await orderRepo.clearTableOrder(table.id);

        // Refresh the tables list
        ref.invalidate(areaTablesProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${table.name} ${l10n.translate('has_been_cleared')}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.translate('error_clearing_table')}: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

/// Paid against still-owed across every occupied table.
///
/// Its own widget so it rebuilds on the stream without dragging the whole
/// dialog with it, and so it can simply not be there while the first figures
/// are still being computed — a bar that flashes zeros and then corrects
/// itself is worse than one that arrives a frame late.
class _FloorTotalsBar extends ConsumerWidget {
  const _FloorTotalsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyFormatterProvider);
    final summary = ref.watch(unpaidTablesProvider).valueOrNull;
    // Only what the tables are actually holding, so this bar is exactly the
    // sum of the amounts on the cards below it. A stray unpaid order still
    // pointing at a table it was cleared from belongs on the Z's unpaid sheet,
    // not in the floor's running total.
    final seated = summary?.seatedTables.toList() ?? const [];
    if (seated.isEmpty) {
      return const SizedBox.shrink();
    }
    final value = seated.fold(0.0, (s, e) => s + e.total);
    final paid = seated.fold(0.0, (s, e) => s + e.paid);
    final owed = seated.fold(0.0, (s, e) => s + e.due);
    final scheme = Theme.of(context).colorScheme;

    Widget figure(String label, String value, Color color) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                  fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          figure(
            '${l10n.translate('occupied')} (${seated.length})',
            currency.format(value),
            scheme.onSurface,
          ),
          const SizedBox(width: 22),
          figure(l10n.translate('paid'), currency.format(paid),
              Colors.green.shade700),
          const Spacer(),
          figure(l10n.translate('pending_payment'), currency.format(owed),
              Colors.orange.shade800),
        ],
      ),
    );
  }
}
