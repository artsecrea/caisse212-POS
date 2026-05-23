import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart' show OnscreenKeyboardTextField;
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
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
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
            OnscreenKeyboardTextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
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
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => _AddCustomerDialog(database: ref.read(databaseProvider)),
    );
    // If the user saved a new customer, immediately select it.
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }
}

// Enhanced Add Customer Dialog with better validation and UX
class _AddCustomerDialog extends StatefulWidget {
  final AppDatabase database;

  const _AddCustomerDialog({required this.database});

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _firstNameFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  bool _isLoading = false;
  bool _autoValidate = false;
  String? _firstNameError;
  String? _lastNameError;
  String? _phoneError;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    // Auto-focus on first field when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstNameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  String? _validateFirstName(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) {
      return l10n.translate('first_name_required');
    }
    if (value.trim().length < 2) {
      return l10n.translate('name_too_short');
    }
    return null;
  }

  String? _validateLastName(String? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) {
      return l10n.translate('last_name_required');
    }
    if (value.trim().length < 2) {
      return l10n.translate('name_too_short');
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return null; // Email is optional

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      final l10n = AppLocalizations.of(context)!;
      return l10n.translate('invalid_email_format');
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) return null; // Phone is optional

    // Remove spaces and dashes for validation
    final cleanPhone = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleanPhone.length < 8) {
      final l10n = AppLocalizations.of(context)!;
      return l10n.translate('phone_too_short');
    }
    return null;
  }

  bool _validateForm() {
    setState(() {
      _firstNameError = _validateFirstName(_firstNameController.text);
      _lastNameError = _validateLastName(_lastNameController.text);
      _phoneError = _validatePhone(_phoneController.text);
      _emailError = _validateEmail(_emailController.text);
    });

    return _firstNameError == null &&
        _lastNameError == null &&
        _phoneError == null &&
        _emailError == null;
  }

  Future<void> _handleSubmit() async {
    setState(() => _autoValidate = true);

    if (!_validateForm()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final customerId = await widget.database.into(widget.database.customers).insert(
        CustomersCompanion.insert(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          phone: Value(_phoneController.text.trim().isEmpty ? null : _phoneController.text.trim()),
          email: Value(_emailController.text.trim().isEmpty ? null : _emailController.text.trim()),
          isSynced: const Value(false),
        ),
      );

      if (mounted) {
        // Pop with the new customer data so the caller can auto-select it.
        Navigator.of(context).pop({
          'id': customerId,
          'name':
              '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.translate('error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 650),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.person_add,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.translate('add_new_customer'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Form fields
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Personal Information Section
                    Text(
                      l10n.translate('personal_information'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // First Name
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OnscreenKeyboardTextField(
                            controller: _firstNameController,
                            focusNode: _firstNameFocus,
                            enabled: !_isLoading,
                            decoration: InputDecoration(
                              labelText: '${l10n.translate('first_name')} *',
                              hintText: l10n.translate('enter_first_name'),
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              errorText: _autoValidate ? _firstNameError : null,
                            ),
                            textCapitalization: TextCapitalization.words,
                            onChanged: (value) {
                              if (_autoValidate) {
                                setState(() {
                                  _firstNameError = _validateFirstName(value);
                                });
                              }
                            },
                            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Last Name
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OnscreenKeyboardTextField(
                          controller: _lastNameController,
                          focusNode: _lastNameFocus,
                          enabled: !_isLoading,
                          decoration: InputDecoration(
                            labelText: '${l10n.translate('last_name')} *',
                            hintText: l10n.translate('enter_last_name'),
                            prefixIcon: const Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _autoValidate ? _lastNameError : null,
                          ),
                          textCapitalization: TextCapitalization.words,
                          onChanged: (value) {
                            if (_autoValidate) {
                              setState(() {
                                _lastNameError = _validateLastName(value);
                              });
                            }
                          },
                          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Contact Information Section
                    Text(
                      l10n.translate('contact_information'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Phone
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OnscreenKeyboardTextField(
                          controller: _phoneController,
                          focusNode: _phoneFocus,
                          enabled: !_isLoading,
                          decoration: InputDecoration(
                            labelText: l10n.translate('phone'),
                            hintText: l10n.translate('enter_phone_number'),
                            helperText: l10n.translate('optional_field'),
                            prefixIcon: const Icon(Icons.phone_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _autoValidate ? _phoneError : null,
                          ),
                          keyboardType: TextInputType.phone,
                          onChanged: (value) {
                            if (_autoValidate) {
                              setState(() {
                                _phoneError = _validatePhone(value);
                              });
                            }
                          },
                          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Email
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OnscreenKeyboardTextField(
                          controller: _emailController,
                          focusNode: _emailFocus,
                          enabled: !_isLoading,
                          decoration: InputDecoration(
                            labelText: l10n.translate('email'),
                            hintText: l10n.translate('enter_email_address'),
                            helperText: l10n.translate('optional_field'),
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _autoValidate ? _emailError : null,
                          ),
                          keyboardType: TextInputType.emailAddress,
                          onChanged: (value) {
                            if (_autoValidate) {
                              setState(() {
                                _emailError = _validateEmail(value);
                              });
                            }
                          },
                          onSubmitted: (_) => _handleSubmit(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Required fields note
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '* ${l10n.translate('required_fields')}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      label: Text(l10n.translate('cancel')),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _handleSubmit,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.person_add),
                      label: Text(
                        _isLoading ? l10n.translate('adding') : l10n.translate('add_customer'),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }

