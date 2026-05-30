// filepath: /home/arecrea/prj/posecrea/lib/presentation/widgets/table_selection_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../utils/app_localizations.dart';
import '../../utils/responsive_utils.dart';
import '../../data/database/app_database.dart' as db;

class TableSelectionDialog extends ConsumerStatefulWidget {
  const TableSelectionDialog({Key? key}) : super(key: key);

  @override
  ConsumerState<TableSelectionDialog> createState() => _TableSelectionDialogState();
}

class _TableSelectionDialogState extends ConsumerState<TableSelectionDialog> {
  bool _isGridView = true;
  String _searchQuery = '';
  String _filterOption = 'all'; // all, withOrder, withoutOrder
  int? _selectedAreaId; // null means "All Areas"

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
                  // Show transfer mode title when saved order with table
                  hasTable && isSavedOrder
                      ? l10n.translate('transfer_order')
                      : l10n.translate('select_table'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
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
            const SizedBox(height: 16),

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
                              selectedColor: Theme.of(context).primaryColor,
                              backgroundColor: isDark
                                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                                  : Colors.grey[200],
                              labelStyle: TextStyle(
                                color: _selectedAreaId == null
                                    ? Colors.white
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
                              selectedColor: Theme.of(context).primaryColor,
                              backgroundColor: isDark
                                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                                  : Colors.grey[200],
                              labelStyle: TextStyle(
                                color: _selectedAreaId == area.id
                                    ? Colors.white
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
                          : Colors.grey[100],
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
                        : Colors.grey[100],
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
                        : Colors.grey[100],
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

  const _AvailableTablesTab({
    required this.isGridView,
    required this.searchQuery,
    required this.filterOption,
    required this.selectedAreaId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablesAsync = ref.watch(areaTablesProvider);
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
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  searchQuery.isNotEmpty
                      ? l10n.translate('no_tables_match_search')
                      : l10n.translate('no_tables_available'),
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
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
class _TableCard extends ConsumerWidget {
  final db.AreaTable table;
  final bool isDark;

  const _TableCard({
    required this.table,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasOrder = table.orderId != null;
    final l10n = AppLocalizations.of(context)!;

    return InkWell(
      onTap: () async {
        await _handleTableSelection(context, ref, table);
      },
      onLongPress: hasOrder ? () async {
        await _handleClearTable(context, ref, table);
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
              const SizedBox(height: 4),
              Text(
                '${l10n.translate('capacity')}: ${table.capacity}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
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

  const _TableListItem({
    required this.table,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasOrder = table.orderId != null;
    final l10n = AppLocalizations.of(context)!;

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
          await _handleTableSelection(context, ref, table);
        },
        onLongPress: hasOrder ? () async {
          await _handleClearTable(context, ref, table);
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
          '${l10n.translate('capacity')}: ${table.capacity} • ${hasOrder ? l10n.translate('has_active_order') : l10n.translate('available')}',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
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
Future<void> _handleTableSelection(BuildContext context, WidgetRef ref, db.AreaTable table) async {
  // Load existing order for this table if any
  final orderRepo = ref.read(orderRepositoryProvider);
  final existingOrder = await orderRepo.getOrderByTable(table.id);
  final currentOrder = ref.read(orderProvider);
  final l10n = AppLocalizations.of(context)!;

  // Check if we're in transfer mode (saved order with existing table)
  final isTransferMode = currentOrder.orderId != null && currentOrder.tableId != null;

  if (isTransferMode) {
    // Don't allow transferring to the same table
    if (table.id == currentOrder.tableId) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('already_on_this_table')),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Check if target table has an existing order
    if (existingOrder != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('table_has_order')),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Show confirmation dialog for transfer
    if (context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.translate('transfer_order')),
          content: Text(
            '${l10n.translate('transfer_order_confirm')} ${currentOrder.tableName} ${l10n.translate('to')} ${table.name}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.translate('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text(l10n.translate('transfer')),
            ),
          ],
        ),
      );

      if (confirmed == true && context.mounted) {
        Navigator.of(context).pop({
          'id': table.id,
          'name': table.name,
          'action': 'transfer',
          'oldTableId': currentOrder.tableId,
        });
      }
    }
    return;
  }

  if (context.mounted) {
    Navigator.of(context).pop({
      'id': table.id,
      'name': table.name,
      'existingOrder': existingOrder,
    });
  }
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
