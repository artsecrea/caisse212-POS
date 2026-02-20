// filepath: /home/arecrea/prj/posecrea/lib/presentation/widgets/table_selection_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../utils/button_styles.dart';
import '../../data/database/app_database.dart' as db;

class TableSelectionDialog extends ConsumerStatefulWidget {
  const TableSelectionDialog({Key? key}) : super(key: key);

  @override
  ConsumerState<TableSelectionDialog> createState() => _TableSelectionDialogState();
}

class _TableSelectionDialogState extends ConsumerState<TableSelectionDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isGridView = true;
  String _searchQuery = '';
  String _filterOption = 'all'; // all, withOrder, withoutOrder
  int? _selectedAreaId; // null means "All Areas"

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final areasAsync = ref.watch(areasProvider);
    final currentOrder = ref.watch(orderProvider);
    final hasTable = currentOrder.tableId != null;

    return Dialog(
      backgroundColor: Theme.of(context).dialogBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 800,
        height: 650,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Text(
                  'Select Table',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                // Unselect button - only show if a table is selected
                if (hasTable)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop({
                          'action': 'unselect',
                        });
                      },
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text('Unselect Table'),
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

            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              indicatorColor: Theme.of(context).primaryColor,
              tabs: const [
                Tab(text: 'Available Tables'),
                Tab(text: 'Active Orders'),
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
                      'Select Area:',
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
                              label: const Text('All'),
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
                      hintText: 'Search tables...',
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
                        child: Text('All Tables'),
                      ),
                      DropdownMenuItem(
                        value: 'withOrder',
                        child: Text('With Order'),
                      ),
                      DropdownMenuItem(
                        value: 'withoutOrder',
                        child: Text('Available'),
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
                  tooltip: _isGridView ? 'Switch to List View' : 'Switch to Grid View',
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
              child: TabBarView(
                controller: _tabController,
                children: [
                  _AvailableTablesTab(
                    isGridView: _isGridView,
                    searchQuery: _searchQuery,
                    filterOption: _filterOption,
                    selectedAreaId: _selectedAreaId,
                  ),
                  _ActiveOrdersTab(),
                ],
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
                      ? 'No tables match your search'
                      : 'No tables available',
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
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
      error: (error, stack) => Center(
        child: Text(
          'Error loading tables: $error',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
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
                'Capacity: ${table.capacity}',
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
          'Capacity: ${table.capacity} • ${hasOrder ? 'Has active order' : 'Available'}',
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
            hasOrder ? 'Occupied' : 'Free',
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

  if (context.mounted) {
    Navigator.of(context).pop({
      'id': table.id,
      'name': table.name,
      'existingOrder': existingOrder,
    });
  }
}

Future<void> _handleClearTable(BuildContext context, WidgetRef ref, db.AreaTable table) async {
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
            title: const Text('Clear Table'),
            content: Text(
              '${table.name} has unpaid items. What would you like to do?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 'clear'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Just Clear'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 'pay'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Pay First'),
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
            title: const Text('Clear Table'),
            content: Text(
              'Are you sure you want to clear ${table.name}? The order will remain but the table will be freed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Clear'),
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
              content: Text('${table.name} has been cleared'),
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
            content: Text('Error clearing table: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }


class _ActiveOrdersTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderRepo = ref.watch(orderRepositoryProvider);

    return FutureBuilder(
      future: orderRepo.getTablesWithOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final tablesWithOrders = snapshot.data ?? [];

        if (tablesWithOrders.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No active orders',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: tablesWithOrders.length,
          itemBuilder: (context, index) {
            final tableWithOrder = tablesWithOrders[index];
            final table = tableWithOrder.table;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.orange[100],
                          radius: 24,
                          child: Icon(
                            Icons.table_restaurant,
                            color: Colors.orange[700],
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                table.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${tableWithOrder.orderCount} order(s) • Capacity: ${table.capacity}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$${tableWithOrder.total.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            Text(
                              _formatTime(tableWithOrder.lastUpdated),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            // Load order and open payment screen
                            final orderRepo = ref.read(orderRepositoryProvider);
                            final order = await orderRepo.getOrderByTable(table.id);

                            if (order != null && context.mounted) {
                              Navigator.of(context).pop({
                                'id': table.id,
                                'name': table.name,
                                'action': 'pay',
                                'order': order,
                              });
                            }
                          },
                          icon: const Icon(Icons.payment, size: 22),
                          label: const Text('Pay'),
                          style: AppButtonStyles.outlinedButtonStyle(
                            foregroundColor: Colors.green[700],
                            borderColor: Colors.green[700]!,
                            isLarge: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            // Load existing order to add more items
                            final orderRepo = ref.read(orderRepositoryProvider);
                            final existingOrder = await orderRepo.getOrderByTable(table.id);

                            if (context.mounted) {
                              Navigator.of(context).pop({
                                'id': table.id,
                                'name': table.name,
                                'action': 'addItems',
                                'existingOrder': existingOrder,
                              });
                            }
                          },
                          icon: const Icon(Icons.add, size: 22),
                          label: const Text('Add Items'),
                          style: AppButtonStyles.elevatedButtonStyle(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            isLarge: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () async {
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
                                    title: const Text('Clear Table'),
                                    content: Text(
                                      '${table.name} has unpaid items. What would you like to do?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, 'cancel'),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context, 'clear'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Just Clear'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context, 'pay'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Pay First'),
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
                                    title: const Text('Clear Table'),
                                    content: Text(
                                      'Are you sure you want to clear ${table.name}? The order will remain but the table will be freed.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Clear'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmed != true) return;
                              }

                              // Clear the table by setting orderId to null
                              if (context.mounted) {
                                await orderRepo.clearTableOrder(table.id);

                                // Refresh and close dialog
                                ref.invalidate(areaTablesProvider);

                                if (context.mounted) {
                                  Navigator.of(context).pop({
                                    'action': 'cleared',
                                    'tableName': table.name,
                                  });
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error clearing table: $e'),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.clear),
                          color: Colors.red[700],
                          tooltip: 'Clear Table',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}

