# POS work — frozen 2026-08-17

Paused to focus on shipping the KDS. The POS **compiles clean (0 analyzer
errors, 624 info/warning baseline)** and is safe to leave as-is, but one feature
is half-wired — see "Dangling" below before touching anything.

---

## Schema state

`schemaVersion` is now **32**. Four migrations were added this session, all
additive and nullable, so a device that upgrades mid-shift keeps every row valid:

| Version | Contents |
|---|---|
| 29 | `refunds` + `refund_lines` + `product_units` tables; `orders.externalOrderId / deliveryStatus / courierName / courierPhone / readySignalAt`; `order_products.serverId / saleUomId / manualDiscountReason`; `order_product_components.name` |
| 30 | `orders.discountReason` |
| 31 | `cash_movements` table |
| 32 | `products.isAvailable` (local "86" flag) |

**A device that has run these cannot roll back to an earlier build.**

---

## Done and verified (analyzer-clean)

### Z mode / fiscal day
- `ZDayState` + `z_day_provider.dart` — business day and Z number in prefs, so
  the login gate can read them before any DB session exists.
- `zBusinessDay` / `zBusinessDayKey` in `database_providers.dart`; configurable
  `zDayStartHour`.
- Day close (`closeBusinessDay` in `z_actions.dart`), login lock with four
  fail-open guards, manager reopen from three places.
- `ZService.closeZ` now **merges** `details` instead of overwriting it — without
  this the Z number never reached the backend.
- Extra close-time tickets: `printOrdersList`, `printProductsSummary`.

### API contract catch-up
- Orders now send `date` (the server was stamping "now", so offline orders
  landed on the wrong business day).
- `clientRequestId` persisted per session — stops the email report being sent
  twice on a retry or re-close.
- Z `409` → `ZAlreadyOpenException` → adopt the server's open Z.
- `POST /orders/{code}/ready` wired to the KDS state rollup for delivery orders.
- Refunds end-to-end: `RefundService`, bulk push, refund dialog with a
  restock/write-off switch, real `refundsTotal` on the Z.
- Added `GET /pos/z`, `/pos/z/{code}`, `/pos/z/{code}/sessions`,
  `/pos/cash-sessions/{code}`.

### Sync rewrite
- `syncAllData` no longer wipes master data. It **upserts** (true
  `ON CONFLICT DO UPDATE`, not `INSERT OR REPLACE`) then **reconciles** — deletes
  only ids absent from the payload.
- Fixed as a side effect: KDS/kiosk registrations were being wiped on every full
  sync with nothing to restore them; `syncMenu` was duplicating
  product↔component rows on every call.
- `_releaseUniqueValue` handles the four secondary unique constraints
  (`users.username`, `commercials.cin`, `waiters.pin`,
  `customers.phone_normalized`) that a real upsert would otherwise abort on.

### Order note
- `orders.note` is now the kitchen note, editable from a toolbar button with
  presets, shown in the order panel and printed on the KDS ticket.
- The manual-discount dialog was **overwriting** it (its "reason for discount"
  field wrote to `note`); it now writes `orders.discountReason`.

### Table-occupancy bug
`server_service.dart` ~2157 tested `existing.status != 'COMPLETED'`. Orders are
born COMPLETED, so the guard never fired and two waiters could take the same
table. Now judged on product states (`PAID`/`CANCELED`) instead.

---

## Resumed — cash movements is now COMPLETE

Finished after the KDS work. All of it is live and reachable:

- `cash_movements` table (schema 31), `CashMovementService`,
  `cashMovementServiceProvider`.
- **Entry point**: top-bar overflow menu → "Cash movements", gated on
  `Permissions.sessionsEnd` (whoever may close a session and count the drawer is
  who explains what left it).
- `lib/presentation/widgets/cash_movement_dialog.dart` — record IN/OUT with a
  required reason, optional reference, plus the session's history and a running
  net, with delete.
- 15 l10n keys across en/ar/fr.
- **Expected cash now includes the net** in BOTH places, which was the whole
  point: `SessionSummary.expectedCashAtEnd` (screen) and the new
  `SessionSummaryReport.expectedCash` (paper). The printed Z used to recompute
  `startingBalance + paidByCash` inline — leaving that would have made the
  printed variance disagree with the figure the cashier had just confirmed.
- Paid-in / paid-out print as their own lines above expected cash, omitted when
  zero so a shop that never uses them sees an unchanged slip.

## Done since the freeze — tests

**POS: 29 passing** (`flutter test`). **KDS: 24 passing.**

- Deleted `posecrea/test/widget_test.dart` — it was a scratch shelf server, not
  a test, and merely loading it started a listener on port 8080.
- Deleted `kds/test/widget_test.dart` — Flutter counter-app template scaffolding
  looking for a `+` icon the KDS never had. It had been failing all along, which
  meant a genuine failure would have been invisible.
- `AppDatabase.forTesting(QueryExecutor)` added so tests run against
  `NativeDatabase.memory()`; production still uses the default constructor.
- `test/money_math_test.dart` — PaymentBreakdown bucketing (cancelled excluded,
  unpaid ignored, unknown method), `zBusinessDay` boundaries (start hour, month
  and year rollover, zero-padding), `expectedCashAtEnd` with and without
  movements.
- `test/sync_and_cash_test.dart` — proves an 86 survives an upsert AND that
  `INSERT OR REPLACE` would have destroyed it, reconcile-delete scoping,
  CashMovementService signs/scoping/validation, and that a fresh DB really has
  every table and ALTER-added column at schema 32.
- `kds/test/board_logic_test.dart` — `PAID → completed`, status derived from
  products not `order.status`, note blank-to-null, the paid-item filter
  (including identity preservation), and `Station.fromJson` null tolerance.

**A real bug fell out of this.** `TransactionType.fromString` fell back to
`cash` for an unrecognised payment method, so an unknown electronic method would
inflate `expectedCashAtEnd` and invent a drawer shortage. It now falls back to
`other`, which keeps the money in takings without claiming it is in the till.
Reachable in practice: the backend's refund contract already uses TRANSFER and
CHECK, neither of which is in this enum.

---

## Done since the freeze — debt cleanup

Analyzer issues: **624 → 173**, zero errors, 29 tests passing throughout.

### l10n duplicates removed (313 fewer warnings)
280 duplicate entries — 221 with identical values, **59 with differing values**
where a later duplicate silently won. Deduped by keeping the **last** occurrence,
which preserves today's rendered text exactly, then **proved** it: parsed both
versions the way Dart resolves them and diffed — `en/ar/fr` all show
`lost=0 gained=0 value-changed=0`.

Worth a look when you have a moment: a few of the 59 were semantically different,
not just casing — `enter_password` was both *"Enter a password"* and *"Enter
tenant password to continue:"*; `settings_reset` was *"...to defaults"* vs
*"...successfully"*; `hold_order` was *"Hold Order"* vs *"Hold"*. The surviving
value is whatever was already being shown, so nothing changed on screen, but the
loser may have been the one someone actually intended.

### print() eliminated (162 sites, now zero)
Split by intent rather than swept uniformly:
- **37 → `Logger.instance.error`**, **21 → `Logger.instance.warning`** (the `❌`
  and `⚠️` sites) — real failures, now persisted by loggecrea's rotating file
  handler so a technician can read them off a shop floor.
- **104 → `posLog`** (`lib/utils/pos_log.dart`) — tracing, compiled out of
  release via `kDebugMode`. Deliberately NOT routed into `Logger.instance`:
  the LAN server logs every request and the sync logs every poll, so persisting
  that chatter would churn the 10 MB rotation and bury the real diagnostics.
- **Deleted** a leftover `print` in `ApiService.fetchUsers` that dumped the whole
  users payload — **bcrypt password hashes included** — to the console on every
  sync.

### zMaxHours now does something
It had been editable in Settings since Z tracking shipped while nothing read it,
so a Z left open over a weekend silently merged several days of takings into one
report. Login now warns when the open Z exceeds the limit. A **warning, not a
block**: refusing the login would strand the till, and only a human can decide
whether to close the old shift. Surfaced on the main screen after navigation so
it isn't lost with the login route.

---

## Not started

- UOM: `units[]` and `saleUomId` are plumbed end-to-end but there is no unit
  picker, so every line still sells in the base unit.
- **Real stock quantities.** Not possible today: `/pos/products` carries no stock
  field, so the POS cannot know a count. Needs a backend change first. The 86
  flag below is the half that was achievable.

---

## Done since the freeze — 86 / mark unavailable

- `products.isAvailable` (schema 32), **local-owned** and deliberately separate
  from `isActive`: that is the catalogue saying the product exists, this is the
  kitchen saying it has none right now.
- **A catalogue sync cannot clear it** — verified: `_persistProducts` never
  writes the column, and the sync upserts rather than replaces, so an omitted
  column keeps its local value. This is a direct payoff of the earlier
  `INSERT OR REPLACE` → `ON CONFLICT DO UPDATE` rewrite; under the old wipe-and-
  refill it would have been reset on every sync.
- Grid: greyscale + dimmed + a red **OUT OF STOCK** bar. The label is there
  because greyscale alone is ambiguous against a product whose own colour is
  grey, and says nothing to a colour-blind user.
- Tapping an 86'd item is **blocked**, not just discouraged, so a fast double-tap
  can't sneak it into the cart. Long-press on an 86'd item offers to restore it;
  right-click / secondary-tap is the toggle gesture.
- Gated on `Permissions.productsModify` — taking an item off the menu changes
  what the whole floor can sell.
- Exposed over the LAN as `isAvailable` on `GET /waiters/products`, so the waiter
  app and kiosks can grey it out. Sent rather than filtered — omitting it would
  look like the product had been deleted.
- 8 l10n keys across en/ar/fr.

---

## Verification not yet done

Everything above was checked with `flutter analyze` only. Nothing has been run
against a live POS. Before shipping the POS specifically, exercise: a refund
(check the restock flag reaches the server), an offline order synced the next day
(its server date should be the ring-up time), a delivery order reaching READY,
and a discount applied to an order that has a kitchen note (the note must
survive).

---

## Windows/Linux binary rename — step 1 of 2 done

The release binary is still called `posecrea.exe` (`windows/CMakeLists.txt`:
`project(posecrea)` + `set(BINARY_NAME "posecrea")`; Linux has the same pair).
The version info in `windows/runner/Runner.rc` already reads correctly —
`ProductName`/`FileDescription` are `CAISSE212` — so Task Manager and the file's
Details tab show the right name today. Only the filename on disk is stale.

**Renaming it cannot be done in a single release.** The in-app updater copies
with `robocopy` (no `/PURGE`) on Windows and `rsync`/`cp` (no `--delete`) on
Linux — both additive. A renamed build would therefore ADD the new binary and
LEAVE the old one, then relaunch the old path (`Platform.resolvedExecutable`),
pairing a stale binary with freshly copied `data/flutter_assets`: a snapshot
mismatch that does not boot. Every already-deployed terminal would break on the
update that carried the rename.

**Step 1 (done, in this release):** `update_service.dart` now reads the exe name
out of the extracted update *before* copying, and after a successful copy
relaunches that binary, deleting the superseded one so a stale desktop shortcut
fails outright instead of launching a mismatched app. Both platforms; rollback
paths deliberately still relaunch the original. Every adoption is gated on the
new build shipping exactly one candidate binary — anything ambiguous changes
nothing and keeps the old path. Verified by running the generated batch and sh
logic against real `robocopy`/`cp` updates: same-name, renamed, ambiguous, and
copy-failed all behave correctly.

**Step 2 (only after every terminal is on a build containing step 1):** flip
`BINARY_NAME` (and `project(...)`) in `windows/CMakeLists.txt` and
`linux/CMakeLists.txt`, and update `InternalName` / `OriginalFilename` in
`windows/runner/Runner.rc` to match. Nothing else references the exe name:
`build.ps1` uses only the `posecrea` *directory*, and the updater resolves the
binary at runtime.

Residual consequence of step 2, unavoidable: desktop shortcuts and any installer
pointing at `posecrea.exe` must be recreated. The updater deletes the old
binary, so those shortcuts break visibly rather than silently misbooting.

---

## New-order alert (chime + toast)

`sseNewOrderProvider` was being **set by the SSE handler and read by nobody** —
an online order could sit in the queue until someone happened to open the Orders
screen. Now `MainScreen` listens to it and does two things: plays a chime and
shows a toast carrying source, order code, item count and total, with a **View**
action that opens `OrdersManagementScreen(initialTabIndex: 1)` — straight to the
online queue rather than the local order list.

The listener sits on MainScreen, not on the external-orders tab, deliberately:
the point is to reach a cashier who is *not* looking at that tab. MainScreen
stays mounted under pushed routes, so the toast still surfaces through the root
ScaffoldMessenger while another screen is on top.

`assets/sounds/new_order.wav` is a generated two-note chime (B5 → E6, 0.6 s,
attack ramp + exponential decay so there is no click). It is a distinct asset
rather than a reuse of `button_tap.mp3` because the alert has to be
distinguishable from the click the cashier hears on every keypress. The
generator script is in the scratchpad; regenerate rather than hand-editing.

`SoundService.newOrderAlert()` throttles at **1200 ms** (UI clicks use 80 ms):
two orders in the same second is normal at peak, and stacked chimes read as a
malfunction rather than as two orders. It also `stop()`s before playing so a
chime already sounding restarts instead of being dropped as "already playing",
and it is deliberately not gated on `_isSupported` failing for the *click*
sounds — an operational alert should survive a UI-sound problem.

### Prerequisite: SSE is OFF by default

`AppSettings.sseEnabled` defaults to **false** and there is **no polling
fallback** for the queue. On a default terminal there is no SSE connection, so
no `new-order` events arrive at all — no chime, no toast, and the external tab
only shows what a manual refresh fetched. The switch is admin-only: Settings →
**SSE listener** (`settings_screen.dart:2283`). Everything above is dormant
until it is on.

### Filters and pagination were already implemented

Status chips (PENDING / CONFIRMED / ACKNOWLEDGED / CANCELLED), source chips
rendered from the server's own count map with live tallies, and the pager all
exist in `external_orders_tab.dart` and are wired to `browse()` with
`source`/`status`/`page`. The tab is rendered unconditionally at
`orders_management_screen.dart:314`. Nothing was missing here — a build predating
that work would explain not seeing it.

---

## Crash class: text fields with no on-screen keyboard mounted

`OnscreenKeyboardTextField` resolves the keyboard in **`initState`** via
`OnscreenKeyboard.of(context)`, and that method ends in `provider!.state`,
guarded only by an `assert`. With no `OnscreenKeyboard` ancestor it throws while
the widget is being inserted — an AssertionError in debug, a null-check
TypeError in release — which takes down the entire subtree, i.e. the dialog the
field lives in.

The ancestor is missing more often than it looks. `main.dart` applies
`OnscreenKeyboard.builder` **only when `showOnscreenKeyboard` is on**, and its
surrounding `try/catch` falls back to the bare child if the builder throws.
Either path leaves every dialog containing one of these fields as a hard crash.
The customer dialogs on the external-order confirm path are wall-to-wall such
fields, which is where it was reported.

**Fix:** `lib/presentation/widgets/adaptive_text_field.dart` —
`AdaptiveKeyboardTextField` probes for the ancestor and falls back to a plain
`TextField`. It probes rather than reading the setting, because the probe tests
the actual precondition and so stays correct when the tree and the setting
disagree — exactly what the builder's catch produces. All **51** call sites
across 22 files were switched; the package is now imported only by `main.dart`
(for the builder) and by the wrapper. Every forwarded parameter default was
checked against the package's own (`maxLines: 1`, `textAlign.start`,
`autofocus: false`, `obscureText: false`, `textCapitalization.none`,
`enabled: null`) so the 41 sites relying on defaults keep identical behaviour.

`test/adaptive_text_field_test.dart` pins both halves: the raw package widget
really does throw with no ancestor (that test is the bug, and will fail loudly
if a package upgrade ever fixes it — at which point the wrapper can go), and the
wrapper renders, accepts typing, and keeps pre-filled text and decoration.

**Not confirmed as the reported crash.** No stack trace was available, so this is
a proven crash class matching the symptom, not a verified diagnosis. If the
terminal has the on-screen keyboard switched **on**, the ancestor exists and this
was not the failure — the error text is needed.

---

## External orders moved to the confirm-order screen

The online queue was reachable from **two** places with **two different UIs**,
which is what made the filters look missing:

* `OrdersManagementScreen` tab 2 → `ExternalOrdersTab` — the new UI with status
  chips, per-source chips and a pager;
* `OrderConfirmationScreen` tab 2 → `_buildExternalTab` — an older master/detail
  list whose header was just "N pending" and a refresh button, **no filters, no
  pagination**. This is the one reachable from the main-page button, so it is the
  one actually in use.

Now there is one home. `OrdersManagementScreen` is a single view again (TabBar,
TabBarView, TabController, `SingleTickerProviderStateMixin` and the
`initialTabIndex` parameter all removed) and the queue lives only on the confirm
screen, next to the Confirm / Cancel / Confirm-and-pay actions that were already
there.

`external_orders_tab.dart` was **deleted**; its filter bar and pager were
extracted first into `lib/presentation/widgets/external_queue_controls.dart` as
public `ExternalQueueFilterBar` / `ExternalQueuePager` and wired into the confirm
screen's left column (filters above the list, pager below).

Four things that had to change with the move:

* **Selection is now derived** from the current page by id instead of stored as
  an object. With filters and paging, the selected item can leave the list under
  the cashier (filter change, page turn, another terminal confirming it) and the
  detail pane would otherwise offer Confirm on a row no longer there. Deriving
  also refreshes the pane's status after a reload.
* **The queue is pulled when the screen opens** (post-frame). Nothing did this
  before — the only loaders were the SSE `connected` event, which is off by
  default, and the refresh button. The tab opened empty.
* **The tab badge** uses the server's `totalElements` for the PENDING filter
  instead of `items.length`, which was one page (64 pending across 4 pages read
  "20"), and is hidden while browsing another status.
* **The empty state** is filter-aware — "No pending external orders" is a lie on
  the CANCELLED chip. 2 new l10n keys × 3 locales.

The new-order toast's **View** action now opens
`OrderConfirmationScreen(initialTab: 1)` instead of the removed tab.

---

## Product cost on order lines

`schemaVersion 33`: `products.cost` (nullable REAL). The API has always returned
`cost` on `/pos/products` and the POS was discarding it.

Every order-product line in the sync payload now carries `cost` — the per-unit
figure, resolved in `buildProductsListForSync` (the one shared builder feeding
both single and bulk order payloads):

1. the variant's own `cost` when the line sold a variant (a large size can cost
   more to make than the base product; `product_variants.cost` already existed);
2. otherwise the product's `cost`;
3. otherwise the key is **omitted**, never sent as `0.0` — zero would read as
   "free to make", i.e. 100% margin, on any server-side report.

Costs are batch-loaded in two queries, not per line: a Z-close sync can push
hundreds of lines.

`test/order_line_cost_test.dart` (7 tests) pins all of it against real SQLite,
including per-unit-not-per-quantity, the variant-beats-product precedence, an
unknown cost staying absent, a line whose product no longer exists still syncing,
and cost surviving the order-discount rewrite pass. `buildProductsListForSync`
was made `@visibleForTesting` so the tests exercise production code rather than a
copy of it.

**Two caveats.**

* **`cost` is not in the documented `PosOrderProductRequest`.** Spring Boot
  disables `FAIL_ON_UNKNOWN_PROPERTIES` by default, so an extra key is ignored
  rather than a 400 — but until the backend adds the field, this is a no-op on
  the server side. Worth confirming against a real endpoint.
* ~~It is the cost at sync time, not a snapshot at sale time.~~ **Done** —
  see below.

---

## Cost is now snapshotted on the order line

`schemaVersion 34`: `order_products.cost` (nullable REAL). Each order now
permanently carries the cost the product had **when it was rung up**, instead of
the cost being looked up at sync time. A supplier price change no longer
retroactively rewrites the margin on orders already sold.

`lib/services/product_cost_resolver.dart` holds the rule once — variant cost
wins, then product cost, then null — because lines are created in eight places
and eight copies of that rule would drift into eight different margins depending
on where the order came from. It memoises per instance, since a basket usually
repeats the same few products and the catalogue cannot change mid-basket.

All **8** insert sites stamp it:

| Site | Path |
|---|---|
| POS cart → new order | `order_provider.dart` (2 sites) |
| Split a line at payment | `payment_screen.dart` |
| Online queue → local order | `external_order_queue_service.dart` |
| Line added server-side (web edit) | `data_sync_service.dart` delta insert |
| LAN kiosk / waiter order | `server_service.dart` (3 sites) |

The payload builder now reads `product.cost` first and only falls back to the
catalogue lookup when it is null — which is exactly the legacy case: rows already
sitting in the sync queue when the column was added. Without that fallback those
orders would have synced with no cost at all.

`0.0` is deliberately distinguishable from unknown: a promo giveaway has a real
cost of zero, and `product.cost ?? …` keeps it, while an absent cost stays
omitted from the payload rather than becoming a fake 100% margin.

`test/order_line_cost_test.dart` is now 14 tests, covering the snapshot beating
a changed catalogue cost, the variant snapshot, both legacy-fallback paths, the
zero-cost case, and the resolver itself (including that its memo does not confuse
a product key with a variant key).

---

## Serial-managed products (schema 35)

The rule: a product (or variant) flagged `isSerialTracked` cannot be sold
without naming the exact physical unit. The backend rejects the **whole order**
with a 400 on any serial mistake, so every guard below exists to stop the sale at
the till rather than fail at sync time, once the customer has left with the goods.

**Data.** New `serials` table (the unit-level stock cache, sold rows included —
a refund or reprint has to name the unit that left), `products.isSerialTracked`,
`product_variants.isSerialTracked`, `order_products.serialId`.

**API.** `fetchSerials({productId})` and `lookupSerial(number)`.

**Sync.** Serials are pulled with the catalogue in both paths (`syncAllData` and
`syncMenu`) and reconciled. Two deliberate asymmetries:

* the fetch is wrapped in its own try — a tenant selling nothing serialised, or
  an older server with no endpoint, must not fail the whole catalogue sync;
* reconcile only runs when the fetch returned rows. An empty list is ambiguous
  (missing endpoint vs. genuinely empty tenant) and wiping the cache on the
  ambiguous case would block every serial sale until the next good pull.

**Selling.** `SerialService` owns the rules in one place: tracked = product flag
OR variant flag, available units FIFO by id, and reserve/release. A tracked
product can no longer quick-add from the grid — checked *before* the variant
branch, since a tracked product without variants would otherwise fall through to
quick-add and build an order the server rejects. The dialog blocks save without a
unit and forces `quantity = 1`.

**The picker** (`serial_picker_panel.dart`) replaces the components panel, which
is free because a tracked unit carries no components. Touch-first: 64px rows, the
whole row is the target, selected state is a filled check plus a 2px border, and
the scan field takes focus on open so a hardware scanner needs no tap. Typing
narrows the same list, so scanning and searching are one mental model; a scan that
matches exactly one unit takes it on Enter and clears for the next. "No units in
stock" is a distinct message from "no match" — the first is a stock problem, the
second a search problem.

**Reservation.** A unit is flipped unavailable the moment it lands in the basket
and released when the line is removed or the order cleared (`OrderNotifier` took
an optional `Ref` for this). Server truth wins on the next pull, which is what
recovers a reservation orphaned by a crash — there is no local cleanup pass.

**Never merging.** `_findDuplicateItemIndex` now skips serial lines. Without it,
adding two iPhones would collapse into one line of quantity 2 and the order would
400 — the single highest-value guard here.

**400 recovery.** `DataSyncService.isSerialRejection` matches all six documented
serial failures (on message text — the backend gives no error code) and triggers
`refreshSerials()`, so the cashier's next pick is made against server truth
instead of retrying a doomed payload. Unrelated failures are deliberately
excluded, or every network blip would trigger a pointless re-pull.

Serials also survive a reload: `serialId` and its number are restored when a
saved order is re-opened (numbers batch-loaded in one query), and the basket line
shows the serial in monospace — the one detail the cashier checks against the box.

`test/serial_test.dart` — 17 tests: tracking precedence (including a tracked
variant of an untracked product), what the picker may offer, reserve/release plus
the server-pull override, scan normalisation, and the rejection matcher in both
directions.

### Verification status

`flutter analyze` 0 errors; `flutter test` 102 passed; `flutter build bundle`
succeeds (Dart + assets compile). The **Windows native build could not complete**:
a running `posecrea` instance holds the exe and DLLs. Nothing has been exercised
against a live server, and the picker has not been seen on screen.

---

## Design: squared shape scale, main page tokenised

The app was running two competing shape languages. `app_theme.dart` defined a
soft scale (`radiusSm 10 / Md 14 / Lg 20 / Xl 28`) and told screens to inherit
it — while **380 call sites hardcoded their own** `BorderRadius.circular(n)`
across 14 distinct values (151×8, 71×12, 43×10, 26×16, 23×20, 20×6, 18×4 …).
The main page alone spanned 3, 4, 6, 8, 12, 14, 16 and 20.

The scale is now **squared** — `radiusSm/Md/Lg/Xl` are all `0`. The four slots
were kept rather than collapsed to one constant: they carry the semantic level of
each surface, so re-tuning later is four numbers here instead of another sweep of
the widget tree, and the call sites stay self-documenting.

Public tokens `AppTheme.brSm/brMd/brLg/brXl` plus `brTopSm/brTopMd` (for a header
capping a panel) were added, and all **41** shape sites on the main page and its
widgets now use them — `main_screen` (3), `top_bar` (8), `product_grid` (2),
`order_panel` (15), `category_selector` (9), `category_grid` (4). Sites were
mapped by what the surface *is*, not by its old number, so the mapping still
makes sense if the scale is ever un-squared. Zero hardcoded radii remain in those
six files. The other ~340 sites elsewhere in the app are untouched.

### Remaining consistency findings (audited, NOT fixed)

* **164 hardcoded `Colors.*` on the main page**, against the project rule of
  reading colour from the scheme. Not all are wrong: `Colors.white` as
  `foregroundColor` on a saturated fill is correct in both themes. The genuinely
  theme-blind ones are the grey/black family — `Colors.grey[600]` as body text,
  `Colors.grey[300]` as a disabled background, `Colors.black54` — which will read
  low-contrast or too bright in dark mode. Fixing these needs semantic judgement
  (a green is "paid", an orange is "warning"), so it wants a status-colour
  extension on the theme rather than a blind swap.
* **16 distinct font sizes on the main page** (9, 10, 11, 12, **12.5**, 13, 14,
  15, 16, 18, 20, 22, 24, 32, 36). The 12.5 is the tell-tale of ad-hoc tweaking.
  A 5–6 step type scale in the theme would collapse these.
* **Elevation is already fine** — 3 uses total, the theme is flat by design.

---

## Refunds, second pass (desktop implementation guide)

The newer guide **contradicts the earlier refunds doc in two places**. Both were
resolved in favour of the newer one; both had already been built the old way.

**1. Serial units DO return to stock.** The earlier doc said a serial "stays
sold; the refund does not free it", so the restock toggle was locked OFF for
serial lines. The new guide says a serial line refunded in full with
`restock: true` returns the unit and flips it available again. Reversed: the
toggle is back for serial lines, defaulting ON, and the picker now prints the
**serial number** on the line — two identical phones on one order are different
physical units, and the cashier has to match the box in their hand.

**2. The bulk endpoint reports per record, not all-or-nothing.** The earlier doc
described one transaction where any bad record rolled back the batch. The new one
returns **200 with `created` / `skipped` / `failed[]`**, keyed by refund code.

That second change was the dangerous one: `syncRefunds` returned `void` and
treated any 200 as total success, so under the new contract a **rejected refund
would have been marked SYNCED and disappeared** — cash handed back, no server
record, nothing on screen. Now `RefundSyncResult` parses the body and outcomes
are applied per record:

* `created` **and** `skipped` → synced (skipped is the idempotent re-send working);
* `failed[]` → parked with the server's own message, **never auto-retried** —
  every rejection reason is deterministic;
* mentioned by neither → left pending, because assuming either way is how a
  refund goes missing;
* non-2xx → transport failure, nothing marked, whole batch retried.

Outcomes are matched by **code, never by position** — a reordered response would
otherwise mark the wrong refunds synced. A bare `{message, count}` body (older
server) still means "all accepted", so the previous behaviour is preserved.

### Also in this pass

* **Amount ceiling** (`0 <= amount <= derived + 0.01`) enforced client-side, so
  an over-amount is refused *before the drawer opens* rather than 400-ing at sync
  with the money already handed over. A lower amount is allowed — that is the
  override case.
* **Line ownership** — found by a test: the cap check loaded lines by id without
  checking they belonged to *this* order, so another order's line was accepted.
* **Guards**: refund blocked on an unsynced order (no server line ids exist to
  point at) with a message saying to sync first; hidden entirely on a cancelled
  order (cancelling already reversed the sale).
* **Already-refunded quantity** shown per line, so a partly-refunded line does
  not just look wrong.
* **Permission gates** — the four `pos:refunds:*` tokens, applied to the refund
  button (`create`) and the restock toggle (`waste`, forced ON and disabled
  without it). `hasRefundPermission` is deliberately lenient: a role seeded
  before V148 holds none of these, and strict enforcement would disable refunds
  for the whole floor on upgrade. If a user carries **no** refund token at all,
  previous behaviour stands; once **any** is present the set is live.

23 new tests (`refund_sync_result_test.dart`, `refund_rules_test.dart`).

### Not done from this guide

* **Amount override UI** — the amount is derived and read-only for everyone. The
  `pos:refunds:amount:override` token is defined and tested but has no field to
  unlock yet.
* **Refund slip printing** (§8) and the **pending-sync ERROR bucket** screen
  (§8) — `parkedRefunds()` exposes the data, but nothing renders it.

---

## Refund slip printing

`PrintingService.printRefundSlip` — its own ticket with its own cut, since a
refund slip is handed to the customer rather than stapled to a sales receipt.

Layout follows the guide: header, the **refund code printed large and first**
(it is the reference support asks the customer for, and nobody should have to
hunt for it), original order code, method, cashier, timestamp, then the lines
with quantity and amount, the total, and the header reason. Serial-tracked lines
print their **serial number** — a serialised slip is proof for *that unit*, not
for the model. A waste line says "not returned to stock" out loud, so a later
stock query surprises nobody (dropped on 58mm paper, where the width does not
allow it).

`RefundService.slipFor` assembles it from **stored rows only** — product names,
serial numbers and the cashier resolved by id — so a reprint days later produces
identical paper even as the catalogue changes underneath. A product deleted by
catalogue reconciliation still prints a line (falling back to its id) rather than
a blank one. Printing happens **before** the sync push and swallows its own
failures: the customer is waiting, and a dead printer must not undo a refund that
is already recorded.

Method prints as the raw code (`CASH`, `CARD`…) exactly as the dialog shows it,
rather than inventing twelve translated variants for what the cashier just
selected.

### The bug this uncovered — schema 37

The slip printed **`1 x 0.00`** on every line under a correct total.

`RefundLineDraft.amount` is deliberately null for a derived amount, because the
contract prefers `amount` **omitted** on the wire so the server derives it from
its own copy of the line. That null was stored verbatim, and the slip is printed
locally from that row.

Storing our derived figure and sending it would have been the wrong fix: the
server checks `amount <= derived + 0.01`, and our per-unit arithmetic does not
account for an order-level `discountPercentage` the way the server's line total
does — so a discounted order would 400 on the ceiling. Instead
`refund_lines.amount` is now always populated locally, and a new
`amount_overridden` flag records whether the figure was **typed or derived**.
Only a typed one goes on the wire; a derived one stays local for the slip. This
also gives the not-yet-built `pos:refunds:amount:override` UI the column it will
need.

`test/refund_slip_test.dart` — 10 tests: the code/order/total, name resolution,
serial on the line, the waste flag, cashier resolution, a deleted product still
printing, reprint stability, per-line amounts summing to the printed total, and
multi-line refunds.

### Still not built

* **Reprint from the order's refunds panel.** `slipFor` works from stored rows
  and reprint stability is tested, so this is a button away — but there is no
  refunds panel on the order detail yet to hang it on.
* **Amount override UI** and the **pending-sync ERROR bucket** screen.

---

## The three remaining refund screens

**Refunds panel on the order detail** (`order_refunds_panel.dart`). Refund state
lives nowhere else — the order stays COMPLETED and the ticket keeps its original
total — so without this panel a refunded order is indistinguishable from an
untouched one. It sits **first** in the details dialog for that reason. Each row
shows the code, amount, method, time, a **sync badge**, and a reprint button;
parked refunds are outlined in red with the server's message. Reads local rows
only, so it is accurate offline, which is exactly when someone asks "did that
refund go through?". Gated on `pos:refunds:view`.

**Reprint** rebuilds through `slipFor`, so a reprint days later is identical to
the original even if the catalogue changed underneath (already covered by the
reprint-stability test).

**Refused-refunds bucket in the sync inspector.** Parked refunds never
auto-retry — every rejection reason is deterministic — so this dialog is the only
place they surface, and a parked refund means money left the drawer with no
server record. Each row carries the server's message **verbatim**, a *Copy code*
action (support asks for the refund code, and reading 20 characters off a till
screen over the phone is how digits get transposed), and a manual retry that
clears the marker and pushes again. The list is height-capped so a terminal with
a dozen of them cannot push the dialog's buttons off screen.

**Amount override** in the refund dialog, gated on
`pos:refunds:amount:override`. Per-line field, derived figure shown as the hint
so leaving it blank visibly means "use this", and an edit icon marks a line whose
amount was typed — the guide's instruction that an override must never look like
a normal amount. Only a typed amount reaches `RefundLineDraft.amount`, which is
what sets `amount_overridden` and what puts it on the wire; the ceiling check
already refuses anything above the line's value before the drawer opens.

The running total was fixed at the same time: it summed derived figures only, so
a supervisor typing 50 against a 90 line saw **90** on the confirm screen while
50 was recorded and handed over.

Two duplicate l10n keys (`retry`, `synced`) were introduced and then removed
during this pass — the pre-existing entries were kept.

153 tests pass; analyzer clean.

---

## Delivery orders (Glovo / Kooul / DealUp / Web) — gap pass

Audited the delivery-orders contract against what was built. Already in place and
left alone: the paged queue browse + counts + filter chips, `hasUnmappedItems`
gating Confirm, 409-on-confirm treated as "another terminal won", `source` +
`externalOrderId` echoed on the order push, re-pull of `/pending` on connect,
and the new-order sound + toast.

### Three SSE events were silently dropped

`SseEventType` knew only `connected`, `new-order`, `order-state-changed`,
`pos-command`, `heartbeat`. Everything else fell to `unknown` and was discarded
— including **`order-cancelled`**. A platform cancelling an order therefore
reached the POS and was ignored: the ticket stayed on the board for a cashier to
work, and if it was already confirmed the kitchen kept cooking for a courier who
was never coming.

Added `order-cancelled`, `order-ready` and `order-delivery-status-changed`.
Cancellation removes the row and escalates by state: a PENDING one gets a toast,
an already-CONFIRMED one gets the alert sound and a **blocking dialog** telling
staff to stop preparing it. `test/sse_events_test.dart` now pins all eight
contract names, so the next one that is added cannot go unhandled unnoticed —
including that near-misses (`order_cancelled`, `ORDER-CANCELLED`) resolve to
`unknown` rather than to the wrong event.

### The connection could die silently

Reconnect existed, but only fired when the stream errored or closed. A proxy or a
sleeping NIC drops an SSE connection without closing the socket — the read never
completes, the POS looks connected forever, and every order lands unseen. Added a
**60 s liveness watchdog** (two missed 25 s heartbeats), reset by any frame and
armed on connect as well, so a stream that opens and then says nothing is caught
too.

### The subscription only lived while the till screen was open

`sseLifecycleProvider` was watched by `MainScreen`, so navigating to Settings or
Orders tore the connection down — and the server alerts the admin with
"0 terminals reached" whenever nobody is subscribed. Moved to `main.dart`, app
scope. It is still a no-op when SSE is disabled or nobody is logged in.

### Glovo cancellations were reported as successes

Glovo has no inbound cancel: the server logs the rejection and nothing reaches
the platform. The POS said "Order X rejected" anyway. Now the confirm dialog
warns **before** the tap, and afterwards a dialog says to phone Glovo support —
because the alternative is a courier arriving for an order everyone believes was
cancelled. Kooul and our own sources keep the plain success message.

### Marketplace fields were being thrown away

`QueueOrderPreview` carried none of the platform extras. Added
`externalOrderCode`, `pickUpCode`, `paymentMethod`, `currency`, `allergyInfo`,
`specialRequirements`, `cutleryRequested`, `estimatedPickupTime`, `deliveryFee`,
`estimatedTotalPrice`, `totalCustomerToPay`, `isPickedUpByCustomer`.

Three are surfaced hard, above everything else on the review pane, because they
change what staff physically do:

* **Allergy** — full-width red banner. Never merged into the general note.
* **`paymentMethod: CASH`** — green "collect cash on handover" banner with the
  amount. Missing it means handing food over unpaid, or charging twice.
* **`externalOrderCode` / `pickUpCode`** — monospace chips by the order code,
  because ours means nothing to a courier.

### Not built

* **The mapping screen** (`/api/integrations/products`, the `unmappedOnly=true`
  inbox, bulk upsert, Kooul auto-map). This is the largest remaining piece and a
  feature in its own right. Without it an unmapped Glovo menu is unworkable on
  day one, exactly as the contract warns.
* The **frozen-payload** caveat is not explained in the UI: mapping an item does
  not retro-fix tickets already queued, and the cashier is given no wording for
  that.
* `deliveryFee` / totals are modelled but not printed on the kitchen ticket.

---

## Courier code display + printing (Glovo / Kooul)

The code a delivery driver scans in their own app to collect the order.

**Data path.** `orders.external_order_code` (schema 39) — copied from the queue
preview at confirm, echoed on the order push next to `externalOrderId`, and read
back from the server's echo on the delta pull (falling back to what we already
hold, so an older server cannot wipe it). Stored on the ORDER rather than read
from the queue because queue rows are purged after 7 days and reprints have to
outlive that. `externalOrderId` remains a machine id and is never shown or
printed.

**On screen.** Monospace chips beside the platform chip, long-press to copy —
staff read this code to platform support on the phone, and re-typing it off a
screen is how digits get transposed. Gated on `sourceHasCourierCode`, so DealUp
and Web (our own channels, no courier) show nothing.

**Printing.** Per-printer group in Printer Settings: **Mode** (Same ticket /
Separate ticket / Off, default same) and **Symbology** (QR / Code128 / Text,
default QR). Both persist by enum index and clamp on read, so a config from a
newer build cannot crash an older one; an absent key falls back to the default
rather than to Off, which would silently disable the feature on every existing
terminal.

The block prints platform name big, the code as the largest text on the ticket,
then the symbol, then pickup code / customer / our own code small. On the main
ticket it goes **above the logo and the items** — the courier reads the top of
the ticket sticking out of the bag, and anything above the code is paper they
have to unfold.

Symbol details that matter: it encodes **exactly** the code — no URL, no prefix,
no JSON — and a test asserts that at byte level, because anything wrapped around
it makes the courier's scan useless. QR uses correction level **M** rather than
L: a bag-mounted ticket gets creased, and the redundancy is worth more than the
density. Size steps down on 58 mm paper to keep the quiet zone. Code128 prints
with `BarcodeText.none` since the human-readable line is already above it.

A missing code on a GLOVO/KOOUL order (should not happen) prints the block with
our own order code as text, no symbol, and logs a warning — better than an empty
box on the bag.

11 tests: source gating including case, the raw-value QR assertion, Code128
accepting real code shapes, and the config round-trip/clamp/default cases.

### Wired, and what is not

The print-options dialog (the normal print **and** the reprint path) reads the
courier identity from the order row and emits the block, plus the separate
ticket when that mode is set. The other three `printOrderReceipt` callers
(`main_screen`, and two in `server_service` for the LAN paths) were left
untouched — they do not currently have the order row to hand, and a
delivery-platform order is not created through them.

---

## Quick product creation at the till (`pos:catalog`)

Four fields — name, barcode, price, category — and nothing else. TVA, stock,
images and active flags are back-office decisions the server fills with its own
defaults; putting them on this dialog would turn a ten-second counter action
into a form nobody completes correctly under pressure.

**Why it cannot be a local insert that syncs later:** the server assigns the id,
stamps tenant/business from `X-POS-Name`, and enforces the **plan's product
cap**. A till that inserted locally would happily create products the
subscription does not allow and only discover it much later. Hence the offline
state disables the button with a hint rather than queueing.

**Persistence goes through the sync path, not a bespoke insert.**
`DataSyncService.persistServerProduct` / `persistServerCategory` call the very
same `_persistProducts` / `_persistCategories` the catalogue sync uses, because
the endpoint returns the product in the `GET /pos/products` shape. That is not a
convenience: a hand-rolled insert here would drift the moment a column is added
to the sync mapping, and the product would silently change under the cashier at
the next refresh. Requirement 4 ("same code path") is met literally.

**`created: false` is a success.** The barcode already existed and the server
returned the existing product. The cashier is holding an item they want to sell,
not a mistake to be told off for — so the product is added to the ticket exactly
as a new one would be, with an informational toast rather than an error.

**Errors keep their meaning.** `PosCatalogException` separates a **403** (role
lacks `pos:catalog` → hide the feature) from everything else, and a plan-limit
message is displayed **verbatim** — it names the cap and the plan, and
paraphrasing leaves the operator with nothing to act on. Tested with a real
plan-limit string.

**Two entry points, one behaviour.** "+ New product" on the product grid
(pre-filling the failed search as the name, since that is the moment the cashier
knows something is missing), and **scan-to-create**: an unknown barcode now
offers to create the product with the barcode pre-filled instead of a dead-end
"not found". Both add the result straight to the open ticket through one shared
helper, so the add-to-ticket behaviour cannot drift between them. Without the
token, the scan miss stays the plain warning it always was.

`categoryId` and `categoryName` are mutually exclusive per the contract; sending
both is refused client-side rather than round-tripped for a 400. An empty
`categoryName` alongside an id is explicitly *not* treated as a conflict — the
dialog passes `''` for the unused branch, and treating that as "both" would make
picking an existing category impossible.

11 tests. 211 passing overall; analyzer clean.

### Not verified

Nothing here has been exercised against the live endpoints: the response shape,
the 403 body, and the exact plan-limit message are all taken from the contract as
written. The acceptance list also includes "created product survives full
re-sync", which follows from reusing the sync writer but has not been observed.
