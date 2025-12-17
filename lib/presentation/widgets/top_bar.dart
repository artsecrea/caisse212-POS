import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:posecrea/providers/stat_provider.dart';
import '../../providers/database_providers.dart';
import '../../services/session_service.dart';

class TopBar extends ConsumerStatefulWidget {
  const TopBar({Key? key}) : super(key: key);

  @override
  ConsumerState<TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<TopBar> {
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    Connectivity().onConnectivityChanged.listen((result) {
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
      ref.read(networkStateProvider.notifier).state = _isOnline;
    });
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() {
      _isOnline = result != ConnectivityResult.none;
    });
    ref.read(networkStateProvider.notifier).state = _isOnline;
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _showCurrentSessionDetails() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user logged in')),
      );
      return;
    }

    final database = ref.read(databaseProvider);
    final sessionService = SessionService(database);
    final session = await sessionService.getActiveSession(currentUser.id);

    if (session == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active session')),
        );
      }
      return;
    }

    final summary = await sessionService.getSessionSummary(session.id);

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Current Session #${session.id}'),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSessionInfoRow('Status', session.status.toUpperCase(), _getStatusColor(session.status)),
                _buildSessionInfoRow('Started', _formatDateTime(session.startedAt)),
                _buildSessionInfoRow('Starting Balance', '\$${session.moneyAtStart.toStringAsFixed(2)}'),
                const Divider(height: 20),
                _buildSessionInfoRow('Tickets', '${summary.ticketCount}'),
                _buildSessionInfoRow('Cash Sales', '\$${summary.totalCash.toStringAsFixed(2)}'),
                _buildSessionInfoRow('Card Sales', '\$${summary.totalCard.toStringAsFixed(2)}'),
                _buildSessionInfoRow('Total Sales', '\$${summary.totalAmount.toStringAsFixed(2)}', Colors.blue),
                const Divider(height: 20),
                _buildSessionInfoRow('Expected Cash', '\$${summary.expectedCashAtEnd.toStringAsFixed(2)}', Colors.green),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (session.status == 'active' || session.status == 'paused')
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _endCurrentSession(session.id);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('End Session'),
              ),
          ],
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    try {
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) {
        _doLogout();
        return;
      }

      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      final session = await sessionService.getActiveSession(currentUser.id);

      if (session == null || session.status != 'active') {
        // No active session, just logout
        _doLogout();
        return;
      }

      // Show dialog asking user to pause or end session
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Logout'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('What would you like to do with your current session?'),
              const SizedBox(height: 16),
              const Text('• Pause: Resume when you login again'),
              const Text('• End: Close session and calculate totals'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop('pause'),
              icon: const Icon(Icons.pause),
              label: const Text('Pause Session'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop('end'),
              icon: const Icon(Icons.stop),
              label: const Text('End Session'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (choice == 'cancel' || choice == null) {
        return;
      }

      if (choice == 'pause') {
        // Pause session
        await sessionService.pauseSession(session.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session paused. Resume when you login again.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        await Future.delayed(const Duration(milliseconds: 500));
        _doLogout();
      } else if (choice == 'end') {
        // End session
        await sessionService.endSession(sessionId: session.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session ended successfully.'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await Future.delayed(const Duration(milliseconds: 500));
        _doLogout();
      }
    } catch (e) {
      print('Logout error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      _doLogout();
    }
  }

  void _doLogout() {
    ref.read(currentUserProvider.notifier).state = null;
    ref.read(currentSessionProvider.notifier).state = null;
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  Future<void> _pauseCurrentSession(int sessionId) async {
    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      await sessionService.pauseSession(sessionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session paused'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pause session: $e')),
        );
      }
    }
  }

  Future<void> _resumeCurrentSession(int sessionId) async {
    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      await sessionService.resumeSession(sessionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session resumed'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resume session: $e')),
        );
      }
    }
  }

  Future<void> _endCurrentSession(int sessionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Session'),
        content: const Text(
          'Are you sure you want to end this session?\n\nYou will be logged out automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End Session'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      await sessionService.endSession(sessionId: sessionId);

      // Clear current user and session
      ref.read(currentUserProvider.notifier).state = null;
      ref.read(currentSessionProvider.notifier).state = null;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session ended successfully. Logging out...'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate to login screen
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to end session: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildSessionInfoRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'paused':
        return Colors.orange;
      case 'ended':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final time = ref.watch(timeProvider).value ?? DateTime.now();

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // App title
          const Icon(Icons.point_of_sale, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          const Text(
            'POS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          // show the time
          const SizedBox(width: 20),
          Text(
            _formatTime(time),
            style: const TextStyle(color: Colors.white, fontSize: 20),
          ),
          const Spacer(),
          // Session icon - shows current session details
          IconButton(
            icon: const Icon(Icons.point_of_sale_outlined, color: Colors.white),
            tooltip: 'Current Session',
            onPressed: _showCurrentSessionDetails,
          ),
          const SizedBox(width: 8),
          // Status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.access_time,
                  color: Colors.white,
                  size: 16,
                ),
                SizedBox(width: 6),
                Text(
                  'Active',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Network state
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isOnline
                  ? Colors.green.withOpacity(0.3)
                  : Colors.red.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isOnline ? Icons.wifi : Icons.wifi_off,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _isOnline ? 'Online' : 'Offline',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Update button
          ElevatedButton.icon(
            onPressed: _isOnline
                ? () {
                    // TODO: Implement sync functionality
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Syncing data...')),
                    );
                  }
                : null,
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Update'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Theme.of(context).primaryColor,
              disabledBackgroundColor: Colors.grey[300],
            ),
          ),
          const SizedBox(width: 16),
          // User profile
          PopupMenuButton<String>(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Text(
                    currentUser?.firstName.substring(0, 1).toUpperCase() ?? 'U',
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  currentUser?.firstName ?? 'User',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.white),
              ],
            ),
            onSelected: (value) async {
              if (value == 'profile') {
                // Navigate to profile
              } else if (value == 'settings') {
                // Navigate to settings
              } else if (value == 'logout') {
                await _handleLogout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person),
                    SizedBox(width: 8),
                    Text('Profile'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings),
                    SizedBox(width: 8),
                    Text('Settings'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sessions',
                child: const Row(
                  children: [
                    Icon(Icons.access_time),
                    SizedBox(width: 8),
                    Text('Sessions'),
                  ],
                ),
                onTap: (){
                  Navigator.pushNamed(context, '/sessions');
                },
              ),
              PopupMenuItem(
                value: 'orders',
                child: const Row(
                  children: [
                    Icon(Icons.list),
                    SizedBox(width: 8),
                    Text('Orders'),
                  ],
                ),
                onTap: (){
                  Navigator.pushNamed(context, '/orders');
                },
              ),
              PopupMenuItem(
                value: 'tickets',
                child: const Row(
                  children: [
                    Icon(Icons.receipt),
                    SizedBox(width: 8),
                    Text('Tickets'),
                  ],
                ),
                onTap: (){
                  Navigator.pushNamed(context, '/tickets');
                },
              ),
              PopupMenuItem(
                value: 'devices',
                child: const Row(
                  children: [
                    Icon(Icons.devices),
                    SizedBox(width: 8),
                    Text('Devices'),
                  ],
                ),
                onTap: (){
                  Navigator.pushNamed(context, '/devices');
                },
              ),
              PopupMenuItem(
                value: 'users',
                child: const Row(
                  children: [
                    Icon(Icons.people),
                    SizedBox(width: 8),
                    Text('Users'),
                  ],
                ),
                onTap: (){
                  Navigator.pushNamed(context, '/users');
                },
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: const Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Logout', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

