import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../data/database/app_database.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_localizations.dart';

class UsersManagementScreen extends ConsumerStatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  ConsumerState<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends ConsumerState<UsersManagementScreen> {
  String _typeFilter = 'ALL';
  String _searchQuery = '';
  int _currentPage = 0;
  final int _rowsPerPage = 10;
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
                if (snapshot.hasError) return _buildErrorView(snapshot.error.toString());

                List<User> users = snapshot.data ?? [];
                users = _applyFilters(users);
                users = _applySorting(users);

                if (users.isEmpty) return _buildEmptyView();
                return _buildUsersTable(users);
              },
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final l10n = AppLocalizations.of(context)!;
    return AppBar(
      title: Text(l10n.translate('users_management')),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(() {}),
          tooltip: l10n.translate('refresh'),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildFiltersBar() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.translate('search_by_name'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) => setState(() { _searchQuery = value; _currentPage = 0; }),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: _buildTypeDropdown()),
        ],
      ),
    );
  }

  Widget _buildTypeDropdown() {
    final l10n = AppLocalizations.of(context)!;
    return DropdownButtonFormField<String>(
      value: _typeFilter,
      decoration: InputDecoration(
        labelText: l10n.translate('user_type'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: [
        DropdownMenuItem(value: 'ALL',     child: Text(l10n.translate('all_types'))),
        DropdownMenuItem(value: 'admin',   child: Text(l10n.translate('admin'))),
        DropdownMenuItem(value: 'cashier', child: Text(l10n.translate('cashier'))),
        DropdownMenuItem(value: 'waiter',  child: Text(l10n.translate('waiter'))),
      ],
      onChanged: (value) => setState(() { _typeFilter = value!; _currentPage = 0; }),
    );
  }

  Widget _buildUsersTable(List<User> users) {
    final l10n = AppLocalizations.of(context)!;
    final paginatedUsers = _paginateUsers(users);
    final totalPages = (users.length / _rowsPerPage).ceil().clamp(1, 99999);

    return Column(
      children: [
        Expanded(
          child: DataTable2(
            columnSpacing: 12,
            horizontalMargin: 12,
            minWidth: 900,
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            columns: [
              DataColumn2(
                label: Text(l10n.translate('user_id'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                onSort: _onSort,
              ),
              DataColumn2(
                label: Text(l10n.translate('username'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: _onSort,
              ),
              DataColumn2(
                label: Text(l10n.translate('full_name'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.L,
                onSort: _onSort,
              ),
              DataColumn2(
                label: Text(l10n.translate('user_type'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: _onSort,
              ),
              DataColumn2(
                label: Text(l10n.translate('permissions'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.L,
              ),
              DataColumn2(
                label: Text(l10n.translate('last_login'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: _onSort,
              ),
              DataColumn2(
                label: Text(l10n.translate('actions'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                fixedWidth: 60,
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
    final l10n = AppLocalizations.of(context)!;
    final permCount = _countPermissions(user.permissions);
    final hasAll = user.permissions?.contains('pos:*') == true;

    return DataRow(
      cells: [
        DataCell(Text('#${user.id}', style: const TextStyle(fontWeight: FontWeight.w600))),
        DataCell(Text(user.username)),
        DataCell(Text('${user.firstName} ${user.lastName}')),
        DataCell(_buildTypeChip(user.type)),
        DataCell(
          hasAll
              ? _miniChip('All permissions', Colors.purple)
              : permCount == 0
                  ? Text(l10n.translate('no_permissions'), style: const TextStyle(color: Colors.grey, fontSize: 12))
                  : Text('$permCount ${l10n.translate('permissions').toLowerCase()}',
                      style: const TextStyle(fontSize: 12)),
        ),
        DataCell(Text(user.lastLogin != null ? _formatDate(user.lastLogin!) : l10n.translate('never'),
            style: const TextStyle(fontSize: 12))),
        DataCell(
          IconButton(
            icon: const Icon(Icons.visibility, size: 20),
            onPressed: () => _showUserDetails(user),
            tooltip: l10n.translate('view_details'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeChip(String type) {
    final Color color;
    final String label;
    switch (type.toLowerCase().replaceAll('pos_', '')) {
      case 'admin':
        color = Colors.red;
        label = 'Admin';
        break;
      case 'cashier':
        color = Colors.blue;
        label = 'Cashier';
        break;
      case 'waiter':
        color = Colors.green;
        label = 'Waiter';
        break;
      default:
        color = Colors.grey;
        label = type.toUpperCase();
    }
    return _miniChip(label, color);
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  Widget _buildPaginationControls(int totalItems, int totalPages) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey[300]!))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${l10n.translate('showing')} ${_currentPage * _rowsPerPage + 1}-${((_currentPage + 1) * _rowsPerPage).clamp(0, totalItems)} ${l10n.translate('of')} $totalItems',
            style: TextStyle(color: Colors.grey[700]),
          ),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.first_page), onPressed: _currentPage > 0 ? () => setState(() => _currentPage = 0) : null),
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null),
              Text('${_currentPage + 1} / $totalPages', style: const TextStyle(fontWeight: FontWeight.w600)),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null),
              IconButton(icon: const Icon(Icons.last_page), onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage = totalPages - 1) : null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(l10n.translate('no_users_found'), style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(l10n.translate('try_adjusting_filters'), style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildErrorView(String error) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(l10n.translate('error_loading_users'), style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(error, style: TextStyle(fontSize: 14, color: Colors.grey[500]), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // Helpers

  int _countPermissions(String? permissions) {
    if (permissions == null || permissions.trim().isEmpty) return 0;
    return permissions.split(',').where((p) => p.trim().isNotEmpty).length;
  }

  List<User> _applyFilters(List<User> users) {
    var filtered = users;
    if (_typeFilter != 'ALL') {
      filtered = filtered.where((u) {
        final normalized = u.type.toLowerCase().replaceAll('pos_', '');
        return normalized == _typeFilter.toLowerCase();
      }).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((u) =>
        u.username.toLowerCase().contains(query) ||
        u.firstName.toLowerCase().contains(query) ||
        u.lastName.toLowerCase().contains(query)).toList();
    }
    return filtered;
  }

  List<User> _applySorting(List<User> users) {
    if (_sortColumnIndex == null) return users;
    users.sort((a, b) {
      int cmp = 0;
      switch (_sortColumnIndex) {
        case 0: cmp = a.id.compareTo(b.id); break;
        case 1: cmp = a.username.compareTo(b.username); break;
        case 2: cmp = '${a.firstName} ${a.lastName}'.compareTo('${b.firstName} ${b.lastName}'); break;
        case 3: cmp = a.type.compareTo(b.type); break;
        case 5:
          if (a.lastLogin == null && b.lastLogin == null) cmp = 0;
          else if (a.lastLogin == null) cmp = 1;
          else if (b.lastLogin == null) cmp = -1;
          else cmp = a.lastLogin!.compareTo(b.lastLogin!);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return users;
  }

  List<User> _paginateUsers(List<User> users) {
    final start = _currentPage * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, users.length);
    return users.sublist(start, end);
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() { _sortColumnIndex = columnIndex; _sortAscending = ascending; });
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}/${date.year}  ${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}';
  }

  void _showUserDetails(User user) {
    showDialog(context: context, builder: (_) => _UserDetailsDialog(user: user));
  }
}

// ─── User Details Dialog ───────────────────────────────────────────────────

class _UserDetailsDialog extends StatelessWidget {
  final User user;
  const _UserDetailsDialog({required this.user});

  static const _permissionGroups = <String, List<String>>{
    'Orders':      ['pos:orders:create', 'pos:orders:view', 'pos:orders:update', 'pos:orders:delete'],
    'Tickets':     ['pos:tickets:create', 'pos:tickets:view', 'pos:tickets:print', 'pos:tickets:delete'],
    'Sessions':    ['pos:sessions:start', 'pos:sessions:end', 'pos:sessions:pause', 'pos:sessions:view', 'pos:sessions:delete'],
    'Customers':   ['pos:customer:set', 'pos:customer:create', 'pos:customer:view', 'pos:customer:delete'],
    'Commercials': ['pos:commercial:set', 'pos:commercial:create', 'pos:commercial:view'],
    'Tables':      ['pos:tables:set', 'pos:tables:clear'],
    'Products':    ['pos:products:view', 'pos:products:modify'],
    'Devices':     ['pos:devices:use', 'pos:devices:view', 'pos:devices:update', 'pos:devices:delete'],
    'Settings':    ['pos:settings:view', 'pos:settings:update'],
    'Reports':     ['pos:reports:view'],
    'Sync':        ['pos:sync:orders', 'pos:sync:tickets', 'pos:sync:sessions', 'pos:sync:customers', 'pos:sync:all', 'pos:sync:viewPending', 'pos:sync:managePending'],
    'Other':       ['pos:manualDiscount', 'pos:printing'],
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 740),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatar(),
                    const SizedBox(height: 20),
                    _sectionTitle('Basic Information'),
                    const SizedBox(height: 10),
                    Card(
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(children: [
                          _infoRow('User ID', '#${user.id}'),
                          _infoRow('Username', user.username),
                          _infoRow('First Name', user.firstName),
                          _infoRow('Last Name', user.lastName),
                          _infoRow('Type', user.type.toUpperCase()),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('Activity'),
                    const SizedBox(height: 10),
                    Card(
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(children: [
                          _infoRow('Created At', _fmtDt(user.createdAt)),
                          _infoRow('Updated At', _fmtDt(user.updatedAt)),
                          _infoRow('Last Login', user.lastLogin != null ? _fmtDt(user.lastLogin!) : 'Never'),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('Permissions'),
                    const SizedBox(height: 10),
                    _buildPermissionsCard(context),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
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

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _typeColor(user.type),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${user.firstName} ${user.lastName}',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('@${user.username}', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    if (user.imageUrl != null && user.imageUrl!.isNotEmpty) {
      return Center(
        child: CircleAvatar(radius: 48, backgroundImage: NetworkImage(user.imageUrl!)),
      );
    }
    return Center(
      child: CircleAvatar(
        radius: 48,
        backgroundColor: Colors.grey[200],
        child: Icon(Icons.person, size: 52, color: Colors.grey[400]),
      ),
    );
  }

  Widget _buildPermissionsCard(BuildContext context) {
    final permsRaw = user.permissions?.trim() ?? '';

    if (permsRaw.isEmpty) {
      return Card(
        elevation: 1,
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Text('No permissions assigned.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
        ),
      );
    }

    // Wildcard — all permissions
    if (permsRaw.contains('pos:*')) {
      return Card(
        elevation: 1,
        color: Colors.purple[50],
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.all_inclusive, color: Colors.purple[700]),
              const SizedBox(width: 8),
              Text('Full access — all permissions granted',
                  style: TextStyle(color: Colors.purple[700], fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    final granted = permsRaw.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toSet();

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _permissionGroups.entries.map((entry) {
            final groupPerms = entry.value;
            final grantedInGroup = groupPerms.where((p) => granted.contains(p)).toList();
            if (grantedInGroup.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[600],
                          letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: groupPerms.map((perm) {
                      final has = granted.contains(perm);
                      final label = perm.split(':').last;
                      return _permChip(label, has);
                    }).toList(),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _permChip(String label, bool granted) {
    final color = granted ? Colors.green : Colors.grey[300]!;
    final textColor = granted ? Colors.green[800]! : Colors.grey[500]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: granted ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(granted ? Icons.check_circle_outline : Icons.radio_button_unchecked,
              size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type.toLowerCase().replaceAll('pos_', '')) {
      case 'admin': return Colors.red[700]!;
      case 'cashier': return Colors.blue[700]!;
      case 'waiter': return Colors.green[700]!;
      default: return Colors.grey[700]!;
    }
  }

  String _fmtDt(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}  ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}:${d.second.toString().padLeft(2,'0')}';
}
