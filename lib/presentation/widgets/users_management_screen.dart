import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data_table_2/data_table_2.dart';
import 'dart:convert';
import '../../data/database/app_database.dart';
import '../../providers/user_provider.dart';

class UsersManagementScreen extends ConsumerStatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  ConsumerState<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends ConsumerState<UsersManagementScreen> {
  // Filters
  String _typeFilter = 'ALL';
  String _searchQuery = '';

  // Pagination
  int _currentPage = 0;
  final int _rowsPerPage = 10;

  // Sorting
  int? _sortColumnIndex;
  bool _sortAscending = true;

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userRepo = ref.watch(userRepositoryProvider);

    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildFiltersBar(),
          Expanded(
            child: FutureBuilder<List<User>>(
              future: userRepo.getAllUsers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _buildErrorView(snapshot.error.toString());
                }

                List<User> users = snapshot.data ?? [];
                users = _applyFilters(users);
                users = _applySorting(users);

                if (users.isEmpty) {
                  return _buildEmptyView();
                }

                return _buildUsersTable(users);
              },
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Users Management'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(() {}),
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildFiltersBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, username...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _currentPage = 0;
                });
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildTypeDropdown(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: _typeFilter,
      decoration: InputDecoration(
        labelText: 'User Type',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: const [
        DropdownMenuItem(value: 'ALL', child: Text('All Types')),
        DropdownMenuItem(value: 'admin', child: Text('Admin')),
        DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
        DropdownMenuItem(value: 'waiter', child: Text('Waiter')),
      ],
      onChanged: (value) {
        setState(() {
          _typeFilter = value!;
          _currentPage = 0;
        });
      },
    );
  }

  Widget _buildUsersTable(List<User> users) {
    final paginatedUsers = _paginateUsers(users);
    final totalPages = (users.length / _rowsPerPage).ceil();

    return Column(
      children: [
        Expanded(
          child: DataTable2(
            columnSpacing: 12,
            horizontalMargin: 12,
            minWidth: 1000,
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            headingRowColor: MaterialStateProperty.all(Colors.grey[200]),
            columns: [
              DataColumn2(
                label: const Text('ID', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Username', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Full Name', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.L,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Type', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Created At', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Last Login', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                fixedWidth: 80,
              ),
            ],
            rows: paginatedUsers.map((user) => _buildDataRow(user)).toList(),
          ),
        ),
        _buildPaginationControls(users.length, totalPages),
      ],
    );
  }

  DataRow _buildDataRow(User user) {
    return DataRow(
      cells: [
        DataCell(Text(user.id.toString())),
        DataCell(Text(user.username)),
        DataCell(Text('${user.firstName} ${user.lastName}')),
        DataCell(_buildTypeChip(user.type)),
        DataCell(Text(_formatDate(user.createdAt))),
        DataCell(Text(user.lastLogin != null ? _formatDate(user.lastLogin!) : 'Never')),
        DataCell(
          IconButton(
            icon: const Icon(Icons.visibility, size: 20),
            onPressed: () => _showUserDetails(user),
            tooltip: 'View Details',
          ),
        ),
      ],
    );
  }

  Widget _buildTypeChip(String type) {
    Color color;
    switch (type.toLowerCase()) {
      case 'admin':
        color = Colors.red;
        break;
      case 'cashier':
        color = Colors.blue;
        break;
      case 'waiter':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildPaginationControls(int totalItems, int totalPages) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${_currentPage * _rowsPerPage + 1}-${((_currentPage + 1) * _rowsPerPage).clamp(0, totalItems)} of $totalItems users',
            style: TextStyle(color: Colors.grey[700]),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _currentPage > 0 ? () => setState(() => _currentPage = 0) : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
              ),
              Text(
                'Page ${_currentPage + 1} of $totalPages',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage = totalPages - 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No users found',
            style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            'Error loading users',
            style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Helper Functions

  List<User> _applyFilters(List<User> users) {
    var filtered = users;

    if (_typeFilter != 'ALL') {
      filtered = filtered.where((u) => u.type == _typeFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((u) {
        return u.username.toLowerCase().contains(query) ||
            u.firstName.toLowerCase().contains(query) ||
            u.lastName.toLowerCase().contains(query);
      }).toList();
    }

    return filtered;
  }

  List<User> _applySorting(List<User> users) {
    if (_sortColumnIndex == null) return users;

    users.sort((a, b) {
      int comparison = 0;
      switch (_sortColumnIndex) {
        case 0: // ID
          comparison = a.id.compareTo(b.id);
          break;
        case 1: // Username
          comparison = a.username.compareTo(b.username);
          break;
        case 2: // Full Name
          comparison = '${a.firstName} ${a.lastName}'.compareTo('${b.firstName} ${b.lastName}');
          break;
        case 3: // Type
          comparison = a.type.compareTo(b.type);
          break;
        case 4: // Created At
          comparison = a.createdAt.compareTo(b.createdAt);
          break;
        case 5: // Last Login
          if (a.lastLogin == null && b.lastLogin == null) {
            comparison = 0;
          } else if (a.lastLogin == null) {
            comparison = 1;
          } else if (b.lastLogin == null) {
            comparison = -1;
          } else {
            comparison = a.lastLogin!.compareTo(b.lastLogin!);
          }
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });
    return users;
  }

  List<User> _paginateUsers(List<User> users) {
    final start = _currentPage * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, users.length);
    return users.sublist(start, end);
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  // User Details
  void _showUserDetails(User user) {
    showDialog(
      context: context,
      builder: (context) => _UserDetailsDialog(user: user),
    );
  }
}

// User Details Dialog
class _UserDetailsDialog extends StatelessWidget {
  final User user;

  const _UserDetailsDialog({required this.user});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${user.firstName} ${user.lastName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'User Details',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Image
                    if (user.imageUrl != null && user.imageUrl!.isNotEmpty)
                      Center(
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            image: DecorationImage(
                              image: NetworkImage(user.imageUrl!),
                              fit: BoxFit.cover,
                            ),
                            border: Border.all(color: Colors.grey[300]!, width: 2),
                          ),
                        ),
                      )
                    else
                      Center(
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[200],
                            border: Border.all(color: Colors.grey[300]!, width: 2),
                          ),
                          child: Icon(Icons.person, size: 60, color: Colors.grey[400]),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Basic Information
                    const Text('Basic Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildInfoRow('User ID', '#${user.id}'),
                            _buildInfoRow('Username', user.username),
                            _buildInfoRow('First Name', user.firstName),
                            _buildInfoRow('Last Name', user.lastName),
                            _buildInfoRow('Type', user.type.toUpperCase()),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Activity Information
                    const Text('Activity Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildInfoRow('Created At', _formatFullDateTime(user.createdAt)),
                            _buildInfoRow('Updated At', _formatFullDateTime(user.updatedAt)),
                            _buildInfoRow('Last Login', user.lastLogin != null ? _formatFullDateTime(user.lastLogin!) : 'Never'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Permissions
                    const Text('Permissions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _buildPermissions(user.permissions),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissions(String? permissionsJson) {
    if (permissionsJson == null || permissionsJson.isEmpty) {
      return const Text(
        'No permissions set',
        style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
      );
    }

    try {
      final permissions = jsonDecode(permissionsJson) as Map<String, dynamic>;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: permissions.entries.map((entry) {
          final hasPermission = entry.value == true;
          return Chip(
            label: Text(
              entry.key.replaceAll('_', ' ').toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                color: hasPermission ? Colors.green[700] : Colors.red[700],
              ),
            ),
            backgroundColor: hasPermission ? Colors.green[50] : Colors.red[50],
            side: BorderSide(
              color: hasPermission ? Colors.green[700]! : Colors.red[700]!,
            ),
            avatar: Icon(
              hasPermission ? Icons.check_circle : Icons.cancel,
              color: hasPermission ? Colors.green[700] : Colors.red[700],
              size: 18,
            ),
          );
        }).toList(),
      );
    } catch (e) {
      return Text(
        'Invalid permissions format: $permissionsJson',
        style: const TextStyle(color: Colors.red),
      );
    }
  }

  String _formatFullDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }
}

