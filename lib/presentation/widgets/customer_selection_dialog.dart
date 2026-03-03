import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../data/database/app_database.dart';
import '../../utils/button_styles.dart';
import '../../utils/app_localizations.dart';
import 'package:drift/drift.dart' show Value;

class CustomerSelectionDialog extends ConsumerStatefulWidget {
  const CustomerSelectionDialog({Key? key}) : super(key: key);

  @override
  ConsumerState<CustomerSelectionDialog> createState() => _CustomerSelectionDialogState();
}

class _CustomerSelectionDialogState extends ConsumerState<CustomerSelectionDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  l10n.translate('select_customer'),
                  style: const TextStyle(
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
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.translate('search_by_name_phone_email'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                isDense: true,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase().trim();
                  _hasSearched = _searchQuery.length >= 2;
                });
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _buildCustomerList(database, l10n),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop({'id': null, 'name': null});
                    },
                    icon: const Icon(Icons.clear),
                    label: Text(l10n.translate('unselect_customer')),
                    style: AppButtonStyles.outlinedButtonStyle(
                      foregroundColor: Colors.red,
                      borderColor: Colors.red,
                      isLarge: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _showAddCustomerDialog(context, l10n);
                    },
                    icon: const Icon(Icons.add),
                    label: Text(l10n.translate('add_new_customer')),
                    style: AppButtonStyles.elevatedButtonStyle(isLarge: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerList(AppDatabase database, AppLocalizations l10n) {
    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              l10n.translate('start_typing_to_search'),
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('search_by_name_phone_email'),
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<List<Customer>>(
      stream: _searchCustomers(database),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final customers = snapshot.data!;

        if (customers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  l10n.translate('no_customers_found'),
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.translate('try_different_search_or_add'),
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: customers.length,
          itemBuilder: (context, index) {
            final customer = customers[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(customer.firstName.substring(0, 1).toUpperCase()),
                ),
                title: Text(
                  '${customer.firstName} ${customer.lastName}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (customer.phone != null) Text('${l10n.translate('phone')}: ${customer.phone}'),
                    if (customer.email != null) Text('${l10n.translate('email')}: ${customer.email}'),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).pop({
                    'id': customer.id,
                    'name': '${customer.firstName} ${customer.lastName}',
                  });
                },
              ),
            );
          },
        );
      },
    );
  }

  Stream<List<Customer>> _searchCustomers(AppDatabase database) {
    final query = database.select(database.customers);

    if (_searchQuery.isEmpty) {
      return Stream.value([]);
    }

    // Search in firstName, lastName, phone, or email
    return query
        .watch()
        .map((customers) => customers.where((c) {
              final name = '${c.firstName} ${c.lastName}'.toLowerCase();
              final phone = c.phone?.toLowerCase() ?? '';
              final email = c.email?.toLowerCase() ?? '';
              return name.contains(_searchQuery) ||
                  phone.contains(_searchQuery) ||
                  email.contains(_searchQuery);
            }).toList());
  }

  Future<void> _showAddCustomerDialog(BuildContext context, AppLocalizations l10n) async {
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('add_new_customer')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstNameController,
                decoration: InputDecoration(labelText: '${l10n.translate('first_name')} *'),
              ),
              TextField(
                controller: lastNameController,
                decoration: InputDecoration(labelText: '${l10n.translate('last_name')} *'),
              ),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(labelText: l10n.translate('phone')),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: emailController,
                decoration: InputDecoration(labelText: l10n.translate('email')),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: AppButtonStyles.textButtonStyle(isLarge: true),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              if (firstNameController.text.isEmpty || lastNameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.translate('please_fill_required_fields'))),
                );
                return;
              }

              final database = ref.read(databaseProvider);
              await database.into(database.customers).insert(
                    CustomersCompanion.insert(
                      firstName: firstNameController.text,
                      lastName: lastNameController.text,
                      phone: Value(phoneController.text.isEmpty ? null : phoneController.text),
                      email: Value(emailController.text.isEmpty ? null : emailController.text),
                      isSynced: const Value(false), // New local customer, needs to be synced
                  ));

              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.translate('customer_added_successfully'))),
                );
              }
            },
            style: AppButtonStyles.elevatedButtonStyle(isLarge: true),
            child: Text(l10n.translate('add')),
          ),
        ],
      ),
    );
  }
}

