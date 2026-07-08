import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:caisse212/providers/stat_provider.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/services/permission_service.dart';
import 'package:caisse212/services/activity_log_service.dart';
import '../../providers/admin_elevation_provider.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/session_service.dart';
import '../../services/customer_display_service.dart';
import '../../services/app_exit_service.dart';
import '../../utils/admin_auth.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/responsive_utils.dart';
import '../settings/settings_screen.dart';
import '../profile/profile_dialog.dart';
import '../../providers/held_orders_provider.dart';
import 'admin_mode_chip.dart';
import 'close_session_dialog.dart';
import 'report_issue_dialog.dart';
import 'sync_inspector_dialog.dart';

class TopBar extends ConsumerStatefulWidget {
  const TopBar({Key? key}) : super(key: key);

  @override
  ConsumerState<TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<TopBar> {
  final _logger = Logger.instance;
  bool _isOnline = true;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  StreamSubscription? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (!mounted) return;
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
      ref.read(networkStateProvider.notifier).state = _isOnline;
    });

    // Sync search controller with provider
    _searchController.text = ref.read(productSearchQueryProvider);

    // Always focus search bar on init
    _requestSearchFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-request focus when returning to screen
    _requestSearchFocus();
  }

  void _requestSearchFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchFocusNode.canRequestFocus) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Widget _buildSearchBar() {
    final searchQuery = ref.watch(productSearchQueryProvider);
    final l10n = AppLocalizations.of(context);

    // Sync controller with provider if changed externally
    if (_searchController.text != searchQuery) {
      _searchController.text = searchQuery;
    }

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          // Search icon
          Container(
            width: 45,
            height: 40,
            alignment: Alignment.center,
            child: const Icon(
              Icons.search,
              color: Colors.white,
              size: 20,
            ),
          ),
          // Search text field
          Expanded(
            child: OnscreenKeyboardTextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: l10n?.translate('search_products') ?? 'Search products...',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                isDense: true,
              ),
              onChanged: (value) {
                ref.read(productSearchQueryProvider.notifier).state = value;
              },
              onSubmitted: (_) {
                // Keep focus after submit
                _searchFocusNode.requestFocus();
              },
            ),
          ),
          // Clear button when there's text
          if (searchQuery.isNotEmpty)
            InkWell(
              onTap: () {
                _searchController.clear();
                ref.read(productSearchQueryProvider.notifier).state = '';
                _searchFocusNode.requestFocus();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 30,
                height: 40,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.clear,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBarcodeScanToggle() {
    final scanMode = ref.watch(barcodeScanModeProvider);
    final l10n = AppLocalizations.of(context);

    IconData icon;
    Color? color;
    String tooltip;

    switch (scanMode) {
      case BarcodeScanMode.disabled:
        icon = Icons.qr_code_scanner_outlined;
        color = Colors.white.withOpacity(0.5);
        tooltip = l10n?.translate('barcode_scanning_disabled') ?? 'Barcode scanning disabled';
        break;
      case BarcodeScanMode.orders:
        icon = Icons.qr_code_2;
        color = Colors.blue;
        tooltip = l10n?.translate('scanning_orders') ?? 'Scanning orders';
        break;
      case BarcodeScanMode.products:
        icon = Icons.inventory_2;
        color = Colors.green;
        tooltip = l10n?.translate('scanning_products') ?? 'Scanning products';
        break;
    }

    return PopupMenuButton<BarcodeScanMode>(
      tooltip: tooltip,
      onSelected: (mode) {
        ref.read(barcodeScanModeProvider.notifier).state = mode;
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: BarcodeScanMode.disabled,
          child: Row(
            children: [
              Icon(
                Icons.qr_code_scanner_outlined,
                color: scanMode == BarcodeScanMode.disabled ? Colors.blue : null,
              ),
              const SizedBox(width: 8),
              Text(
                l10n?.translate('scanner_disabled') ?? 'Disabled',
                style: TextStyle(
                  fontWeight: scanMode == BarcodeScanMode.disabled ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: BarcodeScanMode.orders,
          child: Row(
            children: [
              Icon(
                Icons.qr_code_2,
                color: scanMode == BarcodeScanMode.orders ? Colors.blue : null,
              ),
              const SizedBox(width: 8),
              Text(
                l10n?.translate('scan_orders') ?? 'Scan Orders',
                style: TextStyle(
                  fontWeight: scanMode == BarcodeScanMode.orders ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: BarcodeScanMode.products,
          child: Row(
            children: [
              Icon(
                Icons.inventory_2,
                color: scanMode == BarcodeScanMode.products ? Colors.blue : null,
              ),
              const SizedBox(width: 8),
              Text(
                l10n?.translate('scan_products') ?? 'Scan Products',
                style: TextStyle(
                  fontWeight: scanMode == BarcodeScanMode.products ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? Colors.white, size: 20),
            const SizedBox(width: 6),
            Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    if (!mounted) return;
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
    final l10n = AppLocalizations.of(context);
    final currencyFormatter = ref.read(currencyFormatterProvider);
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n?.translate('no_user_logged_in') ?? 'No user logged in')),
      );
      return;
    }

    final database = ref.read(databaseProvider);
    final sessionService = SessionService(database);
    final session = await sessionService.getActiveSession(currentUser.id);

    if (session == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n?.translate('no_active_session') ?? 'No active session')),
        );
      }
      return;
    }

    final summary = await sessionService.getSessionSummary(session.id);

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${l10n?.translate('current_session') ?? 'Current Session'} #${session.code}'),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSessionInfoRow(l10n?.translate('status') ?? 'Status', session.status.toUpperCase(), _getStatusColor(session.status)),
                _buildSessionInfoRow(l10n?.translate('started_at') ?? 'Started', _formatDateTime(session.startedAt)),
                _buildSessionInfoRow(l10n?.translate('starting_balance') ?? 'Starting Balance', currencyFormatter.format(session.moneyAtStart)),
                const Divider(height: 20),
                _buildSessionInfoRow(l10n?.translate('tickets') ?? 'Tickets', '${summary.ticketCount}'),
                _buildSessionInfoRow(l10n?.translate('cash_sales') ?? 'Cash Sales', currencyFormatter.format(summary.totalCash)),
                _buildSessionInfoRow(l10n?.translate('card_sales') ?? 'Card Sales', currencyFormatter.format(summary.totalCard)),
                if (summary.totalMobile > 0)
                  _buildSessionInfoRow(l10n?.translate('mobile_total') ?? 'Mobile Sales', currencyFormatter.format(summary.totalMobile)),
                _buildSessionInfoRow(l10n?.translate('total_paid') ?? 'Total Paid', currencyFormatter.format(summary.totalPaid), Colors.blue),
                const Divider(height: 20),
                _buildSessionInfoRow(l10n?.translate('expected_cash') ?? 'Expected Cash', currencyFormatter.format(summary.expectedCashAtEnd), Colors.green),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n?.translate('close') ?? 'Close'),
            ),
            if (session.status == 'active' || session.status == 'paused')
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _endCurrentSession(session.id);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text(l10n?.translate('end_session') ?? 'End Session',style: TextStyle(color: Colors.white),),
              ),
          ],
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    final l10n = AppLocalizations.of(context);
    try {
      // Warn if there are unsaved held orders in RAM
      final heldOrders = ref.read(heldOrdersProvider);
      if (heldOrders.isNotEmpty && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange),
                const SizedBox(width: 8),
                Text(l10n?.translate('held_orders_warning_title') ??
                    'Unsaved held orders'),
              ],
            ),
            content: Text(
              (l10n?.translate('held_orders_warning_body') ??
                      'You have {0} held order(s) in memory that will be lost if you log out. Continue?')
                  .replaceAll('{0}', heldOrders.length.toString()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n?.translate('cancel') ?? 'Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: Text(l10n?.translate('logout') ?? 'Logout'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }

      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) {
        await _doLogout();
        return;
      }

      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      final session = await sessionService.getActiveSession(currentUser.id);

      if (session == null || session.status != 'active') {
        // No active session, just logout
        await _doLogout();
        return;
      }

      // Show dialog asking user to pause or end session
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(l10n?.translate('logout') ?? 'Logout'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n?.translate('what_to_do_with_session') ?? 'What would you like to do with your current session?'),
              const SizedBox(height: 16),
              Text(l10n?.translate('pause_resume_info') ?? '• Pause: Resume when you login again'),
              Text(l10n?.translate('end_close_info') ?? '• End: Close session and calculate totals'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: Text(l10n?.translate('cancel') ?? 'Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop('pause'),
              icon: const Icon(Icons.pause),
              label: Text(l10n?.translate('pause_session') ?? 'Pause Session'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop('end'),
              icon: const Icon(Icons.stop),
              label: Text(l10n?.translate('end_session') ?? 'End Session'),
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
            SnackBar(
              content: Text(l10n?.translate('session_paused_resume_login') ?? 'Session paused. Resume when you login again.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        await Future.delayed(const Duration(milliseconds: 500));
        await _doLogout();
      } else if (choice == 'end') {
        // End session via cash-count + Z-report dialog.
        final result = await showCloseSessionDialog(
          context: context,
          ref: ref,
          sessionId: session.id,
        );
        if (!result.closed) return; // user backed out — keep them logged in
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n?.translate('session_ended_successfully') ?? 'Session ended successfully.'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await Future.delayed(const Duration(milliseconds: 500));
        await _doLogout();
      }
    } catch (e) {
      _logger.error('Logout error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.translate('error') ?? 'Error'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      await _doLogout();
    }
  }

  /// Closes any still-open session for [userId] then pushes all local data
  /// to the server before the user leaves. Errors are swallowed — logout
  /// must never be blocked by a failed sync.
  Future<void> _syncAndCloseBeforeLogout(int? userId) async {
    try {
      final database = ref.read(databaseProvider);
      final syncService = ref.read(dataSyncServiceProvider);
      if (userId != null) {
        final session =
            await SessionService(database).getActiveSession(userId);
        if (session != null) {
          await SessionService(database).endSession(sessionId: session.id);
        }
      }
      await Future.wait([
        syncService.syncPendingOperations(),
        syncService.syncSessionsBulk(),
        syncService.syncOrdersBulk(),
        syncService.syncTicketsBulk(),
      ]).timeout(const Duration(seconds: 15));
    } catch (e) {
      _logger.warning('Pre-logout sync failed (non-blocking): $e');
    }
  }

  Future<void> _doLogout() async {
    // Record the logout before clearing the user.
    final user = ref.read(currentUserProvider);
    if (user != null) {
      ref.read(activityLogServiceProvider).logLogout(
            userId: user.id,
            username: user.effectiveDisplayName,
          );
    }
    // Show a non-dismissible progress dialog while we sync.
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(AppLocalizations.of(context)?.translate('syncing_data') ??
                  'Syncing data...'),
            ],
          ),
        ),
      );
    }
    await _syncAndCloseBeforeLogout(user?.id);
    // Clear user and session state
    ref.read(currentUserProvider.notifier).state = null;
    ref.read(currentSessionProvider.notifier).state = null;
    // Drop any admin-mode elevation so it doesn't survive a user swap.
    ref.read(adminElevationProvider.notifier).state = null;
    // Clear current order state
    ref.read(orderProvider.notifier).clearOrder();
    if (mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
      // pushNamedAndRemoveUntil clears the dialog and all other routes.
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  /// Full logout - clears tenant data and goes back to server login
  Future<void> _handleFullLogout() async {
    final localizations = AppLocalizations.of(context);
    final prefs = ref.read(sharedPreferencesProvider);

    // Require an admin's credentials before wiping local + tenant data.
    final admin = await showAdminCredentialDialog(
      context,
      ref,
      title: localizations?.translate('full_logout') ?? 'Full Logout',
      description: localizations?.translate('full_logout_warning') ??
          'This will clear ALL data and disconnect from the server.',
      confirmLabel: localizations?.translate('verify_logout') ?? 'Verify & Logout',
      confirmColor: Colors.red,
    );
    if (admin == null) return;

    // After password verification (or if no password set), show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations?.translate('full_logout') ?? 'Full Logout'),
        content: Text(
          localizations?.translate('full_logout_confirm') ??
          'This will clear all server authentication data and local database.\n\n'
          'You will need to reconnect to the server or use demo mode again.\n\n'
          'Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localizations?.translate('cancel') ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(localizations?.translate('full_logout') ?? 'Full Logout'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Clear current user and session
      ref.read(currentUserProvider.notifier).state = null;
      ref.read(currentSessionProvider.notifier).state = null;
      // Drop any admin-mode elevation so it doesn't survive a user swap.
      ref.read(adminElevationProvider.notifier).state = null;
      // Clear current order state
      ref.read(orderProvider.notifier).clearOrder();

      // Get API service and call logout endpoint
      final apiService = ApiService(prefs);
      
      // Call logout API (this won't throw error, just logs if it fails)
      await apiService.logout();

      // Clear API service data INCLUDING tenant password hash
      await apiService.clearAllAuthData(); // Use clearAllAuthData for full logout

      // Dump/backup the database before clearing
      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);
      await syncService.dumpDatabaseBeforeClear();

      // Clear the database
      await syncService.clearAllData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logged out completely. All data cleared.'),
            backgroundColor: Colors.orange,
          ),
        );
        // Navigate to tenant login screen – unfocus first to prevent
        // AnimatedDefaultTextStyle dirty-widget-in-wrong-scope errors.
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/tenant_login', (route) => false);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during logout: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Build customer display toggle button
  Widget _buildCustomerDisplayButton(AppLocalizations? l10n, {bool iconOnly = false}) {
    final displayService = ref.read(customerDisplayServiceProvider);
    final isOpen = ref.watch(customerDisplayOpenProvider);

    return Tooltip(
      message: l10n?.translate('customer_display') ?? 'Customer Display',
      child: InkWell(
        onTap: () async {
          if (isOpen) {
            await displayService.close();
            ref.read(customerDisplayOpenProvider.notifier).state = false;
          } else {
            await displayService.open();
            ref.read(customerDisplayOpenProvider.notifier).state = true;
            // Send business name
            final prefs = ref.read(sharedPreferencesProvider);
            final businessName = prefs.getString('business_name');
            if (businessName != null && businessName.isNotEmpty) {
              await displayService.sendBusinessName(businessName);
            }
            // Send current order if any
            final currentOrder = ref.read(orderProvider);
            if (currentOrder.items.isNotEmpty) {
              await displayService.sendOrderUpdate(currentOrder);
            }
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isOpen ? Colors.green.withOpacity(0.2) : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isOpen ? Colors.green : Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOpen ? Icons.connected_tv : Icons.tv_off,
                color: isOpen ? Colors.green : Colors.white70,
                size: 18,
              ),
              if (!iconOnly) ...[
                const SizedBox(width: 6),
                Text(
                  isOpen
                      ? (l10n?.translate('display_on') ?? 'Display On')
                      : (l10n?.translate('display_off') ?? 'Display Off'),
                  style: TextStyle(
                    color: isOpen ? Colors.green : Colors.white70,
                    fontSize: 12,
                    fontWeight: isOpen ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Sync data from server
  Future<void> _handleSync() async {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.read(sharedPreferencesProvider);
    final apiService = ref.read(apiServiceProvider);
    final settings = ref.read(settingsProvider);

    // Check if in demo mode
    if (apiService.isDemoMode()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n?.translate('demo_mode_sync_unavailable') ?? 'Demo mode: Sync not available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(l10n?.translate('syncing_data') ?? 'Syncing data...'),
          ],
        ),
      ),
    );

    try {
      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);

      // First upload local data
      await syncService.uploadLocalData();

      // Pull server-side deltas (admin edits, tombstones) before full refresh
      await syncService.pullAllDeltas(prefs);

      // Then download fresh data with data retention
      await syncService.syncAllData(dataRetentionDays: settings.dataRetentionDays);

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.translate('data_synced_successfully') ?? 'Data synced successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.translate('sync_failed') ?? 'Sync failed'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pauseCurrentSession(int sessionId) async {
    final l10n = AppLocalizations.of(context);
    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      await sessionService.pauseSession(sessionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.translate('session_paused') ?? 'Session paused'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n?.translate('failed_to_pause_session') ?? 'Failed to pause session'}: $e')),
        );
      }
    }
  }

  Future<void> _resumeCurrentSession(int sessionId) async {
    final l10n = AppLocalizations.of(context);
    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      await sessionService.resumeSession(sessionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.translate('session_resumed') ?? 'Session resumed'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n?.translate('failed_to_resume_session') ?? 'Failed to resume session'}: $e')),
        );
      }
    }
  }

  Future<void> _endCurrentSession(int sessionId) async {
    final l10n = AppLocalizations.of(context);
    // Cash-count + Z-report dialog. endSession runs inside the dialog flow
    // so we don't double-call it here.
    final result = await showCloseSessionDialog(
      context: context,
      ref: ref,
      sessionId: sessionId,
    );
    if (!result.closed) return;

    try {
      // Clear current user and session
      ref.read(currentUserProvider.notifier).state = null;
      ref.read(currentSessionProvider.notifier).state = null;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.translate('session_ended_logging_out') ?? 'Session ended successfully. Logging out...'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate to login screen – unfocus first to prevent
        // AnimatedDefaultTextStyle dirty-widget-in-wrong-scope errors.
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/login', (route) => false);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.translate('failed_to_end_session') ?? 'Failed to end session'}: $e'),
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
    final l10n = AppLocalizations.of(context);
    final currentUser = ref.watch(currentUserProvider);
    final time = ref.watch(timeProvider).value ?? DateTime.now();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < kBreakpointCompact;
    final isVeryCompact = screenWidth < 700;

    final hPad = isVeryCompact ? 8.0 : 16.0;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Primary bar ────────────────────────────────────────────
          SizedBox(
            height: 56,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: Row(
                children: [
                  const Icon(Icons.point_of_sale, color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                  const SizedBox(width: 8),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 360,
                        minWidth: isVeryCompact ? 80 : 150,
                      ),
                      child: _buildSearchBar(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Barcode + nav buttons only on non-compact (go to secondary row on compact)
                  if (!isCompact) ...[
                    _buildBarcodeScanToggle(),
                    const SizedBox(width: 4),
                    if (ref.read(permissionServiceProvider).hasPermission(Permissions.agendaView))
                      Tooltip(
                        message: 'Agenda',
                        child: IconButton(
                          icon: const Icon(Icons.calendar_month_outlined, color: Colors.white),
                          onPressed: () => Navigator.pushNamed(context, '/agenda'),
                        ),
                      ),
                    if (ref.read(permissionServiceProvider).hasPermission(Permissions.reportsView))
                      Tooltip(
                        message: 'Dashboard',
                        child: IconButton(
                          icon: const Icon(Icons.dashboard_outlined, color: Colors.white),
                          onPressed: () => Navigator.pushNamed(context, '/dashboard'),
                        ),
                      ),
                    if (ref.read(permissionServiceProvider).hasPermission(Permissions.notesView))
                      Tooltip(
                        message: l10n?.translate('notes') ?? 'Notes',
                        child: IconButton(
                          icon: const Icon(Icons.sticky_note_2_outlined, color: Colors.white),
                          onPressed: () => Navigator.pushNamed(context, '/notes'),
                        ),
                      ),
                  ],
                  const Spacer(),
                  // Session, network, sync, customer display on non-compact only
                  if (!isCompact) ...[
                    IconButton(
                      icon: const Icon(Icons.point_of_sale_outlined, color: Colors.white, size: 20),
                      tooltip: l10n?.translate('session') ?? 'session',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: _showCurrentSessionDetails,
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onLongPress: () => showDialog(
                        context: context,
                        builder: (_) => const SyncInspectorDialog(),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _isOnline ? _handleSync : null,
                        icon: const Icon(Icons.sync, size: 18),
                        label: Text(l10n?.translate('update') ?? 'Update'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Theme.of(context).primaryColor,
                          disabledBackgroundColor: Colors.grey[300],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (ref.watch(settingsProvider).enableCustomerDisplay) ...[
                      _buildCustomerDisplayButton(l10n, iconOnly: false),
                      const SizedBox(width: 8),
                    ],
                  ],
                  // Admin-mode elevation chip (auto-hides for admins).
                  const AdminModeChip(),
                  // User profile — avatar-only on very compact
                  PopupMenuButton<String>(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: isVeryCompact ? 16 : 18,
                          backgroundColor: Colors.white,
                          child: Text(
                            currentUser?.effectiveDisplayName.substring(0, 1).toUpperCase() ?? 'U',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: isVeryCompact ? 13 : 14,
                            ),
                          ),
                        ),
                        if (!isVeryCompact) ...[
                          const SizedBox(width: 6),
                          Text(
                            currentUser?.effectiveDisplayName ?? (l10n?.translate('user') ?? 'User'),
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          const Icon(Icons.arrow_drop_down, color: Colors.white),
                        ],
                      ],
                    ),
            onSelected: (value) async {
              if (value == 'profile') {
                showDialog(
                  context: context,
                  builder: (context) => const ProfileDialog(),
                );
              } else if (value == 'settings') {
                // Navigate to settings
              } else if (value == 'report_issue') {
                showDialog(
                  context: context,
                  builder: (context) => const ReportIssueDialog(),
                );
              } else if (value == 'logout') {
                await _handleLogout();
              } else if (value == 'full_logout') {
                await _handleFullLogout();
              } else if (value == 'exit_app') {
                await requestAppExit(context, ref);
              }
            },
            itemBuilder: (context) {
              final l10n = AppLocalizations.of(context);
              final permissionService = ref.read(permissionServiceProvider);
              final items = <PopupMenuEntry<String>>[];

              // Profile - always visible
              items.add(PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    const Icon(Icons.person),
                    const SizedBox(width: 8),
                    Text(l10n?.translate('profile') ?? 'Profile'),
                  ],
                ),
              ));

              // Settings - permission protected
              if (permissionService.hasPermission(Permissions.settingsView)) {
                items.add(PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      const Icon(Icons.settings),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('settings') ?? 'Settings'),
                    ],
                  ),
                  onTap: () {
                    Future.delayed(Duration.zero, () {
                      showDialog(
                        context: context,
                        builder: (context) => const SettingsScreen(),
                      );
                    });
                  },
                ));
              }

              // Sessions - permission protected
              if (permissionService.hasPermission(Permissions.sessionsView)) {
                items.add(PopupMenuItem(
                  value: 'sessions',
                  child: Row(
                    children: [
                      const Icon(Icons.access_time),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('sessions') ?? 'Sessions'),
                    ],
                  ),
                  onTap: () {
                    Navigator.pushNamed(context, '/sessions');
                  },
                ));
              }

              // Orders - permission protected
              if (permissionService.hasPermission(Permissions.ordersView)) {
                items.add(PopupMenuItem(
                  value: 'orders',
                  child: Row(
                    children: [
                      const Icon(Icons.list),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('orders') ?? 'Orders'),
                    ],
                  ),
                  onTap: () {
                    Navigator.pushNamed(context, '/orders');
                  },
                ));
              }

              // Tickets - permission protected
              if (permissionService.hasPermission(Permissions.ticketsView)) {
                items.add(PopupMenuItem(
                  value: 'tickets',
                  child: Row(
                    children: [
                      const Icon(Icons.receipt),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('tickets') ?? 'Tickets'),
                    ],
                  ),
                  onTap: () {
                    Navigator.pushNamed(context, '/tickets');
                  },
                ));
              }

              // Devices - permission protected
              if (permissionService.hasPermission(Permissions.devicesView)) {
                items.add(PopupMenuItem(
                  value: 'devices',
                  child: Row(
                    children: [
                      const Icon(Icons.devices),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('devices') ?? 'Devices'),
                    ],
                  ),
                  onTap: () {
                    Navigator.pushNamed(context, '/devices');
                  },
                ));
              }

              // Agenda (planning view) - permission protected
              if (permissionService.hasPermission(Permissions.agendaView)) {
                items.add(PopupMenuItem(
                  value: 'agenda',
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('agenda') ?? 'Agenda'),
                    ],
                  ),
                  onTap: () {
                    Navigator.pushNamed(context, '/agenda');
                  },
                ));
              }

              // Printers - permission protected
              if (permissionService.hasPermission(Permissions.devicesView)) {
                items.add(PopupMenuItem(
                  value: 'printers',
                  child: Row(
                    children: [
                      const Icon(Icons.print),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('printers') ?? 'Printers'),
                    ],
                  ),
                  onTap: () {
                    Navigator.pushNamed(context, '/printers');
                  },
                ));
              }

              // Activity logs - permission protected
              if (permissionService.hasPermission(Permissions.logsView)) {
                items.add(PopupMenuItem(
                  value: 'logs',
                  child: Row(
                    children: [
                      const Icon(Icons.history),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('activity_logs') ?? 'Activity Logs'),
                    ],
                  ),
                  onTap: () {
                    Navigator.pushNamed(context, '/logs');
                  },
                ));
              }

              // Users - permission protected (admin only typically)
              if (permissionService.hasPermission('pos:users:view')) {
                items.add(PopupMenuItem(
                  value: 'users',
                  child: Row(
                    children: [
                      const Icon(Icons.people),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('users') ?? 'Users'),
                    ],
                  ),
                  onTap: () {
                    Navigator.pushNamed(context, '/users');
                  },
                ));
              }

              // Report Issue - always visible
              items.add(PopupMenuItem(
                value: 'report_issue',
                child: Row(
                  children: [
                    Icon(Icons.bug_report, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Text(
                      l10n?.translate('report_issue') ?? 'Report Issue',
                      style: TextStyle(color: Colors.blue[700]),
                    ),
                  ],
                ),
              ));

              // Divider before logout
              items.add(const PopupMenuDivider());

              // Logout - always visible
              items.add(PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(l10n?.translate('logout') ?? 'Logout', style: const TextStyle(color: Colors.orange)),
                  ],
                ),
              ));

              // Full logout - permission protected (admin only)
              if (permissionService.hasPermission(Permissions.all)) {
                items.add(PopupMenuItem(
                  value: 'full_logout',
                  child: Row(
                    children: [
                      const Icon(Icons.logout, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n?.translate('full_logout_clear_all') ?? 'Full Logout (Clear All)',
                          style: const TextStyle(color: Colors.red),
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                );
              }

              // Exit app — confirm, offer to close the session, sync, then quit.
              items.add(const PopupMenuDivider());
              items.add(PopupMenuItem(
                value: 'exit_app',
                child: Row(
                  children: [
                    const Icon(Icons.power_settings_new, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Text(exitMenuLabel(context),
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ));

              return items;
            },
          ),
                ],         // primary Row children
              ),           // primary Row
            ),             // Padding
          ),               // SizedBox(56) — primary bar done
          // ── Secondary bar (compact only) ─────────────────────────
          if (isCompact)
            Container(
              height: 40,
              color: Theme.of(context).primaryColorDark,
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: Row(
                children: [
                  if (!isVeryCompact) ...[
                    Text(
                      _formatTime(time),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildBarcodeScanToggle(),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    icon: const Icon(Icons.point_of_sale_outlined, color: Colors.white, size: 18),
                    tooltip: l10n?.translate('session') ?? 'session',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: _showCurrentSessionDetails,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isOnline
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      _isOnline ? Icons.wifi : Icons.wifi_off,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onLongPress: () => showDialog(
                      context: context,
                      builder: (_) => const SyncInspectorDialog(),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.sync, color: Colors.white, size: 18),
                      tooltip: l10n?.translate('update') ?? 'Update',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: _isOnline ? _handleSync : null,
                    ),
                  ),
                  if (ref.watch(settingsProvider).enableCustomerDisplay) ...[
                    const SizedBox(width: 4),
                    _buildCustomerDisplayButton(l10n, iconOnly: true),
                  ],
                ],
              ),
            ),
        ],            // Column children
      ),              // Column
    );                // Container
  }
}

