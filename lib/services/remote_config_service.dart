import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

import '../domain/models/app_settings.dart';
import '../providers/database_providers.dart';
import '../providers/settings_provider.dart';
import 'diagnostics_service.dart';
import 'printing_service.dart';

/// Why a remote setting change was refused.
class _Rejected implements Exception {
  final String reason;
  _Rejected(this.reason);
}

/// One remotely editable setting: how to check the value and which existing
/// setter stores it, so a remote change takes the same path as the settings
/// screen (persisted, side effects, live UI update).
class _Key {
  final Object? Function(Object? raw) parse;
  final Future<void> Function(SettingsNotifier n, dynamic v) apply;
  const _Key(this.parse, this.apply);
}

/// The remote console's settings and printer commands: get_config,
/// set_config, get_printers, set_printers, test_print.
///
/// set_config only touches the keys in [_allow]: display, buttons, sync, KDS
/// and waiter behaviour, ticket text. Nothing that changes an amount, a tax,
/// a report, a permission or a password is reachable (user ruling 2026-11-20).
class RemoteConfigService {
  final Ref _ref;
  RemoteConfigService(this._ref);

  static final _secret =
      RegExp(r'pass|token|secret|pin$|api_?key|hash', caseSensitive: false);

  // ── value checks ────────────────────────────────────────────────────────

  static bool _bool(Object? v) {
    if (v is bool) return v;
    throw _Rejected('expected true or false');
  }

  static int Function(Object?) _int(int min, int max) => (v) {
        if (v is num && v == v.roundToDouble()) {
          final i = v.toInt();
          if (i >= min && i <= max) return i;
        }
        throw _Rejected('expected an integer from $min to $max');
      };

  static double Function(Object?) _double(double min, double max) => (v) {
        if (v is num && v >= min && v <= max) return v.toDouble();
        throw _Rejected('expected a number from $min to $max');
      };

  static String Function(Object?) _text(int maxLength) => (v) {
        if (v is String && v.length <= maxLength) return v;
        throw _Rejected('expected text of at most $maxLength characters');
      };

  static String Function(Object?) _oneOf(List<String> values) => (v) {
        if (v is String && values.contains(v)) return v;
        throw _Rejected('expected one of ${values.join(', ')}');
      };

  static List<String> _textList(Object? v, {int maxItems = 50, int maxLength = 120}) {
    if (v is List && v.length <= maxItems && v.every((e) => e is String && e.length <= maxLength)) {
      return v.cast<String>();
    }
    throw _Rejected('expected a list of at most $maxItems texts');
  }

  static Map<String, String> _textMap(Object? v) {
    if (v is Map && v.length <= 20 && v.entries.every((e) => e.key is String && e.value is String && (e.value as String).length <= 2000)) {
      return v.map((k, val) => MapEntry(k as String, val as String));
    }
    throw _Rejected('expected {ticketType: text}');
  }

  static _Key _flag(Future<void> Function(SettingsNotifier, bool) set) =>
      _Key(_bool, (n, v) => set(n, v as bool));

  // ── the allowlist ───────────────────────────────────────────────────────

  late final Map<String, _Key> _allow = {
    'isDarkMode': _flag((n, v) => n.setDarkMode(v)),
    'language': _Key(_oneOf(['en', 'fr', 'ar', 'es']), (n, v) => n.setLanguage(v)),
    'loggingLanguage':
        _Key(_oneOf(['en', 'fr', 'ar', 'es']), (n, v) => n.setLoggingLanguage(v)),
    'categoryDisplayMode': _Key(
        _oneOf(CategoryDisplayMode.values.map((e) => e.name).toList()),
        (n, v) => n.setCategoryDisplayMode(
            CategoryDisplayMode.values.byName(v as String))),
    'componentGroupDisplayMode': _Key(
        _oneOf(ComponentGroupDisplayMode.values.map((e) => e.name).toList()),
        (n, v) => n.setComponentGroupDisplayMode(
            ComponentGroupDisplayMode.values.byName(v as String))),
    'buttonOrder': _Key((v) {
      final order = _textList(v);
      final known = _ref.read(settingsProvider).buttonOrder.toSet();
      // A reorder, never a way to add or drop a button.
      if (order.toSet().length != order.length ||
          !order.toSet().containsAll(known) ||
          !known.containsAll(order)) {
        throw _Rejected('must be a reordering of ${known.join(', ')}');
      }
      return order;
    }, (n, v) => n.setButtonOrder(v as List<String>)),
    'actionButtonAlignment': _Key(
        _oneOf(ActionButtonAlignment.values.map((e) => e.name).toList()),
        (n, v) => n.setActionButtonAlignment(
            ActionButtonAlignment.values.byName(v as String))),
    'orderPanelOnRight': _flag((n, v) => n.setOrderPanelOnRight(v)),
    // Toolbar buttons. Discount, refund and tip stay out: hiding or showing
    // them changes who can move money.
    'showTableButton': _flag((n, v) => n.setShowTableButton(v)),
    'showCustomerButton': _flag((n, v) => n.setShowCustomerButton(v)),
    'showCommercialButton': _flag((n, v) => n.setShowCommercialButton(v)),
    'showWaiterButton': _flag((n, v) => n.setShowWaiterButton(v)),
    'showCouponButton': _flag((n, v) => n.setShowCouponButton(v)),
    'showPrintButton': _flag((n, v) => n.setShowPrintButton(v)),
    'showPersonsButton': _flag((n, v) => n.setShowPersonsButton(v)),
    'showOrderTypeButton': _flag((n, v) => n.setShowOrderTypeButton(v)),
    'showConfirmOrderButton': _flag((n, v) => n.setShowConfirmOrderButton(v)),
    'showPayButton': _flag((n, v) => n.setShowPayButton(v)),
    'showProceedButton': _flag((n, v) => n.setShowProceedButton(v)),
    'showDailySummaryButton': _flag((n, v) => n.setShowDailySummaryButton(v)),
    'showCashDrawerButton': _flag((n, v) => n.setShowCashDrawerButton(v)),
    'showCancelOrderButton': _flag((n, v) => n.setShowCancelOrderButton(v)),
    'showTagsButton': _flag((n, v) => n.setShowTagsButton(v)),
    'showReserveButton': _flag((n, v) => n.setShowReserveButton(v)),
    'autoSyncOnline': _flag((n, v) => n.setAutoSyncOnline(v)),
    'bulkSyncSize': _Key(_int(1, 1000), (n, v) => n.setBulkSyncSize(v)),
    'autoSyncDurationMinutes':
        _Key(_int(1, 1440), (n, v) => n.setAutoSyncDuration(v)),
    'sseEnabled': _flag((n, v) => n.setSseEnabled(v)),
    'enableSnackBars': _flag((n, v) => n.setEnableSnackBars(v)),
    'enableCustomerDisplay': _flag((n, v) => n.setEnableCustomerDisplay(v)),
    'autoUpdate': _flag((n, v) => n.setAutoUpdate(v)),
    'openOnStartup': _flag((n, v) => n.setOpenOnStartup(v)),
    'autoStartServer': _flag((n, v) => n.setAutoStartServer(v)),
    'kitchenTargetMinutes':
        _Key(_int(1, 240), (n, v) => n.setKitchenTargetMinutes(v)),
    'printWaiterOrderTicket': _flag((n, v) => n.setPrintWaiterOrderTicket(v)),
    'printWaiterPaper': _flag((n, v) => n.setPrintWaiterPaper(v)),
    'waiterKdsBatchSeconds':
        _Key(_int(0, 600), (n, v) => n.setWaiterKdsBatchSeconds(v)),
    'waiterCallEnabled': _flag((n, v) => n.setWaiterCallEnabled(v)),
    'waiterCallRingUntilDismissed':
        _flag((n, v) => n.setWaiterCallRingUntilDismissed(v)),
    'waiterShowKitchenStatus': _flag((n, v) => n.setWaiterShowKitchenStatus(v)),
    'waiterNotifyReady': _flag((n, v) => n.setWaiterNotifyReady(v)),
    'waiterNotifyCanceled': _flag((n, v) => n.setWaiterNotifyCanceled(v)),
    'waiterNotifyRupture': _flag((n, v) => n.setWaiterNotifyRupture(v)),
    'waiterDashboardShowOwed': _flag((n, v) => n.setWaiterDashboardShowOwed(v)),
    'printKitchenCancellations':
        _flag((n, v) => n.setPrintKitchenCancellations(v)),
    'printDiscountReason': _flag((n, v) => n.setPrintDiscountReason(v)),
    'showOrderNumberInLists': _flag((n, v) => n.setShowOrderNumberInLists(v)),
    'showOrderNumberOnKds': _flag((n, v) => n.setShowOrderNumberOnKds(v)),
    'showOrderNumberOnWaiter': _flag((n, v) => n.setShowOrderNumberOnWaiter(v)),
    'ticketHeader': _Key(_text(2000), (n, v) => n.setTicketHeader(v)),
    'ticketFooter': _Key(_text(2000), (n, v) => n.setTicketFooter(v)),
    'ticketHeaders': _Key(_textMap, (n, v) async {
      for (final e in (v as Map<String, String>).entries) {
        await n.setTicketHeaderFor(e.key, e.value);
      }
    }),
    'ticketFooters': _Key(_textMap, (n, v) async {
      for (final e in (v as Map<String, String>).entries) {
        await n.setTicketFooterFor(e.key, e.value);
      }
    }),
    'notePresets': _Key((v) => _textList(v), (n, v) => n.setNotePresets(v)),
    'showOnscreenKeyboard': _flag((n, v) => n.setShowOnscreenKeyboard(v)),
    'onscreenKeyboardWidthFraction': _Key(
        _double(0.2, 1.0), (n, v) => n.setOnscreenKeyboardWidthFraction(v)),
    'productCardSize': _Key(_int(1, 5), (n, v) => n.setProductCardSize(v)),
    'productLabelOverlay': _flag((n, v) => n.setProductLabelOverlay(v)),
    'showBackTileInProductGrid':
        _flag((n, v) => n.setShowBackTileInProductGrid(v)),
    'showFavoritesCategory': _flag((n, v) => n.setShowFavoritesCategory(v)),
    'sortByLastUsed': _flag((n, v) => n.setSortByLastUsed(v)),
    'autoFocusProductSearch': _flag((n, v) => n.setAutoFocusProductSearch(v)),
    'showProductSearch': _flag((n, v) => n.setShowProductSearch(v)),
    'externalQueueGridView': _flag((n, v) => n.setExternalQueueGridView(v)),
    'numericKeypadBeta': _flag((n, v) => n.setNumericKeypadBeta(v)),
    'agendaTimeStep': _Key(_int(5, 240), (n, v) => n.setAgendaTimeStep(v)),
  };

  /// For the capabilities list and the tests.
  Set<String> get allowedKeys => _allow.keys.toSet();

  Map<String, dynamic> _settingsJson() =>
      Map<String, dynamic>.from(_ref.read(settingsProvider).toJson())
        ..removeWhere((k, _) => _secret.hasMatch(k));

  // ── get_config ──────────────────────────────────────────────────────────

  Map<String, dynamic> getConfig(Map<String, dynamic> command) {
    final api = _ref.read(apiServiceProvider);
    final all = <String, dynamic>{
      'settings': _settingsJson(),
      'editable': allowedKeys.toList()..sort(),
      'terminal': {
        'posName': api.getPosName(),
        'posId': api.getPosId(),
        'businessId': api.getBusinessId(),
        'tenantId': api.getTenantId(),
        'baseUrl': api.getBaseUrl(),
      },
      'printers': _printerConfigJson(),
    };
    final section = (command['section'] as String?)?.trim();
    if (section == null || section.isEmpty) return all;
    if (!all.containsKey(section)) {
      throw ArgumentError('unknown section: $section (${all.keys.join(', ')})');
    }
    return {section: all[section]};
  }

  // ── set_config ──────────────────────────────────────────────────────────

  /// Applies what passes the allowlist and its checks; the rest comes back in
  /// `rejected` with the reason. Valid keys apply even when others fail.
  Future<Map<String, dynamic>> setConfig(Map<String, dynamic> command) async {
    final changes = command['changes'];
    if (changes is! Map || changes.isEmpty) {
      throw ArgumentError('changes must be a non-empty object');
    }
    final notifier = _ref.read(settingsProvider.notifier);
    final before = _settingsJson();
    final rejected = <String, String>{};
    final applied = <String>[];
    for (final entry in changes.entries) {
      final key = '${entry.key}';
      final spec = _allow[key];
      if (spec == null) {
        rejected[key] = 'not remotely editable';
        continue;
      }
      try {
        await spec.apply(notifier, spec.parse(entry.value));
        applied.add(key);
      } on _Rejected catch (e) {
        rejected[key] = e.reason;
      } catch (e) {
        rejected[key] = 'failed: $e';
      }
    }
    final after = _settingsJson();
    return {
      'applied': applied,
      'before': {for (final k in applied) k: before[k]},
      'after': {for (final k in applied) k: after[k]},
      'rejected': rejected,
    };
  }

  // ── printers ────────────────────────────────────────────────────────────

  Map<String, dynamic> _printerConfigJson() {
    final printing = _ref.read(printingServiceProvider);
    final c = printing.config;
    return {
      'receipt': {
        'address': c.receiptPrinterAddress,
        'name': c.receiptPrinterName,
        'connectionType': c.receiptConnectionType?.name,
      },
      'kds': {
        'address': c.kdsPrinterAddress,
        'name': c.kdsPrinterName,
        'connectionType': c.kdsConnectionType?.name,
        'enabled': c.kdsEnabled,
        'printMode': c.defaultKdsMode.name,
      },
      'printingEnabled': c.printingEnabled,
      'pool': [
        for (final p in printing.printerPool)
          {
            'id': p.id,
            'label': p.label,
            'address': p.address,
            'name': p.name,
            'connectionType': p.connectionType.name,
          }
      ],
    };
  }

  Future<Map<String, dynamic>> getPrinters() async {
    List<Map<String, dynamic>>? os;
    try {
      final snap = await DiagnosticsService.snapshot()
          .timeout(const Duration(seconds: 10));
      os = [
        for (final p in snap.printers)
          {
            'name': p.name,
            'port': p.port,
            'driver': p.driver,
            'jobs': p.jobs,
            'statusFlags': p.statusFlags,
          }
      ];
    } catch (_) {}
    return {..._printerConfigJson(), 'osPrinters': os};
  }

  static ConnectionType? _connection(Object? v) {
    if (v == null) return null;
    final s = '$v'.toUpperCase();
    for (final t in ConnectionType.values) {
      if (t.name == s) return t;
    }
    throw _Rejected(
        'connectionType must be ${ConnectionType.values.map((e) => e.name).join('|')}');
  }

  static String? _address(Object? v) {
    if (v == null) return null;
    if (v is String && v.trim().isNotEmpty && v.length <= 200) return v.trim();
    throw _Rejected('expected a non-empty address');
  }

  /// `{changes: {receipt?: {name?, address?, connectionType?},
  /// kds?: {…, kdsPrintMode?}, pool?: {"<printer name>": {name?, address?,
  /// connectionType?}}}}` — values come in as text from the back office.
  /// Only where to print and the kitchen print mode; every printing rule
  /// stays as configured. Each bad field lands in `rejected` under its path;
  /// the good ones still apply.
  Future<Map<String, dynamic>> setPrinters(Map<String, dynamic> command) async {
    final printing = _ref.read(printingServiceProvider);
    final prefs = _ref.read(sharedPreferencesProvider);
    final before = _printerConfigJson();
    final rejected = <String, String>{};
    final changes = command['changes'] is Map ? command['changes'] as Map : command;

    Map? section(String name) {
      final s = changes[name];
      if (s == null) return null;
      if (s is! Map) {
        rejected[name] = 'expected an object';
        return null;
      }
      return s;
    }

    /// Runs [parse] on one field, recording a refusal under [path].
    T? field<T>(String path, Map s, String key, T? Function(Object?) parse) {
      if (!s.containsKey(key)) return null;
      try {
        return parse(s[key]);
      } on _Rejected catch (e) {
        rejected[path] = e.reason;
      } catch (e) {
        rejected[path] = 'invalid: $e';
      }
      return null;
    }

    String? name(Object? v) {
      final t = v?.toString().trim();
      if (t == null || t.isEmpty || t.length > 120) {
        throw _Rejected('expected a name of 1 to 120 characters');
      }
      return t;
    }

    KdsPrintMode? mode(Object? v) {
      final t = v?.toString().trim();
      for (final m in KdsPrintMode.values) {
        if (m.name.toLowerCase() == t?.toLowerCase()) return m;
      }
      throw _Rejected(
          'kdsPrintMode must be ${KdsPrintMode.values.map((e) => e.name).join('|')}');
    }

    var config = printing.config;
    final receipt = section('receipt');
    if (receipt != null) {
      if (receipt.containsKey('kdsPrintMode')) {
        rejected['receipt.kdsPrintMode'] = 'only the kds printer has a print mode';
      }
      config = config.copyWith(
        receiptPrinterName: field('receipt.name', receipt, 'name', name),
        receiptPrinterAddress:
            field('receipt.address', receipt, 'address', _address),
        receiptConnectionType: field(
            'receipt.connectionType', receipt, 'connectionType', _connection),
      );
    }
    final kds = section('kds');
    if (kds != null) {
      config = config.copyWith(
        kdsPrinterName: field('kds.name', kds, 'name', name),
        kdsPrinterAddress: field('kds.address', kds, 'address', _address),
        kdsConnectionType:
            field('kds.connectionType', kds, 'connectionType', _connection),
        defaultKdsMode: field('kds.kdsPrintMode', kds, 'kdsPrintMode', mode),
      );
    }
    if (receipt != null || kds != null) {
      await printing.saveConfig(prefs, config);
    }

    final pool = changes['pool'];
    if (pool != null) {
      if (pool is! Map) {
        rejected['pool'] = 'expected {"<printer name>": {...}}';
      } else {
        final list = List.of(printing.printerPool);
        for (final entry in pool.entries) {
          final key = '${entry.key}';
          final i = list.indexWhere(
              (p) => p.name == key || p.label == key || p.id == key);
          if (i < 0) {
            // Editing only: adding or removing a printer changes routing
            // nobody on site agreed to.
            rejected['pool.$key'] = 'unknown printer';
            continue;
          }
          final v = entry.value;
          if (v is! Map) {
            rejected['pool.$key'] = 'expected an object';
            continue;
          }
          if (v.containsKey('kdsPrintMode')) {
            rejected['pool.$key.kdsPrintMode'] =
                'pool printers follow the kitchen print mode';
          }
          list[i] = list[i].copyWith(
            name: field('pool.$key.name', v, 'name', name),
            address: field('pool.$key.address', v, 'address', _address),
            connectionType: field(
                'pool.$key.connectionType', v, 'connectionType', _connection),
          );
        }
        await printing.savePrinterPool(prefs, list);
      }
    }
    return {'before': before, 'after': _printerConfigJson(), 'rejected': rejected};
  }

  /// `{target: receipt|kds|<pool printer name>}`.
  Future<Map<String, dynamic>> testPrint(Map<String, dynamic> command) async {
    final printing = _ref.read(printingServiceProvider);
    final target = '${command['target'] ?? 'receipt'}'.trim();
    bool ok;
    switch (target.toLowerCase()) {
      case 'receipt':
        ok = await printing.printTestPage(PrinterPurpose.receipt);
      case 'kds':
        ok = await printing.printTestPage(PrinterPurpose.kds);
      default:
        final p = printing.printerPool
            .where((p) => p.name == target || p.label == target || p.id == target)
            .firstOrNull;
        if (p == null) throw ArgumentError('unknown printer: $target');
        ok = await printing.testPoolPrinter(p);
    }
    if (!ok) throw StateError('the printer did not answer ($target)');
    return {'target': target, 'printed': true};
  }
}

final remoteConfigServiceProvider = Provider<RemoteConfigService>((ref) {
  return RemoteConfigService(ref);
});
