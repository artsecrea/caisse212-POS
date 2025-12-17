import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';

class CommercialSelectionDialog extends ConsumerStatefulWidget {
  const CommercialSelectionDialog({Key? key}) : super(key: key);

  @override
  ConsumerState<CommercialSelectionDialog> createState() => _CommercialSelectionDialogState();
}

class _CommercialSelectionDialogState extends ConsumerState<CommercialSelectionDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commercialsAsync = ref.watch(commercialsProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Select Commercial',
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
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by CIN or name',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: commercialsAsync.when(
                data: (commercials) {
                  var filteredCommercials = commercials;

                  if (_searchQuery.isNotEmpty) {
                    filteredCommercials = commercials.where((c) {
                      final name = '${c.firstName} ${c.lastName}'.toLowerCase();
                      final cin = c.cin.toLowerCase();
                      return name.contains(_searchQuery) || cin.contains(_searchQuery);
                    }).toList();
                  }

                  if (filteredCommercials.isEmpty) {
                    return const Center(child: Text('No commercials found'));
                  }

                  return ListView.builder(
                    itemCount: filteredCommercials.length,
                    itemBuilder: (context, index) {
                      final commercial = filteredCommercials[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
                            child: Icon(
                              Icons.badge,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                          title: Text(
                            '${commercial.firstName} ${commercial.lastName}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('CIN: ${commercial.cin}'),
                          onTap: () {
                            Navigator.of(context).pop({
                              'id': commercial.id,
                              'name': '${commercial.firstName} ${commercial.lastName}',
                            });
                          },
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(child: Text('Error: $error')),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop({'id': null, 'name': null});
              },
              icon: const Icon(Icons.clear),
              label: const Text('Unselect Commercial'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

