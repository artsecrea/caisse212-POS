---
name: caisse212-printing-service
description: Integrate, configure, or extend the caisse212 Flutter thermal-printing service (`printing_service.dart`). Use when the user asks about ESC/POS receipt + KDS printing, per-station printer routing, a `PrinterConfig` / `PrintRule` setup, NETWORK printers over raw TCP, cash-drawer kick, or wiring `flutter_thermal_printer` + `esc_pos_utils_plus` into a Riverpod app. Also covers porting the service into a non-Riverpod codebase.
---

# caisse212 PrintingService — integration & extension skill

This skill documents the public API and integration steps for the
caisse212 `printing_service.dart` — a singleton service that wraps
`flutter_thermal_printer` + `esc_pos_utils_plus` with:

- A persisted `PrinterConfig` (SharedPrefs, hot-reload-safe).
- Two physical printer slots: **receipt** and **KDS**.
- A **named printer pool** that routes per-station kitchen tickets to
  different physical devices.
- A **rule engine** (`PrintRule`) gating each output (order ticket,
  customer receipt, store copy, KDS) by order type, order source, and
  whether a table is selected.
- First-class **NETWORK** printer support via raw `Socket.connect` (the
  upstream plugin only supports USB/BLE).
- Cash drawer pulse.
- Multi-station consolidated jobs to dodge Windows USB spooler races.
- "Modifications only" KDS mode that prints just the new/unprinted items.

The user will send you `printing_service.dart` alongside this skill.
Reference the file directly when answering — it is the source of truth;
this document is the map.

---

## 1. Required packages

Add to `pubspec.yaml`:

```yaml
dependencies:
  flutter_thermal_printer: ^2.0.0
  esc_pos_utils_plus: ^2.0.4
  image: ^4.7.2          # ESC/POS bitmap printing (logo)
  shared_preferences: ^2.x
  flutter_riverpod: ^2.5.1
  drift: ^2.20.3         # Only if the host project uses Drift
```

Optional if the host project wants matching theme colors for the printer
config UI:

```yaml
  flutter_onscreen_keyboard: ^0.4.1+1   # Touch-keyboard for IP/port input
```

> **NETWORK printers note.** `flutter_thermal_printer` v2 does **not**
> implement `ConnectionType.NETWORK`. The service handles network
> printers entirely outside the plugin by opening a raw `Socket` to
> `host:port` (default `9100`) and writing the ESC/POS bytes directly.
> Discovery (`startScan`) still returns only USB/BLE; network printers
> are added manually via `connectPrinter` or by saving a synthetic
> `Printer` into config.

---

## 2. Files to copy

Minimum surface to import into a new project:

| File | What it carries |
|---|---|
| `lib/services/printing_service.dart` | The service itself + `PrinterConfig`, `PrintRule`, `NamedPrinter`, `PrinterPurpose`, `KdsPrintMode`, `PrintOutput`. |
| Optional: provider wiring | `final printingServiceProvider = Provider<PrintingService>(...)`, `final sharedPreferencesProvider = Provider<SharedPreferences>(...)`. |

The service uses these external types from the host project:

- `CurrentOrder` — order-cart domain model with `.items: List<OrderItem>`,
  `.tableId`, `.tableName`, `.customerName`, `.customerPhone`,
  `.deliveryAddress`, `.type`, `.numberOfPersons`, `.orderCode`,
  `.discountPercentage`.
- `OrderItem` — `.displayName`, `.quantity`, `.totalPrice`,
  `.components`, `.productId`, `.id`, `.ticketId`, `.kdsPrintedAt`,
  `.note`, `.state`.
- `OrderItemComponent` — `.name`, `.quantity`, `.price`.
- An `AppDatabase` Drift class with `orderProducts`, `tickets`,
  `stations`, `productStations`, `products` tables.

If your project doesn't have these, see §10 for adapter patterns.

---

## 3. Initialization

```dart
// main.dart (or boot service)
final prefs = await SharedPreferences.getInstance();
final container = ProviderContainer(overrides: [
  sharedPreferencesProvider.overrideWithValue(prefs),
]);

final printingService = container.read(printingServiceProvider);
await printingService.initialize(prefs, container);
```

`initialize` loads the persisted `PrinterConfig` and the per-station
printer pool from SharedPrefs (keys all `printer_*` / `station_printer_*`),
sets up the discovery stream listener, and emits the loaded config on
`configStream`.

It's safe to call repeatedly (idempotent) — call once at boot.

---

## 4. Provider wiring (Riverpod)

```dart
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('Override in ProviderScope'),
);

final printingServiceProvider = Provider<PrintingService>((ref) {
  return PrintingService();  // singleton — internal factory pattern
});
```

The service is a **singleton** (`PrintingService._internal()`), so
`Provider` just returns the one instance. State lives inside the
service; Riverpod is used only as a dependency-injection vehicle.

---

## 5. Public API surface

### 5.1 Discovery

```dart
await printingService.startScan();      // USB + BLE
await printingService.stopScan();
printingService.printersStream;         // Stream<List<Printer>>
printingService.availablePrinters;      // current cache
printingService.isScanning;
```

For NETWORK printers, skip discovery — go straight to `connectPrinter`
with a manually constructed `Printer` whose `connectionType` is
`ConnectionType.NETWORK` and `address` is `host:port` (default
`:9100`).

### 5.2 Slot assignment

```dart
await printingService.setPrinter(prefs, printer, PrinterPurpose.receipt);
await printingService.setPrinter(prefs, printer, PrinterPurpose.kds);
await printingService.clearPrinter(prefs, PrinterPurpose.receipt);
```

### 5.3 The rule engine

```dart
enum PrintOutput { orderTicket, customerReceipt, storeCopy, kds }

bool shouldPrint(
  PrintOutput output, {
  required String orderType,           // 'DINE_IN' | 'TAKE_AWAY' | 'DELIVERY'
  required bool hasTable,
  String source = 'POS',               // 'POS' | 'WAITER' | 'KIOSK' | 'EXTERNAL'
})
```

Every print method either calls `shouldPrint` internally or expects the
caller to call it first. The cashier configures rules via the
`PrinterConfig.orderTicketRule` etc. (4 rules — one per output).

### 5.4 Order-time prints

```dart
await printingService.printOrderReceipt(
  order: currentOrder,
  cashierName: 'Othman',
  storeName: 'My Café',
  storeAddress: '...',
  storePhone: '...',
);

await printingService.printKdsTicket(
  order: currentOrder,
  cashierName: 'Othman',
  mode: KdsPrintMode.modificationsOnly,  // or .full
  stationIds: [],                         // empty = all stations
);
```

`printKdsTicket` honors `PrinterConfig.splitKdsByStation`:
- **off** → one consolidated kitchen ticket on the global KDS printer.
- **on** → groups items per station, resolves each station's target
  printer via the pool, dedups groups that share a printer, dispatches
  one ESC/POS job per physical device with paper cuts between sections.

### 5.5 Payment-time prints

```dart
await printingService.printPaymentDocuments(
  ticketId: 123,
  ticketNumber: '0001',
  amount: 220.0,
  paymentMethod: 'CASH',
  createdAt: DateTime.now(),
  items: [{...}],
  orderType: 'DINE_IN',
  hasTable: true,
  source: 'POS',
  // …optional store/customer/table fields
);
```

Orchestrates customer receipt × `customerCopies`, store copy, and the
cash drawer kick — each gated by its own `PrintRule`. Honors the
`autoPrintOnPayment` master switch.

### 5.6 Z-report and waiter slips (caisse212-specific)

```dart
await printingService.printDailySummaryReport(
  report: dailySummary,
  l10n: appLocalizations,
  currencyFormatter: ...,
  businessName: ...,
);

await printingService.printWaiterSettlementSlip(
  waiterName: 'Yassine B.',
  orders: [(code: 'W42_1', due: 220.0, tableName: 'T5'), ...],
  grandTotal: 825.0,
  cashierName: 'Othman',
);

await printingService.printWaiterProfileSummary(
  waiterName: 'Yassine B.',
  sessionLabel: 'Session #42',
  ordersCount: 7,
  totalPaid: 1420.0,
  totalOwed: 825.0,
  unpaidOrders: [(code, due, tableName), ...],
  paidTickets: [(ticketNum, paymentMethod, amount, at), ...],
);
```

These three bypass `shouldPrint` (operator-initiated, not auto-print).

### 5.7 Cash drawer

```dart
await printingService.kickCashDrawer();   // pulse via receipt printer
```

Auto-fired from `printPaymentDocuments` when `cashDrawerKick: true` and
(optionally) only on cash payments.

---

## 6. Configuration model

### 6.1 `PrinterConfig`

Persisted as flat SharedPrefs keys (one per field) plus four
JSON-encoded `PrintRule` blobs (one per `PrintOutput`).

```dart
class PrinterConfig {
  // Slots
  final String? receiptPrinterAddress;
  final String? receiptPrinterName;
  final ConnectionType? receiptConnectionType;
  final String? kdsPrinterAddress;
  final String? kdsPrinterName;
  final ConnectionType? kdsConnectionType;
  final bool kdsEnabled;
  final bool printingEnabled;        // master switch
  final PaperSize paperSize;         // 58 or 80mm
  final int textSize;                // 1=normal, 2=large, 3=extra
  final String printingLanguage;     // 'en' | 'fr' | 'ar' (drives CP table)

  // Rules
  final PrintRule orderTicketRule;
  final PrintRule customerReceiptRule;
  final PrintRule storeCopyRule;
  final PrintRule kdsRule;

  // Pro
  final bool autoPrintOnPayment;
  final int customerCopies;
  final bool reprintWatermark;       // stamp DUPLICATA on reprints
  final bool cashDrawerKick;
  final bool cashDrawerCashOnly;
  final bool splitKdsByStation;
  final KdsPrintMode defaultKdsMode; // .full | .modificationsOnly
  final bool consolidateKdsJob;      // dodges Windows USB driver races
}
```

### 6.2 `PrintRule`

```dart
class PrintRule {
  final bool enabled;
  final Set<String> orderTypes;   // {DINE_IN, TAKE_AWAY, DELIVERY}
  final Set<String> sources;      // {POS, WAITER, KIOSK, EXTERNAL}
  final bool requireTable;        // only print when a table is selected
}
```

A `shouldPrint` call returns `true` only when:
- `printingEnabled` is on,
- the rule itself is `enabled`,
- the order's type is in `orderTypes`,
- the order's source is in `sources`,
- `requireTable` is satisfied.

`fromJson` defaults unknown fields gracefully so old configs migrate
without manual intervention.

---

## 7. Per-station printer routing

Two SharedPrefs JSON blobs:

```
station_printer_pool_v1         — List<NamedPrinter>
station_printer_assignments_v1  — Map<String stationId, String printerId>
```

```dart
class NamedPrinter {
  final String id;           // uuid — stable key
  final String label;        // 'Bar', 'Grill 1', …
  final String address;
  final String name;
  final ConnectionType connectionType;
}
```

API:

```dart
await printingService.savePrinterPool(prefs, [NamedPrinter(...)]);
await printingService.saveStationAssignments(prefs, {3: 'uuid-of-printer'});
printingService.printerPool;
printingService.stationAssignments;
printingService.printerPoolStream;
printingService.stationAssignmentsStream;
```

At print time `printKdsTicket` resolves each item's stations (primary
`Products.stationId` + many-to-many `ProductStations`), then groups
sections by **resolved printer address**. Stations sharing a physical
printer collapse into one print job with paper cuts between sections.
Unassigned stations fall back to the global `kdsPrinterAddress` —
turning the feature into a no-op for existing installs.

---

## 8. NETWORK printers (raw TCP)

`flutter_thermal_printer` v2 returns `false` for any `connect(printer)`
call when `printer.connectionType == ConnectionType.NETWORK`. The
service handles this internally:

```dart
Future<bool> _sendBytesOverTcp(String address, List<int> bytes) async {
  final parts = address.split(':');
  final host = parts[0];
  final port = parts.length > 1 ? int.parse(parts[1]) : 9100;
  final sock = await Socket.connect(host, port, timeout: Duration(seconds: 5));
  sock.add(bytes);
  await sock.flush();
  await sock.close();
}
```

Every dispatch (`_dispatchBytes`) branches on `connectionType`:
- `NETWORK` → `_sendBytesOverTcp`.
- `USB`/`BLE` → `_thermalPrinter.printData(printer, bytes, longData: true)`.

For NETWORK, no persistent connection is kept — each print opens a
fresh socket. This is intentional: thermal-printer TCP stacks are
flaky about long-lived connections, and reopening costs ~50ms.

Reachability check:
```dart
final reachable = await printingService.testNetworkReachable('192.168.1.50:9100');
```

---

## 9. Common pitfalls

1. **Don't call `_ensurePrinterConnected` (or any consumer) from
   `initState`.** The service uses inherited widgets indirectly; defer
   to `didChangeDependencies` or `addPostFrameCallback`.

2. **Windows USB driver races.** Sending three sequential `printData`
   calls produces three spool jobs; some drivers stall on the third.
   The service mitigates with `consolidateKdsJob: true` (default), which
   concatenates per-station buffers into one job with paper cuts. If
   you still hit issues, drop to per-station mode with an 800ms cool-down
   between jobs (already implemented).

3. **`modificationsOnly` ghost prints.** "Modifications" = items with
   `ticketId == null && kdsPrintedAt == null`. Items already on a paid
   ticket don't count. Don't forget to clear `kdsPrintedAt` if you ever
   "unprint" an item.

4. **Hot-restart, not hot-reload, after schema/config changes.** The
   service is a long-lived singleton — hot-reload doesn't replace the
   instance.

5. **Empty/relative URLs as `NetworkImage`.** Not a printing-service
   bug, but the same project triggers `"No host specified in URI"` from
   passing `''` to `NetworkImage`. Validate that any imageUrl starts
   with `http://`/`https://` before constructing.

6. **The `_translate` / L10n calls.** The service localizes printed
   text using an `AppLocalizations` lookup. If you copy the service to
   a project without that exact L10n structure, replace `_text(key,
   fallback: ...)` calls with the fallback string and remove the L10n
   dependency.

---

## 10. Adapting to a non-caisse212 project

The service is mostly self-contained but assumes these host types:

| Host type | Service usage | Adapter strategy |
|---|---|---|
| `CurrentOrder` | Most print methods take this | Replace with your own order DTO + adapt field accesses. |
| `OrderItem` | `printKdsTicket`, `printOrderReceipt` | Same — your line-item DTO. |
| `AppDatabase` (Drift) | `_persistTickets`, `_markItemsAsPrinted`, station lookups | If you don't use Drift, replace the DB queries with whatever ORM you have, or take repository instances as constructor params. |
| `Ref` (Riverpod) | Reads `currencySymbolProvider`, `settingsProvider`, `databaseProvider` | Either keep Riverpod, or replace with constructor-injected callbacks. |
| `AppLocalizations` | `_translate`/`_text` for printed strings | Pass fallback strings directly. |

A minimal port checklist for a non-Riverpod project:
1. Strip Riverpod — make `PrintingService` take dependencies via
   constructor (`PrintingService(this._db, this._settings, this._currency)`).
2. Replace `Ref?` reads with stored fields.
3. Pass a `String currencySymbol` instead of reading
   `currencySymbolProvider`.
4. Replace `_text(key, fallback: '...')` with just the fallback string.
5. Replace `_loadBusinessLogo()` with whatever your project uses for
   logo bytes (or remove).

---

## 11. Configuration UI hints

If you want a Settings UI that matches caisse212's, mirror these
patterns:

- **Receipt + KDS slot pickers** — list `availablePrinters` from the
  service's scan stream; tap a row to call `setPrinter`. Manual NETWORK
  entry: small form (label + IP + port + assign-to-purpose) that
  constructs a `Printer(...)` and calls `setPrinter`.
- **Print Rules editor** — for each `PrintOutput`, render the rule's
  `enabled` switch + chip group of order types + chip group of sources
  + `requireTable` toggle. Persist via `_config.copyWith(...)` →
  `saveConfig`.
- **Per-station routing** — list the printer pool (add/edit/delete) and
  one dropdown per station (from your stations table) with
  "Use default KDS printer" as the null option. Persist via
  `savePrinterPool` / `saveStationAssignments`.
- **Master toggles** — `printingEnabled`, `kdsEnabled`,
  `autoPrintOnPayment`, `cashDrawerKick`/`cashDrawerCashOnly`,
  `splitKdsByStation`, `consolidateKdsJob`, `defaultKdsMode`,
  `reprintWatermark`, `customerCopies`.

---

## 12. Sanity checks before you ship

- [ ] `flutter analyze lib/services/printing_service.dart` is clean.
- [ ] Hot-restart the app and confirm `PrintingService` loads
  `_loadStationRouting` (check `printerPool` is non-null after init).
- [ ] Trigger one print of each type the project uses (order ticket,
  KDS, customer receipt) on at least one USB and one NETWORK printer.
- [ ] Confirm `_dispatchBytes` honors `connectionType` — NETWORK should
  hit `_sendBytesOverTcp`, never `_thermalPrinter.connect`.
- [ ] Stress the per-station path: assign two stations to the same
  pool printer, ring an order spanning both, confirm ONE job hits the
  device with two sections + cut between.
- [ ] Multi-station product: confirm the same item prints on every
  station it belongs to (deduped per printer address).

---

## 13. Quick command reference

```dart
// Scan + connect
service.startScan();
service.stopScan();
service.setPrinter(prefs, printer, PrinterPurpose.receipt);

// Gate
service.shouldPrint(PrintOutput.orderTicket,
    orderType: 'DINE_IN', hasTable: true, source: 'POS');

// Order-time
service.printOrderReceipt(order: order, cashierName: 'X');
service.printKdsTicket(order: order, cashierName: 'X');

// Payment-time
service.printPaymentDocuments(...);
service.kickCashDrawer();

// Pool
service.savePrinterPool(prefs, [NamedPrinter(...)]);
service.saveStationAssignments(prefs, {stationId: printerId});

// Update config
final next = service.config.copyWith(splitKdsByStation: true);
service.saveConfig(prefs, next);
```

---

If something in the source file differs from this map, **the source
file wins** — open `printing_service.dart` and follow the actual
implementation. This skill is the high-altitude index, not the spec.
