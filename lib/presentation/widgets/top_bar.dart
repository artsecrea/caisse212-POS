import 'kitchen_board_dialog.dart' show showKitchenBoardDialog;
import 'dart:async';
import '../../services/pos_notifications.dart' show notifySessionPauseChange;
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:caisse212/providers/stat_provider.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/services/api_service.dart' show ApiService;
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
import 'settings_lock_dialog.dart';
import '../profile/profile_dialog.dart';
import '../../providers/held_orders_provider.dart';
import 'admin_mode_chip.dart';
import 'calculator_dialog.dart';
// DISABLED-FOR-NOW: restore alongside the commented menu items below.
// import 'cash_movement_dialog.dart';
import 'close_session_dialog.dart';
import 'session_reports_dialog.dart';
import 'z_report_dialog.dart';
import '../../utils/snackbar_helper.dart';
import 'settle_unpaid_dialog.dart';
// import 'notify_admin_dialog.dart';
import 'report_issue_dialog.dart';
import 'test_mode_screen.dart';
import 'sync_inspector_dialog.dart';
import 'update_dialog.dart' show showUpdateDialog;
import '../../providers/update_provider.dart';
import '../../services/update_service.dart' show UpdateService;
import '../../services/z_actions.dart' show refreshZConfig;
import './adaptive_text_field.dart';
import '../../core/theme/app_theme.dart';

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
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() {
        _isOnline = _hasNetwork(results);
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

  /// Put the cursor back in the product search.
  ///
  /// Guarded, because this runs from [didChangeDependencies], which fires on
  /// ANY inherited-widget change — including ones caused by a dialog opening
  /// above us or the on-screen keyboard resizing the view. Ungarded, typing in
  /// the Settings dialog yanked the caret to this field and the characters
  /// landed in the product search instead.
  ///
  /// Does nothing at all when `autoFocusProductSearch` is off: taking the
  /// caret is what raises the on-screen keyboard, so on a touch till this is
  /// the difference between the keyboard covering half the product grid every
  /// time you come back to the main screen and it staying down until asked
  /// for. The cashier taps the search box to type; the barcode scanner keeps
  /// working either way, since it listens on the scaffold's own focus node.
  void _requestSearchFocus() {
    final settings = ref.read(settingsProvider);
    if (!settings.showProductSearch || !settings.autoFocusProductSearch) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_mayTakeFocus()) return;
      if (_searchFocusNode.canRequestFocus) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  /// Whether it is this bar's turn to hold the keyboard.
  bool _mayTakeFocus() {
    // A modal is open above the main screen (settings, payment, any dialog).
    // Its fields own the keyboard until it closes.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    // Something else on this screen already has the caret — the order note,
    // a quantity box, the customer search. Respect whatever the user is
    // actually typing in. A FocusScopeNode means "nothing in particular".
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null &&
        primary != _searchFocusNode &&
        primary is! FocusScopeNode) {
      return false;
    }
    return true;
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
        borderRadius: AppTheme.brXl,
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
            child: AdaptiveKeyboardTextField(
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
              borderRadius: AppTheme.brXl,
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

  /// A top-bar action: outlined, filled, and big enough to hit.
  ///
  /// These used to be bare white glyphs on a coloured bar with nothing around
  /// them — no edge, no hit target you could see, and at a glance no way to
  /// tell a button from the decoration. A border and a tint make each one read
  /// as a thing you press.
  Widget _navButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 46,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.75), width: 1.6),
              ),
              child: Icon(icon, color: iconColor ?? Colors.white, size: 23),
            ),
          ),
        ),
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
          borderRadius: AppTheme.brXl,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  /// connectivity_plus 6 reports a LIST of active transports, not one enum.
  /// The old `result != ConnectivityResult.none` compared a List to an enum —
  /// never equal, so `networkStateProvider` was pinned to true and the whole
  /// app believed it was online while the till sat on a dead link. Matches the
  /// idiom already used in `network_provider.dart`.
  static bool _hasNetwork(List<ConnectivityResult> results) =>
      results.isNotEmpty && !results.contains(ConnectivityResult.none);

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() {
      _isOnline = _hasNetwork(results);
    });
    ref.read(networkStateProvider.notifier).state = _isOnline;
  }

  /// Clear the backlog of unpaid orders in one pass.
  ///
  /// Credentials first: this turns other people's open orders into collected
  /// cash on a day the operator chooses, which is a books decision, not a
  /// cashier one. Admin, or a holder of the same close sign-off permission —
  /// somebody trusted to accept a discrepancy is trusted to clear one.
  Future<void> _handleSettleUnpaid() async {
    final l10n = AppLocalizations.of(context);
    final elevation = await showAdminCredentialDialog(
      context,
      ref,
      title: l10n?.translate('settle_unpaid_orders'),
      description: l10n?.translate('enter_admin_credentials'),
      permission: Permissions.sessionsCloseUnbalanced,
    );
    if (elevation == null || !mounted) return;
    await showSettleUnpaidDialog(context: context, ref: ref);
  }

  /// Read a past trading day's Z figures from the till.
  ///
  /// Credentials first, every time: this exposes whole-day takings, and the
  /// till is typically left logged in as whichever cashier is on. An admin
  /// passes by being an admin; anyone else needs `pos:z:print`.
  ///
  /// See [showPrintZReportDialog].
  Future<void> _handleZReport() async {
    final l10n = AppLocalizations.of(context);
    // Refuse before asking for credentials — typing a password only to be
    // told no is worse than being told no.
    if (await zReportBlockedByOpenShift(ref.read(databaseProvider))) {
      if (mounted) {
        SnackBarHelper.error(
            context, l10n?.translate('z_report_blocked_open') ?? 'Close the Z first');
      }
      return;
    }
    if (!mounted) return;
    final elevation = await showAdminCredentialDialog(
      context,
      ref,
      title: l10n?.translate('print_z_report'),
      description: l10n?.translate('enter_admin_credentials'),
      permission: Permissions.zPrint,
    );
    if (elevation == null || !mounted) return;
    await showPrintZReportDialog(context: context, ref: ref);
  }

  void _showCurrentSessionDetails() async {
    final l10n = AppLocalizations.of(context);
    final currencyFormatter = ref.read(currencyFormatterProvider);
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      SnackBarHelper.showToast(l10n?.translate('no_user_logged_in') ?? 'No user logged in', kind: ToastKind.info);
      return;
    }

    final database = ref.read(databaseProvider);
    final sessionService = SessionService(database);
    final session = await sessionService.getActiveSession(currentUser.id);

    if (session == null) {
      if (mounted) {
        SnackBarHelper.showToast(l10n?.translate('no_active_session') ?? 'No active session', kind: ToastKind.info);
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
            // Reports for the shift in progress (X, products, options,
            // orders) — read-only, so safe on a live session. Same dialog
            // Sessions management offers, so the two cannot drift.
            TextButton.icon(
              onPressed: () => showSessionReportsDialog(
                context: context,
                ref: ref,
                session: session,
              ),
              icon: const Icon(Icons.assessment_outlined, size: 18),
              label: Text(l10n?.translate('session_reports') ?? 'Reports'),
            ),
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
          builder: (ctx) {
            final cs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              icon: const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFD97706), size: 30),
              title: Text(
                l10n?.translate('held_orders_warning_title') ??
                    'Unsaved held orders',
                textAlign: TextAlign.center,
              ),
              content: Text(
                (l10n?.translate('held_orders_warning_body') ??
                        'You have {0} held order(s) in memory that will be lost if you log out. Continue?')
                    .replaceAll('{0}', heldOrders.length.toString()),
                textAlign: TextAlign.center,
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l10n?.translate('cancel') ?? 'Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  ),
                  label: Text(l10n?.translate('logout') ?? 'Logout'),
                ),
              ],
            );
          },
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

      // Z close availability — offered next to End Session. The dialog it
      // opens re-checks every Z rule; this only decides whether to offer it.
      final openZForClose = await ref.read(zServiceProvider).getOpenZ();
      final canCloseZ = openZForClose != null &&
          ref.read(permissionServiceProvider).hasPermission(Permissions.zClose);

      // Show dialog asking user to pause or end session — a clear, tappable
      // list of options (each with an icon + one-line explanation) instead of a
      // cramped row of colored buttons.
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dctx) {
          final dcs = Theme.of(dctx).colorScheme;
          // Semantic accents (caution / destructive / brand) — tinted at low
          // alpha so they read on both light and dark surfaces.
          const pauseColor = Color(0xFFD97706); // amber
          const endColor = Color(0xFFDC2626); // red

          Widget optionTile({
            required IconData icon,
            required Color color,
            required String title,
            required String subtitle,
            required String value,
          }) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: color.withValues(alpha: 0.10),
                borderRadius: AppTheme.brLg,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(dctx).pop(value),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: AppTheme.brLg,
                      border: Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: color, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(subtitle,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: dcs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: color.withValues(alpha: 0.7)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            icon: Icon(Icons.logout_rounded, color: dcs.primary, size: 30),
            title: Text(l10n?.translate('logout') ?? 'Logout',
                textAlign: TextAlign.center),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n?.translate('what_to_do_with_session') ??
                        'What would you like to do with your current session?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: dcs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 18),
                  optionTile(
                    icon: Icons.pause_circle_outline,
                    color: pauseColor,
                    title: l10n?.translate('pause_session') ?? 'Pause Session',
                    subtitle: l10n?.translate('pause_resume_info_short') ??
                        'Resume when you log in again',
                    value: 'pause',
                  ),
                  optionTile(
                    icon: Icons.stop_circle_outlined,
                    color: endColor,
                    title: l10n?.translate('end_session') ?? 'End Session',
                    subtitle: l10n?.translate('end_close_info_short') ??
                        'Close session and calculate totals',
                    value: 'end',
                  ),
                  if (canCloseZ)
                    optionTile(
                      icon: Icons.point_of_sale,
                      color: dcs.primary,
                      title: l10n?.translate('close_z') ?? 'Close Z',
                      subtitle: l10n?.translate('close_z_info_short') ??
                          'Close the whole shift and print the Z report',
                      value: 'closez',
                    ),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dctx).pop('cancel'),
                child: Text(l10n?.translate('cancel') ?? 'Cancel'),
              ),
            ],
          );
        },
      );

      if (choice == 'cancel' || choice == null) {
        return;
      }

      if (choice == 'pause') {
        // Pause session
        if (await sessionService.pauseSession(session.id)) {
          await notifySessionPauseChange(ref.read, session.id);
        }
        if (mounted) {
          SnackBarHelper.showToast(l10n?.translate('session_paused_resume_login') ?? 'Session paused. Resume when you login again.', kind: ToastKind.warning);
        }
        await Future.delayed(const Duration(milliseconds: 500));
        await _doLogout();
      } else if (choice == 'end') {
        // End session via the cash-count dialog. That dialog now owns the
        // optional "Print X report" checkbox (when Z tracking is on), so there
        // is no follow-up confirmation dialog here.
        final result = await showCloseSessionDialog(
          context: context,
          ref: ref,
          sessionId: session.id,
        );
        if (!result.closed) return; // user backed out — keep them logged in

        if (mounted) {
          SnackBarHelper.showToast(l10n?.translate('session_ended_successfully') ?? 'Session ended successfully.', kind: ToastKind.success);
        }
        await Future.delayed(const Duration(milliseconds: 500));
        await _doLogout();
      } else if (choice == 'closez') {
        // The session close with "close the Z" ticked: the cash is counted,
        // then the Z closes on this — its last — session.
        final result = await showCloseSessionDialog(
          context: context,
          ref: ref,
          sessionId: session.id,
          closeZ: true,
        );
        if (!result.closed) return;
        final closed = result.zClosed;
        if (mounted) {
          SnackBarHelper.showToast(closed
                  ? (l10n?.translate('z_closed') ?? 'Z closed')
                  : (l10n?.translate('session_ended_successfully') ??
                      'Session ended successfully.'), kind: ToastKind.success);
        }
        await Future.delayed(const Duration(milliseconds: 500));
        await _doLogout();
      }
    } catch (e) {
      _logger.error('Logout error: $e');
      if (mounted) {
        SnackBarHelper.showToast('${l10n?.translate('error') ?? 'Error'}: $e', kind: ToastKind.error);
      }
      await _doLogout();
    }
  }

  /// Pauses any still-active session for [userId] then pushes all local data
  /// to the server before the user leaves. Errors are swallowed — logout
  /// must never be blocked by a failed sync.
  Future<void> _syncAndCloseBeforeLogout(int? userId) async {
    try {
      final database = ref.read(databaseProvider);
      final syncService = ref.read(dataSyncServiceProvider);
      if (userId != null) {
        final session =
            await SessionService(database).getActiveSession(userId);
        // Pause, never end: a session still active here means the logout
        // dialog's End/Pause did not run (an error fell through to logout).
        // Ending it would close a cashier's shift nobody asked to close.
        if (session != null && session.status == 'active') {
          if (await SessionService(database).pauseSession(session.id)) {
            await notifySessionPauseChange(ref.read, session.id);
          }
        }
      }
      await syncService.syncPendingOperations();
      await Future.wait([
        syncService.syncSessionsBulk(),
        syncService.syncCashMovementsBulk(),
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
        builder: (dctx) {
          final dcs = Theme.of(dctx).colorScheme;
          return AlertDialog(
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: dcs.primary),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    AppLocalizations.of(dctx)?.translate('syncing_data') ??
                        'Syncing data...',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(dctx)?.translate('please_wait') ??
                        'Please wait…',
                    style:
                        TextStyle(fontSize: 12.5, color: dcs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        },
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
        borderRadius: AppTheme.brMd,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isOpen ? Colors.green.withOpacity(0.2) : Colors.white.withOpacity(0.1),
            borderRadius: AppTheme.brMd,
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
    final apiService = ref.read(apiServiceProvider);

    // Check if in demo mode
    if (apiService.isDemoMode()) {
      SnackBarHelper.showToast(l10n?.translate('demo_mode_sync_unavailable') ?? 'Demo mode: Sync not available', kind: ToastKind.warning);
      return;
    }

    if (_syncing) return;
    _syncing = true;

    final step = ValueNotifier<String>(
        l10n?.translate('checking_for_updates') ?? 'Checking for updates…');
    // Closed by identity, never with a bare pop(): the UpdateWatcher opens
    // the update dialog on its own when the check finds a build, and a pop()
    // would close that one and leave this spinner up for good.
    DialogRoute<void>? progress;
    void showProgress() {
      progress = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Flexible(
                  child: ValueListenableBuilder<String>(
                    valueListenable: step,
                    builder: (_, text, _) => Text(text),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      Navigator.of(context).push(progress!);
    }

    void hideProgress() {
      final route = progress;
      progress = null;
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
    }

    try {
      // A new POS build comes first: installing it restarts the app, so
      // there is no point refreshing data it would reload anyway. Dismissed
      // (or the update server unreachable) → carry on with the data.
      if (UpdateService.platformSupported) {
        showProgress();
        final found = await ref
            .read(updateProvider.notifier)
            .checkForUpdates()
            .timeout(const Duration(seconds: 15), onTimeout: () => null)
            .catchError((_) => null);
        hideProgress();
        if (!mounted) return;
        if (found == true) {
          // Waits for the watcher's dialog when it already opened one.
          await showUpdateDialog(context,
              isMandatory: ref.read(updateProvider).updateRequired);
          if (!mounted) return;
        }
      }

      step.value = l10n?.translate('syncing_data') ?? 'Syncing data...';
      showProgress();
      await _syncData(l10n, apiService);
    } finally {
      hideProgress();
      _syncing = false;
    }
  }

  bool _syncing = false;

  Future<void> _syncData(AppLocalizations? l10n, ApiService apiService) async {
    try {
      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);

      // The terminal's category scope rides on login/refresh only — never on
      // the catalogue sync — so without this an admin hiding a category would
      // not reach a till that stays signed in. Failure is not fatal to a sync.
      await apiService.refreshTerminalInfo();

      // Push this till's edits, then take the server's copy of every order
      // in the open sessions (admin cancels, discounts, notes).
      await syncService.refreshOpenSessions();

      // Then download fresh data (also subscription, refund policy, tags).
      await syncService.syncAllData();

      // Settings that otherwise only refresh at login or on an SSE push.
      await refreshZConfig(ref);
      await syncService.syncIntegrationMappings();
      await syncService.syncPendingNotifications();

      // The grids watch their tables, but these per-product lookups are
      // one-shot reads and would keep serving the pre-sync catalogue.
      ref.invalidate(productComponentsProvider);
      ref.invalidate(productComponentGroupRulesProvider);
      ref.invalidate(productVariantsProvider);
      ref.invalidate(productAttributesProvider);

      final user = ref.read(currentUserProvider);
      if (user != null) {
        ref.read(currentUserProvider.notifier).state =
            await reloadCurrentUser(database, user);
      }

      if (mounted) {
        SnackBarHelper.showToast(l10n?.translate('data_synced_successfully') ?? 'Data synced successfully!', kind: ToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showToast('${l10n?.translate('sync_failed') ?? 'Sync failed'}: $e', kind: ToastKind.error);
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
        SnackBarHelper.showToast(l10n?.translate('session_ended_logging_out') ?? 'Session ended successfully. Logging out...', kind: ToastKind.success);

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
        SnackBarHelper.showToast('${l10n?.translate('failed_to_end_session') ?? 'Failed to end session'}: $e', kind: ToastKind.error);
      }
    }
  }

  Widget _buildSessionInfoRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
        return Theme.of(context).colorScheme.onSurfaceVariant;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentUser = ref.watch(currentUserProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < kBreakpointCompact;
    final isVeryCompact = screenWidth < 700;

    final hPad = isVeryCompact ? 8.0 : 16.0;
    final scheme = Theme.of(context).colorScheme;

    final showSearch =
        ref.watch(settingsProvider.select((s) => s.showProductSearch));
    // A query typed before the field was hidden would keep filtering the grid
    // with nothing on screen to clear it.
    if (!showSearch && ref.read(productSearchQueryProvider).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(productSearchQueryProvider.notifier).state = '';
      });
    }

    return Container(
      decoration: BoxDecoration(
        // Not `primaryColor`: this bar puts white on top of itself, and a dark
        // scheme's primary is a pale blue. See [AppTheme.bar].
        color: AppTheme.bar(scheme),
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
                  if (showSearch) ...[
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
                  ],
                  // Barcode + nav buttons only on non-compact (go to secondary row on compact)
                  if (!isCompact) ...[
                    _buildBarcodeScanToggle(),
                    const SizedBox(width: 4),
                    // The calculator's home. It used to sit in the category
                    // bar, which is a strange place for a general-purpose tool
                    // and disappears entirely once a full-page shop hides that
                    // bar. Here it is in the same place on every layout.
                    _navButton(
                      icon: Icons.calculate_outlined,
                      tooltip: l10n?.translate('calculator') ?? 'Calculator',
                      onPressed: () => showCalculatorDialog(context),
                    ),
                    if (ref.watch(permissionServiceProvider).hasPermission(Permissions.agendaView)) ...[
                      _navButton(
                        icon: Icons.calendar_month_outlined,
                        tooltip: 'Agenda',
                        onPressed: () => Navigator.pushNamed(context, '/agenda'),
                      ),
                      // Booking rides the same permission as the agenda: both
                      // are the diary, one reading it and one adding to it.
                      _navButton(
                        icon: Icons.event_available_outlined,
                        tooltip: AppLocalizations.of(context)
                                ?.translate('book_appointment') ??
                            'Book appointment',
                        onPressed: () =>
                            Navigator.pushNamed(context, '/booking'),
                      ),
                    ],
                    // Dashboard removed from the bar on request. The
                    // '/dashboard' route still exists in main.dart but nothing
                    // navigates to it any more — add an entry here or in the
                    // profile menu to bring it back.
                    if (ref.watch(permissionServiceProvider).hasPermission(Permissions.notesView))
                      _navButton(
                        icon: Icons.sticky_note_2_outlined,
                        tooltip: l10n?.translate('notes') ?? 'Notes',
                        onPressed: () => Navigator.pushNamed(context, '/notes'),
                      ),
                  ],
                  const Spacer(),
                  // Session, network, sync, customer display on non-compact only
                  if (!isCompact) ...[
                    _navButton(
                      icon: Icons.point_of_sale_outlined,
                      tooltip: l10n?.translate('session') ?? 'session',
                      onPressed: _showCurrentSessionDetails,
                    ),
                    _navButton(
                      icon: Icons.summarize_outlined,
                      tooltip: l10n?.translate('print_z_report') ?? 'Z report',
                      onPressed: _handleZReport,
                    ),
                    _navButton(
                      icon: Icons.price_check_rounded,
                      tooltip: l10n?.translate('settle_unpaid_orders') ??
                          'Settle unpaid orders',
                      onPressed: _handleSettleUnpaid,
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
                          backgroundColor: AppTheme.onBar,
                          foregroundColor: AppTheme.bar(scheme),
                          disabledBackgroundColor:
                              AppTheme.onBar.withValues(alpha: 0.45),
                          disabledForegroundColor:
                              AppTheme.bar(scheme).withValues(alpha: 0.5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          textStyle: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
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
                          backgroundColor: AppTheme.onBar,
                          child: Text(
                            currentUser?.effectiveDisplayName.substring(0, 1).toUpperCase() ?? 'U',
                            style: TextStyle(
                              color: AppTheme.bar(scheme),
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
              } else if (value == 'test_mode') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const TestModeScreen()));
              } else if (value == 'logout') {
                await _handleLogout();
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
                    // Deferred because the popup menu is still closing; the
                    // pin prompt needs the menu's route gone first.
                    Future.delayed(Duration.zero, () async {
                      if (!context.mounted) return;
                      if (!await SettingsLockDialog.unlock(context, ref)) {
                        return;
                      }
                      if (!context.mounted) return;
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

              // DISABLED-FOR-NOW: Cash movements and Notify admin are hidden
              // from the menu. Everything behind them is intact — the dialogs,
              // services, the cash_movements table and the paid-in/paid-out
              // figures in the session close math all still exist; with no
              // movements ever recorded those simply total zero. Re-enable by
              // uncommenting this block and the two imports at the top.
              /*
              // Cash movements — drawer in/out that isn't a sale. Sits next to
              // Sessions because it only makes sense against an open one, and
              // rides on the same permission: whoever may end a session and
              // count the drawer is who explains what left it.
              if (permissionService.hasPermission(Permissions.sessionsEnd)) {
                items.add(PopupMenuItem(
                  value: 'cash_movements',
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('cash_movements') ?? 'Cash movements'),
                    ],
                  ),
                  onTap: () {
                    // Deferred: the menu has to finish closing before another
                    // route/dialog is pushed, same pattern as Settings above.
                    Future.delayed(Duration.zero, () {
                      showCashMovementDialog(context: context, ref: ref);
                    });
                  },
                ));
              }

              // Notify admin — a GENERAL push to the owner's phone. Ungated:
              // "the card machine is down" is exactly the message a junior
              // cashier alone on shift needs to be able to send.
              items.add(PopupMenuItem(
                value: 'notify_admin',
                child: Row(
                  children: [
                    const Icon(Icons.campaign_outlined),
                    const SizedBox(width: 8),
                    Text(l10n?.translate('notify_admin') ?? 'Notify admin'),
                  ],
                ),
                onTap: () {
                  Future.delayed(Duration.zero, () {
                    showNotifyAdminDialog(context: context, ref: ref);
                  });
                },
              ));
              */

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
                items.add(PopupMenuItem(
                  value: 'kitchen_board',
                  child: Row(
                    children: [
                      const Icon(Icons.soup_kitchen_outlined),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('kitchen_board') ?? 'Kitchen'),
                    ],
                  ),
                  // After the menu closes, or the dialog opens under it.
                  onTap: () => WidgetsBinding.instance.addPostFrameCallback(
                      (_) => showKitchenBoardDialog(context)),
                ));
              }

              // Refunds screen — every refund given (this till, and all tills
              // from the server). The refund ACTION is the main-screen button.
              if (permissionService
                  .hasRefundPermission(Permissions.refundsView)) {
                items.add(PopupMenuItem(
                  value: 'refunds',
                  child: Row(
                    children: [
                      const Icon(Icons.assignment_return, color: Colors.deepOrange),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('refunds') ?? 'Refunds'),
                    ],
                  ),
                  onTap: () {
                    Navigator.pushNamed(context, '/refunds');
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

              // DISABLED-FOR-NOW: Devices is hidden from the menu. The screen
              // and its '/devices' route are untouched, so re-enabling is just
              // uncommenting this block. Nothing else navigates there, so with
              // this commented out the screen is simply unreachable.
              /*
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
              */

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
                items.add(PopupMenuItem(
                  value: 'booking',
                  child: Row(
                    children: [
                      const Icon(Icons.event_available_outlined),
                      const SizedBox(width: 8),
                      Text(l10n?.translate('book_appointment') ??
                          'Book appointment'),
                    ],
                  ),
                  onTap: () {
                    Navigator.pushNamed(context, '/booking');
                  },
                ));
              }

              // Printers — settings-grade: the same permission and the same
              // pin as Settings itself. The screen enforces both again for the
              // other ways in; this only decides whether to offer the item.
              if (SettingsLockDialog.canOpenPrinters(ref)) {
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

              // Debug/profile builds only: the tree shaker drops this from
              // release, so a till never shows it.
              if (!kReleaseMode) {
                items.add(PopupMenuItem(
                  value: 'test_mode',
                  child: const Row(
                    children: [
                      Icon(Icons.science_outlined),
                      SizedBox(width: 8),
                      Text('Test mode (debug)'),
                    ],
                  ),
                ));
              }

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

              // Full logout moved to Settings: wiping the terminal is a setup
              // action, not something to sit one tap from Logout in a menu the
              // cashier opens all shift.

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
              color: AppTheme.barAlt(scheme),
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: Row(
                children: [
                  if (!isVeryCompact) ...[
                    const _TopBarClock(),
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
                  IconButton(
                    icon: const Icon(Icons.summarize_outlined,
                        color: Colors.white, size: 18),
                    tooltip: l10n?.translate('print_z_report') ?? 'Z report',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: _handleZReport,
                  ),
                  IconButton(
                    icon: const Icon(Icons.price_check_rounded,
                        color: Colors.white, size: 18),
                    tooltip: l10n?.translate('settle_unpaid_orders') ??
                        'Settle unpaid orders',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: _handleSettleUnpaid,
                  ),
                  IconButton(
                    icon: const Icon(Icons.calculate_outlined,
                        color: Colors.white, size: 18),
                    tooltip: l10n?.translate('calculator') ?? 'Calculator',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => showCalculatorDialog(context),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isOnline
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.3),
                      borderRadius: AppTheme.brXl,
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


/// The compact bar's clock, in a widget of its own so its once-a-second tick
/// redraws these few glyphs instead of rebuilding the whole top bar — which it
/// did even on wide screens where the clock is never shown.
class _TopBarClock extends ConsumerWidget {
  const _TopBarClock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(timeProvider).value ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return RepaintBoundary(
      child: Text(
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 13,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
