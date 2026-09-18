import 'package:caisse212/utils/sample_data_generator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';


/// Debug Screen to Manage Sample Data
/// Use this during development to quickly populate or reset the database
class DebugDataScreen extends ConsumerStatefulWidget {
  const DebugDataScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DebugDataScreen> createState() => _DebugDataScreenState();
}

class _DebugDataScreenState extends ConsumerState<DebugDataScreen> {
  bool _isLoading = false;
  String _message = '';

  Future<void> _generateSampleData() async {
    setState(() {
      _isLoading = true;
      _message = 'Generating sample data...';
    });

    try {
      final database = AppDatabase();
      final generator = SampleDataGenerator(database);
      await generator.generateAll();

      setState(() {
        _message = '✅ Sample data generated successfully!';
      });
    } catch (e) {
      setState(() {
        _message = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _clearAllData() async {
    setState(() {
      _isLoading = true;
      _message = 'Clearing all data...';
    });

    try {
      final database = AppDatabase();

      // Delete all data from tables (in reverse order to respect foreign keys)
      await database.delete(database.zs).go();
      await database.delete(database.cashSessions).go();
      await database.delete(database.transactions).go();
      await database.delete(database.payments).go();
      await database.delete(database.orderProductComponents).go();
      await database.delete(database.orderProducts).go();
      await database.delete(database.orders).go();
      await database.delete(database.customers).go();
      await database.delete(database.commercials).go();
      await database.delete(database.kDSs).go();
      await database.delete(database.kiosks).go();
      await database.delete(database.stations).go();
      await database.delete(database.areaTables).go();
      await database.delete(database.areas).go();
      await database.delete(database.componentGroups).go();
      await database.delete(database.components).go();
      await database.delete(database.products).go();
      await database.delete(database.categories).go();
      await database.delete(database.users).go();

      setState(() {
        _message = '✅ All data cleared!';
      });
    } catch (e) {
      setState(() {
        _message = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showStats() async {
    setState(() {
      _isLoading = true;
      _message = 'Loading statistics...';
    });

    try {
      final database = AppDatabase();

      final usersCount = await database.select(database.users).get().then((list) => list.length);
      final categoriesCount = await database.select(database.categories).get().then((list) => list.length);
      final productsCount = await database.select(database.products).get().then((list) => list.length);
      final tablesCount = await database.select(database.areaTables).get().then((list) => list.length);
      final customersCount = await database.select(database.customers).get().then((list) => list.length);
      final ordersCount = await database.select(database.orders).get().then((list) => list.length);

      setState(() {
        _message = '''
📊 Database Statistics:
━━━━━━━━━━━━━━━━━━━━━━
👥 Users: $usersCount
📂 Categories: $categoriesCount
🍔 Products: $productsCount
🪑 Tables: $tablesCount
👤 Customers: $customersCount
📋 Orders: $ordersCount
━━━━━━━━━━━━━━━━━━━━━━
        ''';
      });
    } catch (e) {
      setState(() {
        _message = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Data Manager'),
        backgroundColor: Colors.deepOrange,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '⚠️ Development Tools',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use these tools to manage sample data during development. Remove this screen before production.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _generateSampleData,
              icon: const Icon(Icons.add_circle),
              label: const Text('Generate Sample Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _showStats,
              icon: const Icon(Icons.analytics),
              label: const Text('Show Database Stats'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Confirm Clear All Data'),
                    content: const Text(
                      'This will delete ALL data from the database. This action cannot be undone. Are you sure?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Delete All'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  _clearAllData();
                }
              },
              icon: const Icon(Icons.delete_forever),
              label: const Text('Clear All Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 32),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_message.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Text(
                  _message,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                ),
              ),

            const Spacer(),

            const Divider(),
            const SizedBox(height: 8),
            Text(
              '💡 Tip: After generating sample data, restart the app to see the changes.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

