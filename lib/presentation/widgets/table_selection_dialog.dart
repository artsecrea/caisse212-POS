// filepath: /home/arecrea/prj/posecrea/lib/presentation/widgets/table_selection_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../utils/button_styles.dart';

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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 700,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Select Table',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              tabs: const [
                Tab(text: 'Available Tables'),
                Tab(text: 'Active Orders'),
              ],
            ),
            const SizedBox(height: 16),
            // Search and filter controls
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search tables...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _filterOption,
                  icon: const Icon(Icons.filter_list),
                  underline: Container(),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Tables')),
                    DropdownMenuItem(value: 'withOrder', child: Text('With Order')),
                    DropdownMenuItem(value: 'withoutOrder', child: Text('Available')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _filterOption = value!;
                    });
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                  onPressed: () {
                    setState(() {
                      _isGridView = !_isGridView;
                    });
                  },
                  tooltip: _isGridView ? 'Switch to List View' : 'Switch to Grid View',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _AvailableTablesTab(
                    isGridView: _isGridView,
                    searchQuery: _searchQuery,
                    filterOption: _filterOption,
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

  const _AvailableTablesTab({
    required this.isGridView,
    required this.searchQuery,
    required this.filterOption,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablesAsync = ref.watch(areaTablesProvider);

    return tablesAsync.when(
      data: (tables) {
        // Apply filters
        var filteredTables = tables.where((table) {
          // Search filter
          if (searchQuery.isNotEmpty) {
            final matchesSearch = table.name.toLowerCase().contains(searchQuery);
            if (!matchesSearch) return false;
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
                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  searchQuery.isNotEmpty
                      ? 'No tables match your search'
                      : 'No tables available',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        if (isGridView) {
          return GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: filteredTables.length,
            itemBuilder: (context, index) {
              final table = filteredTables[index];
              return _buildTableGridCard(context, ref, table);
            },
          );
        } else {
          return ListView.builder(
            itemCount: filteredTables.length,
            itemBuilder: (context, index) {
              final table = filteredTables[index];
              return _buildTableListTile(context, ref, table);
            },
          );
        }
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
    );
  }

  Widget _buildTableGridCard(BuildContext context, WidgetRef ref, dynamic table) {
    final hasOrder = table.orderId != null;

    return InkWell(
      onTap: () async {
        await _handleTableSelection(context, ref, table);
      },
      onLongPress: hasOrder ? () async {
        await _handleClearTable(context, ref, table);
      } : null,
      child: Card(
        color: hasOrder ? Colors.orange[50] : Colors.green[50],
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.table_restaurant,
                color: hasOrder ? Colors.orange[700] : Colors.green[700],
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                table.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                'Capacity: ${table.capacity ?? 'N/A'}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: hasOrder ? Colors.orange[700] : Colors.green[700],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  hasOrder ? 'Has Order' : 'Available',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableListTile(BuildContext context, WidgetRef ref, dynamic table) {
    final hasOrder = table.orderId != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListTile(
        onTap: () async {
          await _handleTableSelection(context, ref, table);
        },
        onLongPress: hasOrder ? () async {
          await _handleClearTable(context, ref, table);
        } : null,
        leading: CircleAvatar(
          backgroundColor: hasOrder ? Colors.orange[100] : Colors.green[100],
          child: Icon(
            Icons.table_restaurant,
            color: hasOrder ? Colors.orange[700] : Colors.green[700],
          ),
        ),
        title: Text(
          table.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          'Capacity: ${table.capacity ?? 'N/A'} • ${hasOrder ? 'Has active order' : 'Available'}',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: hasOrder ? Colors.orange[700] : Colors.green[700],
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

  Future<void> _handleTableSelection(BuildContext context, WidgetRef ref, dynamic table) async {
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

  Future<void> _handleClearTable(BuildContext context, WidgetRef ref, dynamic table) async {
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

