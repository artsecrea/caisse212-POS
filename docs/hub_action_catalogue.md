# Action catalogue for hub-ready interfaces

Branch `refactor/phase1-consolidate` at `8791018` (clean). Read-only investigation. All paths are relative to the repo root. A line number is the line of the declaration or call. "UI" means `lib/presentation/**`, `lib/utils/**` and `lib/main.dart`. "LAN" means `lib/services/server_service.dart`.

How the counts were made: public methods were extracted from the 30 relevant classes, then every `.method(` call site in `lib/**` (except `*.g.dart`) was grepped. Generic names (`delete`, `update`, `create`, `cancel`, `watch`, `call`, `load`) were checked by hand, because grep cannot tell them apart.

---

## 0. What this means for the interface design

1. **Today the cart lives in memory and is saved in bulk.** `OrderNotifier` (`lib/providers/order_provider.dart:72`, 29 methods) holds the cart. Adding, removing or editing a line and setting the customer, discount, persons, note or type all happen in RAM. Nothing is written until one of four buttons calls `saveOrder` or `updateOrder`: Print, Proceed, Pay (quick cash) or Pay (screen). On the till, then, "addLine" is not a database action. It becomes an action only when the cart is submitted. The waiter app is different: it works line by line (`add-products`, `DELETE …/products/<opId>`). **The interface needs both shapes:** `submitCart(cart)` for the till and `addLines` / `removeLine` for waiters. A Remote implementation can turn `submitCart` into a line delta keyed by `lineUid`.
2. **The LAN server is a second, independent writer.** `server_service.dart` makes **118** direct `database.select/update/into/delete` calls and only **8** repository or service calls (lines 28, 1875, 3207, 3208, 3345, 3347, 3957, 3966, 4322, 4347). It re-implements creating orders, adding lines, removing lines, cancelling, transferring and clearing tables on its own (see §4).
3. **The UI still orchestrates.** It fires **31** sync kicks from UI files (`autoSyncOrder`, `pushOrderTags`, `syncTicketsForOrder`, `syncSessionsBulk`, …), **14** print triggers that change state (`printKdsTicket` ×7 and `printPaymentDocuments` ×7, counted across UI, LAN and repository), **8** `incrementPrintCount` calls, **19** activity-log calls and **10** notification calls. The interface must absorb all of these.
4. **Some services are built directly, bypassing providers.** `SessionService(db)` is constructed in `lib/main.dart:536`, `lib/services/app_exit_service.dart:166` and `lib/services/pos_command_handler.dart:271,273,286,306`. A Remote swap through providers would not reach these.
5. **Drift types still leak into the UI in 2 places.** `TicketDraftSplitsCompanion.insert` is built at `lib/presentation/paymen_screen/payment_screen.dart:1019`. `TicketsCompanion(...)` is built at `lib/presentation/widgets/tickets_management_screen.dart:950`. Both must become DTOs.

Legend: **[ORCH]** means the UI (or LAN handler) calls several repository/service methods in sequence for one intent, so the interface method must absorb that sequence. **[DUP]** means the action is implemented twice (see §4).

---

## 1. Actions per domain

### A. Orders & lines: 18 actions

| # | Proposed action (Dart-ish) | What it does today (writes / side effects) | Implemented | Called by |
|---|---|---|---|---|
| A1 | `Future<SubmitResult> submitCart(CurrentOrder cart, {required int userId, required int sessionId, String? status, bool headerOnly = false})` → `{orderId, orderCode, CurrentOrder reloaded}` | **New order:** checks that a session is active (`order_provider.dart:806`), mints an order code (`:615`), takes the next `sessionOrderNo` (`:916`) and the zDay, then inserts header, lines and options. Emits `OrderInsertedEvent` (`:987`), writes an audit entry (`:1000`), calls `notifyDiscounts` (`:1006`) and does a detached push (`:1018`). **Existing order:** re-homes a closed-session order, updates lines in place (`:1414`), inserts new lines (`:1521`) and records removed lines as cancellations (`keepCancelledLine` `:1544`, `_logRemovedItems` `:1730`, `recordRemovedItems` `:1856`). Prints a kitchen cancellation (`:1671`), claims the order (`:1676`), emits events (`:1679-1681`), writes audit and `notifyDiscounts` (`:1689-1695`), then queues or pushes (`_queueOrderUpdate` `:1881`). | `OrderRepository.saveOrder` `order_provider.dart:827`; `OrderRepository.updateOrder` `:1112` | **[ORCH ×4]** Each button runs the same sequence: if saved `updateOrder` else `saveOrder`, then `setTableOrderId`, `getOrderById` reload, `loadOrder`/`clearOrder` and prints. Print: `main_screen.dart:1750/1754/1762/1784`. Proceed: `:2113/2118/2126/2135/2142`. Pay (quick): `:2231/2236/2243/2248`. Pay (screen): `:2659/2663/2670/2677`. |
| A2 | `Future<void> assignWaiter(int orderId, int? waiterId)` | Header-only `updateOrder` (same chain as A1, no line writes) | `order_provider.dart:1112` (`headerOnly:true`) | **[ORCH]** `main_screen.dart:1613` `clearWaiter` + `:1621` `updateOrder`; `:1624` `setWaiter` + `:1635` `updateOrder` |
| A3 | `Future<void> cancelOrder(int orderId, {String? reason, required int userId})` | `updateOrderStatus('CANCELED')`. Reads what was sent to the kitchen (`:2542`), re-homes the order (`:2550`), writes status, reason and `isSynced=false`, calls `notifyOrderCancelled` (`:2631`) and flags the tickets cancelled (`:2656`). Detached sync with a queue fallback (`:2680`, `queueOrderUpdate` `:2714`). Emits an event, writes `logOrderUpdated` (`:2743`) and audit, then prints the kitchen cancellation (`:2770`). **The table is freed by the caller, not here.** | `OrderRepository.updateOrderStatus` `order_provider.dart:2517` | **[ORCH][DUP]** `main_screen.dart:2516` + `setTableOrderId(null)` `:2528` + `clearOrder` `:2530`; `order_panel.dart:182` + `freeTablesForOrder` `:188`; `orders_management_screen.dart:2335` + `autoSyncOrder` `:2345` (does not free the table); LAN `_waiterCancelOrder` `server_service.dart:4271` (own copy, see §4) |
| A4 | `Future<void> changeOrderStatus(int orderId, String status, {String? reason})` | Same as A3 for any status (back-office status picker) | `order_provider.dart:2517` | **[ORCH]** `orders_management_screen.dart:2335` + `autoSyncOrder` `:2345` |
| A5 | `Future<RemovePaidLineResult> removePaidLine({required int lineId, required int ticketId})` → `{ticketDeleted}` | Deletes the paid line and its options, rewrites the ticket amount from the remaining lines or deletes the ticket (one transaction), and queues the sync | `OrderRepository.deletePaidLine` `order_provider.dart:2078` | **[ORCH]** `order_panel.dart:439` + `getOrderById` `:452` + `loadOrder` `:454` |
| A6 | `Future<int> confirmExternalOrder(int queueItemId, {int? userId, int? overrideClientId})` | Confirms on the server (`api.confirmQueueItem`), upserts the customer (`external_order_queue_service.dart:243`), inserts the local order in a transaction (`_insertLocalOrder` `:206`, `nextSessionOrderNo` `:298`) | `ExternalOrderNotifier.confirm` `external_order_provider.dart:261` → `ExternalOrderQueueService.confirmAndSave` `external_order_queue_service.dart:139` | `order_confirmation_screen.dart:143`, `:306` (+ `getOrderById` `:320`) |
| A7 | `Future<int> rejectExternalOrder(int queueItemId, {int? userId})` | Cancels on the server, inserts a local CANCELED order (`isSynced=false`) | `external_order_provider.dart:308` → `cancelAndSave` `external_order_queue_service.dart:176` | `order_confirmation_screen.dart:251` |
| A8 | `Future<void> resetOrderNumber({String mode})` | Resets the `order_number_counters` row of the scope to 0 | `OrderRepository.resetOrderNumber` `order_provider.dart:609` → `AppDatabase.resetOrderNumber` `app_database.dart:1195` | `settings_screen.dart:1420` |
| A9 | `Future<void> reserveSerial(int serialId)` / `releaseSerials()` | Marks a stock serial as taken by the cart (shared stock state) | `SerialService.reserve` `serial_service.dart:82`, `releaseAll` `:88` | `product_grid.dart:1197`; `order_provider.dart:91` (cart clear) |
| A10 | `Future<void> acknowledgeSerialConflicts()` | Clears serial conflict flags | `serial_service.dart:131` | `serial_conflict_alert.dart:98` |
| A11 | `Future<void> claimOrder(int orderId)` (internal to payments, not UI-facing) | Sets `takenBy` and session to this cashier, `isSynced=false` (`:3006/3015`), `logOrderUpdated` (`:3025`) | `claimOrderForCurrentUser` `order_provider.dart:2971` | 6 UI calls: `main_screen.dart:2403`, `payment_screen.dart:3320,3554,3947`, `exchange_settle_dialog.dart:240`, `waiter_settlement_dialog.dart:206` |
| A12 | (LAN) `createOrder(WaiterOrderRequest, {requestId})` | Mints the code (`server_service.dart:2941`), inserts the order (`:3058`), takes `nextSessionOrderNo` (`:3070`), links the table (`:3095`), inserts lines (`_insertWaiterLine` `:3378`, inserts at `:3427/3446`), logs (`:3117`), auto-syncs (`:3145`) and fires prints (`_firePrintsForWaiterOrder` `:3199`) | `_waiterCreateOrder` `server_service.dart:2853` (route `:235`) | Waiter app `POST /waiters/orders` |
| A13 | (LAN) `addLines(String orderCode, List<LineRequest>, {requestId})` | Inserts the lines in a transaction (`:3649`), updates the order (`:3684`), logs (`:3712`) and fires KDS (`_fireKdsForWaiterAddedProduct` `:3288`) | `_waiterAddProductsToOrder` `server_service.dart:3609` (route `:241`) | Waiter `PUT …/add-products` |
| A14 | (LAN) `addLine(String orderCode, LineRequest)` | Same flow for a single line: transaction (`:4625`), order write (`:4633`), log (`:4653`) | `_waiterAddProductToOrder` `server_service.dart:4558` (route `:237`) | Waiter `PUT …/add-product` |
| A15 | (LAN) `removeLine(String orderCode, int lineId, {waiterId})` | Writes a tombstone (`:4197/4216`), notifies (`:4217`), deletes options and the line (`:4227/4230`), updates the order (`:4233`) and logs (`:4243`) | `_waiterRemoveProduct` `server_service.dart:4125` (route `:248`) | Waiter `DELETE …/products/<opId>` |
| A16 | (LAN) `createOrder(SocketOrderModel)` for KDS/kiosk | Finds the active session (`:986`), inserts the order (`:994`), takes `nextSessionOrderNo` (`:1008`), links the table (`:1019`), inserts lines (`:1054`) and options (`:1076`), logs (`:1092`) | `_createOrder` `server_service.dart:945` (route `:205`) | KDS/kiosk `POST /orders` |
| A17 | (LAN) `updateOrder(int orderId, SocketOrderModel)` | Full header rewrite from the device (`:1206`), log (`:1236`) | `_updateOrder` `server_service.dart:1113` body branch | KDS `PUT /orders/<id>` |
| A18 | `Future<void> printOrderTicket(int orderId)` (waiter "print") | Prints the order or kitchen ticket and stamps the printed quantities | `_waiterPrintOrder` `server_service.dart:3923` (`printKdsTicket` `:4008`) | Waiter `POST …/print` |

These cart edits stay **local, outside the interface**: they are in-memory until A1. `addItem` (6 calls: `main_screen.dart:267,367`, `order_panel.dart:353`, `product_grid.dart:233,1169,1172`), `addWeighedItem` (`main_screen.dart:458`), `removeItem` (2), `updateItemQuantity` (2), `updateItem` (4), `setTable` / `updateTable` (5), `setCustomer` / `clearCustomer` (3), `setCommercial` / `clearCommercial` (2), `setDiscountPercentage` / `setDiscountReason` (`main_screen.dart:1695-1696`), `setNote` (`order_panel.dart:587`), `setOrderType` (4), `setDeliveryAddress` / `setReference` / `setDeliveryFee` (`main_screen.dart:1193-1200`, `order_reference_dialog.dart:61`), `setNumberOfPersons` (`main_screen.dart:1378`), `setTip` (3), `loadOrder` (15) and `clearOrder` (14). The RAM hold stack (`order_panel.dart:212-216`, `held_orders_provider.dart:6`) is also local.

**Dead with a hub in mind:** `OrderRepository.holdOrder` (`order_provider.dart:1037`, 0 callers), `updateOrderProductState` (`:1948`, 0), `recordRemovedItems` (`:1856`, internal only), `getTablesWithOrders` / `getOrdersByTable` / `getPendingOrders` / `getAllOrdersWithDetails` / `getAllOrdersWithFullDetails` (0 each), `OrderNotifier.mergeItems` / `holdOrder` (0), and `TicketRepository.createTicket` / `markTicketAsPaid` / `getAllTickets` / `getTicketsWithDetails` / `getTicketsGroupedByOrder` (0). `deleteOrder` (`:3979`) is called only by the sync engine (`data_sync_service.dart:3504,3675`).

### B. Kitchen / KDS: 8 actions

| # | Proposed action | What it does | Implemented | Called by |
|---|---|---|---|---|
| B1 | `Future<KitchenRound> fireKitchenRound(int orderId, {KdsPrintMode? mode, Set<int>? paidLinesStillOwed})` → lines sent | Prints the kitchen delta and stamps `kdsPrintedQuantity` / `orderTicketPrintedQuantity` **on the shared order lines** (`printing_service.dart:5034-5046`, `:4960-4970`) | `PrintingService.printKdsTicket` (+ `_markItemsAsPrinted` `printing_service.dart:5034`) | **[ORCH]** `main_screen.dart:2556` `_firePostSavePrints` (`printKdsTicket` `:2591`), `main_screen.dart:2348` (pay quick), `print_options_dialog.dart:100`; LAN `server_service.dart:3260` (`_firePrintsForWaiterOrder`), `:3361` (`_printWaiterKdsNow` `:3339`), `:4008` |
| B2 | `Future<bool> setLineKitchenState(String lineUid /*today int lineId*/, KitchenState state, {String source})` | Write-once stage stamps (`:1316`). Rolls up the order: a terminal state writes status and auto-syncs (`:1356`, `:1363`), a micro-state touches `updatedAt` (`:1367`). Signals the waiter that food is ready, signals the delivery platform, logs (`:1372`). | `ServerService.applyKitchenLineState` `server_service.dart:1302` | POS kitchen board `kitchen_board_dialog.dart:429`; LAN `_updateOrderProduct` `server_service.dart:1273` (route `PUT /orders/products/<id>` `:207`) |
| B3 | `Future<void> setRush(int orderId, bool rush)` | Writes `priority` (`:1382`), log (`:1388`) | `ServerService.setOrderRush` `server_service.dart:1380` | `kitchen_board_dialog.dart:543` |
| B4 | `Future<void> setOrderKitchenStatus(int orderId, String status, {int? userId})` | Fast status path: confirms an ONHOLD order (createdBy/takenBy), writes status (`:1160`), syncs only on a terminal state (`:1165`), logs (`:1169`) | `_updateOrder` `server_service.dart:1113` (query `status=`) | KDS `PUT /orders/<id>?status=` (route `:206`) |
| B5 | internal: `printKitchenCancellation(orderId, lines)` | Prints a cancellation slip for cooked lines | `order_provider.dart:2890` | from `updateOrder` `:1671`, `updateOrderStatus` `:2770`, `deleteOrder` `:4110` |
| B6 | `Future<void> signalOrderReady(int orderId)` | Writes `readySignalAt` (`:4107`), tells the delivery platform | `_signalOrderReadyIfDelivery` `server_service.dart:4080`; `signalReadyProvider` `external_orders_live_provider.dart:153` | from B2 rollup; live external orders page |
| B7 | `Future<void> callWaiter(...)` / `ackWaiterCall(String callId)` | In-memory call registry + push to waiter app | `WaiterCallService.call` `waiter_call_service.dart:98`, `acknowledge` `:158` | `call_waiter_dialog.dart:69`; LAN `_waiterAckCall` `server_service.dart:1513` (`:1522`, route `:253`) |
| B8 | `Future<void> kdsNudge()` | No write: wakes KDS long-poll (`_kdsEventsTicket` `server_service.dart:823`) | transport only | KDS `POST /orders/events/ticket` |

### C. Tables / floor: 7 actions

| # | Proposed action | What it does | Implemented | Called by |
|---|---|---|---|---|
| C1 | internal to A1: `attachTable(orderId, tableId)` | Writes `area_tables.orderId` | `setTableOrderId` `order_provider.dart:2798` | **[ORCH]** always right after `saveOrder`: `main_screen.dart:1762,2126,2243,2670`; with `null` after cancel at `:2528` |
| C2 | `Future<void> transferOrder(int orderId, {required int fromTableId, required int toTableId})` | Transaction (`:3217`): refuses an occupied target, runs `clearTableOrder` + `setTableOrderId` (`:3238-3239`), writes `orders.tableId` and `isSynced=false`, logs (`:3252`), detached sync (`:3277`) | `transferOrderToTable` `order_provider.dart:3204` | **[ORCH][DUP]** `main_screen.dart:1452` + `notifier.updateTable` `:1455` + `invalidate(areaTablesProvider)`; LAN `_waiterTransferTable` `server_service.dart:4392` (own transaction `:4444-4463`, log `:4473`) |
| C3 | `Future<void> clearTable(int tableId)` (manual release) | `area_tables.orderId = null`. The UI first checks for unpaid lines itself (`getOrderByTable`). | `clearTableOrder` `order_provider.dart:2805` | **[ORCH][DUP]** `table_selection_dialog.dart:992` (`getOrderByTable`) → `:1077`; LAN `_waiterClearTable` `server_service.dart:4501` (direct write `:4534`, log `:4539`) |
| C4 | internal: `freeTablesForOrder(orderId)` | Frees every table pointing at the order | `order_provider.dart:2815` | `order_panel.dart:188`, `server_service.dart:4347`, inside `settleOrderAndFreeTable` (`:3111`) |
| C5 | `Future<int> reconcileFloor({required bool freeOnPayment})` | A repair that writes: frees tables whose order is settled or gone | `reconcileTableOccupancy` `order_provider.dart:3142` | `table_selection_dialog.dart:38`, `payment_screen.dart:3937`, `settle_unpaid_dialog.dart:352` |
| C6 | `Future<void> freeTablesForSession(int sessionId)` | Frees every table of the session's orders | `clearTablesForSession` `order_provider.dart:3193` | `close_session_dialog.dart:649` |
| C7 | `Future<CurrentOrder?> openTable(int tableId)` (read used as an action) | Loads the order occupying the table | `getOrderByTable` `order_provider.dart:1931` | `table_selection_dialog.dart:869`, `:992` |

### D. Payments, tickets & splits: 12 actions

| # | Proposed action | What it does | Implemented | Called by |
|---|---|---|---|---|
| D1 | `Future<PaymentResult> payOrderInCash(CurrentOrder cart, {required int userId, required int sessionId})` → `{orderId, ticketId, ticketNum, completed, PrintJob receipt, KitchenRound kitchen}` | Submits the cart (A1), reloads, computes the unpaid total less the order discount less earlier amount parts (`moneySplitParts` `order_provider.dart:698`). Creates a paid ticket and settles the lines in one transaction (`ticket_settlement_service.dart:69`). Prints KDS, receipt and drawer, `incrementPrintCount`. Claims the order (A11). `settleOrderAndFreeTable` (`order_provider.dart:3090`: transaction `:3095`, `updateOrderStatus(queueSync:false)` `:3109`, `freeTablesForOrder` `:3111`). Then `autoSyncOrder`. | spread over 7 classes | **[ORCH ×10 calls]** `main_screen.dart:2183` `_payDirectly`: `:2231/2236` save, `:2243` table, `:2248` reload, `:2267` `moneySplitParts`, `:2284` `getTicketsByOrderId`, `createPaidTicket` (`:2286`), `:2348` KDS print, `:2364` receipt, `:2390` `incrementPrintCount`, `:2403` claim, `:2405` settle, `:2413` `clearOrder`, `:2427` `autoSyncOrder` |
| D2 | `Future<PaymentResult> payTicket(int orderId, {required Map<int,double> claims /*lineId→qty, better lineUid*/, required String method, double? tendered, int ticketIndex, ...split})` | Mints the ticket number (`_mintTicketNum` `payment_screen.dart:3796`: online `api.fetchOrderSplit` + `TicketSettlementService.nextTicketNum` `ticket_settlement_service.dart:52`). `createPaidTicket(ClaimedQuantities)` with split details, claims the order, prints, `incrementPrintCount`, logs the payment. Then **check-and-complete:** `settleOrderAndFreeTable`, `reconcileTableOccupancy`, claim again, `clearDraftSplit`, `autoSyncOrder`. | `TicketSettlementService.createPaidTicket` `ticket_settlement_service.dart:69` + order repository | **[ORCH]** `payment_screen.dart:3224` `_processPayment`: claim `:3320`, print `:3389`, `:3433` `incrementPrintCount`, `:3441` log; `_checkAndCompleteOrder` `:3922` → `:3928`, `:3937`, `:3947`, `:3953`, `:3968` |
| D3 | `Future<PaymentResult> payAmountPart(int orderId, {required double amount, required SplitPlan plan, required String method, ...})` | Pays a split by amount: a ticket with `NoLines`, unless it is the closing part, which carries `ClaimedQuantities`. Claim, `getTicketById`, print, `incrementPrintCount`, log, `syncTicketsForOrder`. | same | **[ORCH]** `payment_screen.dart:3474` `_processMoneyPart`: claim `:3554`, `getTicketById` `:3557`, print `:3620`, `incrementPrintCount` `:3656`, log `:3663`, `_pushTicketsSoon` `:3694` (`:3699`) |
| D4 | `Future<List<PaymentResult>> payAllTickets(int orderId, List<TicketDraft>)` | Loops D2 | — | `payment_screen.dart:3884` |
| D5 | `Future<void> saveDraftSplit(int orderId, List<DraftTicketLines>)` / `clearDraftSplit(orderId)` | Replaces the `ticket_draft_splits` rows in one transaction | `TicketRepository.replaceDraftSplit` `ticket_provider.dart:428`, `clearDraftSplit` `:442` | `payment_screen.dart:1014` (Companion built in UI `:1019`); `:3953` |
| D6 | `Future<List<SettleResult>> settleOrdersAsCash(List<int> orderIds, {DateTime? zDay, int? sessionIdFor(order)})` | For each order: a cash ticket covering the remaining due, every unpaid line marked paid, status set to paid, table cleared (`settleOrderAsCash` `order_provider.dart:745`, `TicketSettlementService` `:765`, `updateOrderStatus` `:780`, `clearTableOrder` `:789`). Optional receipt. | `order_provider.dart:745` | **[ORCH]** `close_session_dialog.dart:281` + print `:299` + `incrementPrintCount` `:324`; `settle_unpaid_dialog.dart:298` + `getOrderById` `:313` + print `:314` + `reconcileTableOccupancy` `:352` |
| D7 | `Future<SettleResult> settleWaiter(int waiterId, List<int> orderIds, {method})` | For each order: `createPaidTicket`, claim, `settleOrderAndFreeTable`, `autoSyncOrder`. Then a settlement slip and `incrementPrintCount`. | — | **[ORCH]** `waiter_settlement_dialog.dart:184`, `:206`, `:207`, `:214`, print `:237`, `:266` |
| D8 | `Future<void> editTicket(int ticketId, {String? method, double? amount})` | Updates the ticket, `isSynced=false`, queues the update | `TicketRepository.updateTicket` `ticket_provider.dart:55` | `tickets_management_screen.dart:948` (`TicketsCompanion` built in UI `:950`) |
| D9 | `Future<void> deleteTicket(int ticketId)` | Refuses on a closed session, queues the delete, unlinks lines, deletes | `ticket_provider.dart:84` | `tickets_management_screen.dart:992` |
| D10 | `Future<void> recordReprint(int ticketId)` | `printCount++` | `incrementPrintCount` `ticket_provider.dart:556` | 8 calls: `main_screen.dart:2390`, `payment_screen.dart:3433,3656,4511`, `close_session_dialog.dart:324`, `tickets_management_screen.dart:834,1270`, `waiter_settlement_dialog.dart:266` |
| D11 | `Future<String> nextTicketNumber(int orderId)` (should become internal to D2/D3) | Highest ticket number of the order, locally and on the server, plus one | `ticket_settlement_service.dart:52` | `payment_screen.dart:3822` |
| D12 | internal: `settleOrderAndFreeTable(orderId, paidStatus, clearTable)` | See D1 | `order_provider.dart:3090` | `main_screen.dart:2405`, `payment_screen.dart:3928`, `exchange_settle_dialog.dart:237`, `waiter_settlement_dialog.dart:207` |

### E. Refunds & exchanges: 2 actions

| # | Proposed action | What it does | Implemented | Called by |
|---|---|---|---|---|
| E1 | `Future<RefundResult> refund(RefundRequest)` → `{refund, slip}` | Online pre-check: pushes an unsynced order (`refund_dialog.dart:905`), then `fetchOrderForRefund` / `fetchRefundsForRefund`. Writes the refund and its lines and mints a code (`_generateCode` `refund_service.dart:291`). Then `notifyRefund`, refund slip print, `syncRefundsBulk`. | `RefundService.createRefund` `refund_service.dart:411` | **[ORCH]** `refund_dialog.dart:306`, notify `:327`, `slipFor` `:341`, `printRefundSlip` `:342`, sync `:354` |
| E2 | `Future<ExchangeResult> settleExchange(ExchangeDraft, {required int newOrderId, ...})` | Transaction (`exchange_service.dart:56`): `createRefund` (`:59`), exchange tickets (`:61-86`) and line updates (`:90`). Then settle and free the table, claim, notify, `logPayment`, print, `syncSingleOrder` + `syncRefundsBulk`. | `ExchangeService.settle` `exchange_service.dart:36` | **[ORCH]** started from `main_screen.dart:2698` after A1; `exchange_settle_dialog.dart:212`, `:237`, `:240`, `:245`, `:252`, `:266`, `:314-315` |

### F. Cash sessions & cash movements: 8 actions

| # | Proposed action | What it does | Implemented | Called by |
|---|---|---|---|---|
| F1 | `Future<OpenSessionResult> openOrResumeSession({required int cashierId, required double float, required ZGate z, ...})` | **Resume branch:** `getActiveSession`, `resumeSession`, `getSessionById`, `logSessionResume`, `notifySessionPauseChange`. **New branch:** `checkOpenRules` (`session_service.dart:460`), `startSession` (`:258`, code `:298`, insert `:273`), `attachSession` (`z_service.dart:179`), reload, `syncSingleSession`, `logSessionStart`, outbox `POS_SESSION_OPENED`. | `SessionService` + `ZService` + sync + log | **[ORCH ×9 calls]** `login_screen.dart:686,691,693,695,698,713,720,732,733,742,744,747` |
| F2 | `Future<void> resumeSession(int sessionId)` | `resumeSession` + `notifySessionPauseChange` | `session_service.dart:405` | **[ORCH]** `login_screen.dart:691/698`, `session_details_screen.dart:96/98`, `update_resume_service.dart:89` |
| F3 | `Future<void> pauseSession(int sessionId)` | `pauseSession` + `notifySessionPauseChange` (+ sync before logout) | `session_service.dart:389` | **[ORCH][DUP ×4]** `top_bar.dart:705/706`, `top_bar.dart:771/772` (+ sync `:776-780`), `session_details_screen.dart:76/77`, `pos_command_handler.dart:289/290`; `main.dart:540` (commented out) |
| F4 | `Future<CloseSessionResult> closeSession(CloseSessionRequest{sessionId, countedCash, notes, closeZ, zClosedBy, freeTables, printX, documents})` | `endSession` (`session_service.dart:331`, which builds the session report `:357`), `logSessionEnd`, `clearTablesForSession`, unpaid summary, X print, an optional Z close + Z print, extra documents, `syncSessionsBulk` / `syncCashMovementsBulk` / `syncOrdersBulk` / `syncTicketsBulk` / `syncRefundsBulk`, email report, `notifySessionClosed` | `SessionService.endSession` + 8 others | **[ORCH ×15 steps][DUP]** `close_session_dialog.dart:626` (`endSession`), `:635` (log), `:649` (tables), `:668` (unpaid), `:671` (report), `:675/684` (X), `:741` (`closeZNow`), `:745` (Z print), `:783-790` (sync), `:796` (email), `:801` (notify); auto-close `main_screen.dart:535` + sync `:541-543`; remote `pos_command_handler.dart:273`, `:308`; Z close `z_service.dart:231` |
| F5 | `Future<void> deleteSession(int sessionId)` | Refuses a closed session, queues the delete, deletes | `session_service.dart:528` (queue `:545`) | `sessions_management_screen.dart:600` |
| F6 | `Future<CashMovement> recordCashMovement({direction, amount, reason, sessionId, zDay, createdBy})` | Inserts the movement and mints a code (`cash_movement_service.dart:40-47`) | `CashMovementService.record` `cash_movement_service.dart:19` | `cash_movement_dialog.dart:57` |
| F7 | `Future<void> deleteCashMovement(int id)` | Delete | `cash_movement_service.dart:70` | `cash_movement_dialog.dart:207` |
| F8 | `Future<void> closeAllSessions()` (remote command) | `endSession` for every active or paused session | `pos_command_handler.dart:299-315` | remote console |

### G. Z (business day): 6 actions

| # | Proposed action | What it does | Implemented | Called by |
|---|---|---|---|---|
| G1 | `Future<Z> ensureZForLogin({required User user, bool superAdmin})` | `refreshZConfig` (`z_actions.dart:62`), `_planZ` (`:93`, online server view), `_closeServerOrphans` (`:154`), `_applyPlanCloses` (`:210`, `markClosedByServer` `z_service.dart:272`), then continue or `openZ` (`z_service.dart:151`; seq planned in `z_rules.dart:142`) | `ensureZForSession` `z_actions.dart:225` | **[ORCH]** `login_screen.dart:1425` + `:1427` |
| G2 | `Future<Z> openZManually({required int userId, bool hasOverride})` | Same plan, then `openZ` | `z_actions.dart:270` | `login_screen.dart:1452`, `z_management_dialog.dart:76` |
| G3 | `Future<ZCloseResult> closeZ(int zId, {required String closeMode, int? endedBy, bool print = true})` | `zCloseBlock` rule check (`z_actions.dart:312`), then `closeZNow` (`:396`) → `ZService.closeZ` (`z_service.dart:223`: ends open sessions `:231`, transaction `:243`). Notifies auto-ended sessions (`z_actions.dart:415`, `:417`), `_pushSessions` (`:429`/`:433`). Then `printZReport` (`:443`). | `z_actions.dart` + `z_service.dart` | **[ORCH]** `close_session_dialog.dart:1179/1208` (block) → `:741` → `:745`; `z_management_dialog.dart:99` → `:129` → `:135` |
| G4 | `Future<bool> printZReport(int zId, {bool isX})` | Builds the report (`generateReport` `z_actions.dart:460`) and prints it | `z_actions.dart:443` | `close_session_dialog.dart:745`, `z_management_dialog.dart:62,135` |
| G5 | `Future<void> refreshZConfig()` | Pulls the Z rules | `z_actions.dart:62` | `login_screen.dart:1425`, `top_bar.dart:1021`, `z_management_dialog.dart:41` |
| G6 | internal to F1: `attachSessionToZ(sessionId, zId)` | Writes `cash_sessions.zId` and the open mode | `z_service.dart:179` | `login_screen.dart:732` |

### H. Customers: 1 action

| # | Proposed action | What it does | Implemented | Called by |
|---|---|---|---|---|
| H1 | `Future<int?> upsertCustomer({required String phone, String? firstName, String? lastName, String? address, bool fromServer = false})` | Deduplicates by normalised phone, updates only non-empty fields, otherwise inserts (`customer_repository.dart:126`, local rowid), `isSynced` flag | `CustomerRepository.upsertByPhone` `customer_repository.dart:82` | `customer_selection_dialog.dart:437`, `external_customer_review_dialog.dart:123`, `external_order_queue_service.dart:243` |

### I. Order tags: 1 action

| # | Proposed action | What it does | Implemented | Called by |
|---|---|---|---|---|
| I1 | `Future<void> setOrderTags(int orderId, List<int> tagIds)` | Writes `orders.tagIds` and `isSynced=false`, then the caller pushes | `OrderRepository.setOrderTags` `order_provider.dart:1966` + `DataSyncService.pushOrderTags` | **[ORCH ×2]** `main_screen.dart:1861` (cart) + `:1866` + `:1867`; `orders_management_screen.dart:1141` + `:1142` |

### J. Reservations: 6 actions (already online-only against BMS)

| # | Proposed action | Implemented | Called by |
|---|---|---|---|
| J1 | `create` / `update(reservation)` | `ReservationService.create` `reservation_service.dart:320`, `update` `:328` | `reservation_panel.dart:497` |
| J2 | `move(reservation, to)` / `moveItem(...)` | `:335`, `:354` | `agenda_conflicts.dart:342,347`, `agenda_screen.dart:1735,1741,1749,1766,1773,1781,1807,1809,1816`, `reservation_detail_sheet.dart:140` |
| J3 | `setStatus(reservation, status)` | `:375` | `agenda_conflicts.dart:318,323,376`, `reservation_detail_sheet.dart:79,83` |
| J4 | `addBlock` / `deleteBlock` | `:392`, `:409` | `reservation_panel.dart:473`, `agenda_screen.dart:1852` |
| J5 | `Future<CurrentOrder> ringUpReservation(String code)` | `refresh` `:283`, `localOrdersFor` `:524`, `buildCart` `:435`, `markArrivedQuietly` `:416` | **[ORCH]** `reservation_actions.dart:180`, `:192`, `:213`, `:218` (`loadOrder`), `:228` |
| J6 | `pullAgenda` / `loadDay` / `search` / `availability` (reads) | `:138`, `:205`, `:266`, `:301` | `reservation_providers.dart:140,98`, `agenda_screen.dart:2044`, `reservation_panel.dart:342,387` |

### K. Notes: 5 actions (local-only today, never synced)

| # | Proposed action | Implemented | Called by |
|---|---|---|---|
| K1 | `addNote({text, orderId?, color, pos})` | `NoteNotifier.addNote` `notes_provider.dart:39` | `note_edit_dialog.dart:242` |
| K2 | `updateNote(note)` | `:62` | `note_edit_dialog.dart:249` |
| K3 | `moveNote(id, x, y)` / `resizeNote` | `:78` / `:88` (0 callers) | `notes_screen.dart:107` |
| K4 | `deleteNote(id)` | `:98` | `notes_screen.dart:207` |
| K5 | `clearNotes()` | `:102` | `notes_screen.dart:232` |

### L. Devices, catalogue and printing (relevant to a hub): 7 actions

| # | Proposed action | Implemented | Called by | Hub? |
|---|---|---|---|---|
| L1 | `addDevice` / `updateDevice` / `deleteDevice` | `DeviceRepository` `device_providers.dart:210`, `:263`, `:303` | `devices_management_screen.dart:672`, `:684`, `:422` | LAN-scoped config: belongs to whoever serves KDS (the hub) |
| L2 | `addStation` | `device_providers.dart:317` | `devices_management_screen.dart:817` | same |
| L3 | `setProductAvailability(productId, bool)` (86 a product) | `CatalogueRepository` `catalogue_repository.dart:58` | `product_grid.dart:1271` | shared state: every till must see it |
| L4 | `createQuickProduct(...)` | `QuickProductService.create` `quick_product_service.dart:39` | `quick_product_dialog.dart:102` | catalogue write |
| L5 | `setDisplayName` / `updateLastLogin` | `UserRepository` `user_provider.dart:46`, `:56` | `profile_dialog.dart:63`, `login_screen.dart:663` | master data |
| L6 | sync admin: `markCompleted` / `clearAll` pending operations | `pending_operations_service.dart:304` | `orders_management_screen.dart:2456`, `sessions_management_screen.dart:848`, `tickets_management_screen.dart:281` | per-till plumbing |
| L7 | printing of reports (`printDailySummaryReport` ×6, `printOrdersList` ×3, `printOrderReceipt` ×5, `printWaiterSettlementSlip`, `printWaiterProfileSummary`) | `printing_service.dart` | close/session/report dialogs | per-till |

**Count of UI/LAN-triggered actions: A 18, B 8, C 7, D 12, E 2, F 8, G 6, H 1, I 1, J 6, K 5, L 7, for a total of 81.** Of these, 31 are marked [ORCH] and 9 are marked [DUP].

---

## 2. Authoritative reads (must answer the same on every till sharing a hub)

| # | Proposed read | Implemented | Called by |
|---|---|---|---|
| R1 | `Future<CurrentOrder?> order(int id)` / `orderByCode(String)` / `orderByTable(int)` | `getOrderById` `order_provider.dart:1978` → `loadOrderDetails` `:2174`; `getOrderByCode` `:2164`; `getOrderByTable` `:1931` | `getOrderById`: 17 calls (`main_screen.dart:617,1784,1811,2142,2248,2677,2709,2749`, `order_confirmation_screen.dart:320`, `kitchen_board_dialog.dart:63`, `orders_management_screen.dart:2120,2132`, `order_panel.dart:252,452`, `settle_unpaid_dialog.dart:313`, `server_service.dart:3209,3348`). `getOrderByCode`: `main_screen.dart:171`, `server_service.dart:3967`. `getOrderByTable`: `table_selection_dialog.dart:869,992`. `loadOrderDetails`: `held_orders_dialog.dart:87` |
| R2 | `Future<List<Order>> unpaidOrders({filter, page})` (resume panel) | `getUnpaidOrdersForResume` `order_provider.dart:3565` (SQL `unpaidOrderSql`) | `unpaid_orders_dialog.dart:123` |
| R3 | `Future<Map<int,double>> orderTotals(List<int>)` / `orderContentSummaries` | `getOrderTotals` `order_provider.dart:3701`; `getOrderContentSummaries` `:3655` | `unpaid_orders_dialog.dart:149,153`; `database_providers.dart:958` (`waiterStatsProvider`); `server_service.dart:4323` |
| R4 | `Future<PaginatedOrders> ordersPage(OrderQuery)` | `getPaginatedOrdersWithFullDetails` `order_provider.dart:3332` | `orders_management_screen.dart:216`, `close_session_dialog.dart:376`, `waiter_profile_dialog.dart:211`, `waiter_settlement_dialog.dart:77` |
| R5 | `Future<OrderFullDetails> orderFullDetails(int)` / `orderRow(int)` / `orderRowByCode` | `order_provider.dart:3971`, `:1990`, `:1997` | `orders_management_screen.dart:2107,145,2571`; `tickets_management_screen.dart:778,917,1207` |
| R6 | `Future<List<Order>> heldOrders()` (ONHOLD in DB) | `getHeldOrders` `order_provider.dart:2466` | `held_orders_dialog.dart:51` |
| R7 | `Future<List<Ticket>> openAmountParts(int orderId)` (split credit) | `moneySplitParts` `order_provider.dart:698` | `main_screen.dart:2267`, `payment_screen.dart:908`, `server_service.dart:1875`, `waiter_live_updates.dart:194` |
| R8 | `Future<List<DraftSplitRow>> draftSplit(int orderId)` | `draftSplitRows` `ticket_provider.dart:420`; `ticketDraftTicketCountProvider` `database_providers.dart:792` | `payment_screen.dart:980` |
| R9 | Order line identity and cancellations: `lineUidsForOrder`, `orderCancellationsProvider`, `savedOrderLinesProvider`, `orderPaymentPositionProvider` | `order_provider.dart:2006`; `order_cancellations_provider.dart:11`, `:29`; `order_provider.dart:4152` | `payment_screen.dart:920`; panels |
| R10 | Tickets: `ticketsOfOrder`, `ticket(id)`, `ticketsPage`, `filteredTickets`, plus figures (`discountTotalOf`, `deliveryFeeForTicket`, `tvaTotalOf`, `printItemsOf`, `linesOfTicket`, `paidTicketsForOrders`, `ticketsForOrders`) | `ticket_provider.dart:31,39,211,272,393,487,506,515,473,460,450` | `main_screen.dart:2284`; `payment_screen.dart:3557,4463`; `tickets_management_screen.dart:73,844,810-812,901-921,1232-1247`; `waiter_profile_dialog.dart:240`; `dashboard_screen.dart:102` |
| R11 | **Floor state:** `Stream<List<TableState>> floor()` | `areaTablesProvider` `database_providers.dart:637`; `unpaidTablesProvider` `:283` (via `UnpaidOrdersService`); `orderWaiterIdsProvider` `:648`; `FloorRepository.allTables` `floor_repository.dart:15` | `table_selection_dialog.dart`; `orders_management_screen.dart:721`; `unpaid_orders_dialog.dart:73`; LAN `_waiterTables` `server_service.dart:2476` |
| R12 | `unpaidOrders(scope)` / `unpaidSummary()` (Z or session close gate) | `UnpaidOrdersService.unpaidOrders` `unpaid_orders_service.dart:138`, `summary` `:251` | `settle_unpaid_dialog.dart:52`; `close_session_dialog.dart:668`, `report_documents.dart:357`, `session_reports_dialog.dart:168`, `database_providers.dart:299` |
| R13 | **Kitchen board / KDS feed:** `Stream<List<KitchenBoardOrder>> kitchenBoard(sessionId)`; `kdsFeed(sinceCursor)` | `KitchenBoardService.watch` `kitchen_board_service.dart:157`; LAN `_getOrders` `server_service.dart:502` (cursor `OrderLogService.getLastUpdateLogId` `order_log_service.dart:119` at `server_service.dart:587,773`; deltas `:748,749,764,765`); `kdsStreamTicketsProvider` `kds_live_service.dart:333` | `kitchen_board_dialog.dart:21`; KDS `GET /orders` (`:199`), `GET /orders/events` (`:202`) |
| R14 | `kdsStats(sessionId)` | `KdsStatsService.forSession` `kds_stats_service.dart:87` | `kds_stats_provider.dart:16` |
| R15 | **Sessions:** `activeSession(cashierId)`, `session(id)`, `sessions(ids)`, `sessionSummary(id)`, `sessionsPage` | `session_service.dart:428`, `:437`, `:446`, `:601`, `:642` | `getActiveSession`: 10 calls (`login_screen.dart:686,1417`, `top_bar.dart:435,557,766`, `session_details_screen.dart:41`, `main.dart:537`, `app_exit_service.dart:166`, `pos_command_handler.dart:271,287`). `getSessionById`: 9. `getSessionSummary`: `session_details_screen.dart:43`, `close_session_dialog.dart:517,1065`, `top_bar.dart:444`. `getSessionsPage`: `sessions_management_screen.dart:64` |
| R16 | **Z:** `openZ()`, `z(id)`, `recentZs`, `sessionsOfZ`, `openSessionsOfZ`, `zDayOptions`, `reportBlockedByOpenShift`, `zCloseBlock` | `z_service.dart:44`, `:60`, `:65`, `:199`, `:206`, `:88`, `:134`; `z_actions.dart:312`; `openZStreamProvider` `database_providers.dart:251` | `getOpenZ`: `top_bar.dart:567`, `z_management_dialog.dart:53`. `getById`: 12. `sessionsForZ`: 8 (`close_session_dialog.dart:466,490,709,759,1048`, `z_management_dialog.dart:115`, …). `zDayOptions`: `settle_unpaid_dialog.dart:59`, `z_report_dialog.dart:37` |
| R17 | **X/Z figures and reports:** `zReport(zId|day)`, `sessionReport(id)`, `ordersList(scope)`, `productsSummary(scope)`, `staffSales`, `optionsSummary`, `dayScope`, `emailPayload` | `DailySummaryService.generateReport` `daily_summary_service.dart:529`, `generateSessionReport` `:851`, `generateOrdersList` `:991`, `generateProductsSummary` `:1097`, `generateStaffSales` `:1182`, `generateOptionsSummary` `:1322`, `dayScopeFor` `:1396`, `getSessionsInRange` `:518`, `sessionIdsForPeriod` `:1078`, `buildEmailReportPayload` `:1439`; inputs `CashMovementService.totalsForSessions` `cash_movement_service.dart:93`, `RefundService.totalForSession` `refund_service.dart:631`, `cashTotalForSession` `:747`, `breakdownForSessions` `:648` | `generateReport`: `daily_summary_dialog.dart:72`, `session_reports_dialog.dart:158`, `z_report_dialog.dart:147`, `pos_notifications.dart:267`, `z_actions.dart:460`. `generateSessionReport`: `close_session_dialog.dart:671`, `session_reports_dialog.dart:164`, `session_service.dart:357`. Others: `report_documents.dart:327,340,365,379`, `session_reports_dialog.dart:126,188,196,204`, `products_sold_report_dialog.dart:118-119`, `close_session_dialog.dart:1273` |
| R18 | Cash movements of a session | `CashMovementService.forSession` `cash_movement_service.dart:64` | `cash_movement_dialog.dart:158` |
| R19 | Refunds: `refundedQuantities(orderId)`, `refundsForOrder`, `localRefunds`, `policyContext`, `slipFor` | `refund_service.dart:390`, `:602`, `:611`, `:325`, `:670` | `refund_dialog.dart:118,128,341`; `order_refunds_panel.dart:45,60`; `refunds_screen.dart:66,70,116,130` (the refund itself already checks the cloud: `refund_dialog.dart:905-909`) |
| R20 | Waiter-app reads | LAN `_waiterDashboard` `server_service.dart:1924`, `_waiterOrders` `:2663`, `_waiterOrderDetail` `:3776`, `_waiterTables` `:2476` | waiter app |
| R21 | Dashboard / stats | `ordersCreatedBetween` `order_provider.dart:2028`, `linesForOrders` `:2049`, `componentsOfLines` `:2057`, `linesOfOrder` `:2041`; `waiterStatsProvider` `database_providers.dart:945` | `dashboard_screen.dart:86,127,132`; `refund_dialog.dart:136,138` |
| R22 | Notes (if notes become shared) | `notesStreamProvider` `notes_provider.dart:7`, `notesByOrderProvider` `:15`, `recentOrdersForNoteLink` `order_provider.dart:2018` | `notes_screen.dart`, `note_edit_dialog.dart:280` |

**Total: 22 read groups.** Catalogue and master data (products, variants, components, categories, users, waiters, stations, tags list `orderTagsProvider` `database_providers.dart:512`) can stay local as a synced copy.

---

## 3. Per-till state, and counters/ids that collide

### 3a. Must stay local with a hub

| What | Where |
|---|---|
| Working cart (in memory) | `OrderNotifier` / `orderProvider` `order_provider.dart:72`, `:524` |
| RAM hold stack | `heldOrdersProvider` `held_orders_provider.dart:6`; `order_panel.dart:212-235` |
| Payment screen draft (in memory) | `ticketsProvider` `payment_screen.dart:630`, `selectedTicketProvider` `:636`, `calculatorProvider` |
| Current user and session on this till | `currentUserProvider` `database_providers.dart:393`, `currentSessionProvider` `:243`, `currentZProvider` `:247` |
| Printers: receipt + KDS config, ESC/POS queue, drawer | `PrintingService` `database_providers.dart:100`, `printing_service.dart`; `printers_management_screen.dart` |
| Customer display (2nd screen) | `customer_display_service.dart:697` |
| Barcode scanner, scale | `barcodeScannerServiceProvider` `database_providers.dart:112`; `scale_config_provider.dart`; `scale_barcode_service.dart` |
| Serial ports | `serial_job_queue.dart` |
| Sound | `sound_service.dart:5` |
| Settings (the till's `AppSettings`, SharedPrefs) | `settingsProvider` `settings_provider.dart:1306`. Some of these are **business rules that must move to the hub:** `paymentCompletesKitchen`, `paidOrderDefaultStatus`, `autoClearTableAfterPaying`, `orderNumberResetMode`, `defaultOrderStatus`, `unpaidPromptOnZClose`, `requireAdminToCloseUnbalanced`. Each till passes them in from the UI today (e.g. `main_screen.dart:2307`, `payment_screen.dart:3310,3550`, `order_provider.dart:919`). |
| Update / remote support / diagnostics / network watch | `update_service.dart`, `remote_support_service.dart`, `diagnostics_service.dart`, `network_watch_service.dart:446` |
| Sync queue (until the hub replaces it) | `pending_operations_service.dart`, `sync_job_service.dart`, `data_sync_service.dart` |
| KDS presence and the LAN server itself, if each till keeps one | `kdsPresenceProvider` `kds_live_service.dart:304`; `server_service.dart`; `discovery_service.dart:7` |

### 3b. Counters and ids that collide across tills

| Counter / id | Minted | Scope today | Collision with ≥2 tills on one hub |
|---|---|---|---|
| **`sessionOrderNo`** (#N) | `AppDatabase.nextSessionOrderNo` `app_database.dart:1171` (UPSERT on `order_number_counters`, table `order_number_counter_table.dart:8`); scope key `orderNumberScope(mode, session)` | per local DB, scope `session` / `z` / `manual` | **Yes.** Each till counts from 1 in its own scope. Called from 4 places: `order_provider.dart:916`, `server_service.dart:1008`, `:3070`, `external_order_queue_service.dart:298`. Reset at `app_database.dart:1195` / `settings_screen.dart:1420`. Must be minted by the hub. |
| **Ticket number** (`tickets.num`) | `TicketSettlementService.nextTicketNum` `ticket_settlement_service.dart:52` → `nextTicketNumber` `split_bill.dart:256`. Local max for the order plus server numbers fetched **only online** (`payment_screen.dart:3796-3822`, 2 s timeout). `createPaidTicket` mints locally when `num` is null (`_payDirectly`, waiter settlement, `settleOrderAsCash`). | per order | **Yes**, when two tills pay parts of the same order offline or in the same second. The comment at `payment_screen.dart:3806-3810` notes that reusing a number upserts over that ticket. Must be minted by the hub. |
| **Z sequence** (`zSeq`) | `planZ` `z_rules.dart:142` (max seq of `currentZDay`, `:152`) → `ZService.openZ` `z_service.dart:151` (insert `:160`) | per terminal: the key is `(terminal, zDay, zSeq)` | No collision while each till keeps its own Z. **If tills share a Z through the hub, the key changes**, and the "Z = per-terminal label" contract (memory: z-v2-contract) has to be revisited. |
| Order code | `generateOrderCode` `utils/order_code.dart:17`, uniqueness checked against **local** orders only (`OrderRepository.uniqueOrderCode` `order_provider.dart:615`); LAN `server_service.dart:2941` | random | Low probability, but not guaranteed unique across tills. The hub should mint it or check it. |
| Session code | `_uniqueSessionCode` `session_service.dart:298` (`CS-YYYYMMDD-<posId>-HHMMSS-XXX`, checked locally) | posId-prefixed | Safe while each till has a distinct posId |
| Refund code | `_generateCode` `refund_service.dart:291` (date/time + posName) | posName-prefixed | Safe while posNames differ |
| Cash movement code | `cash_movement_service.dart:40-46` (`CM-date-time-micros`) | timestamp | Very unlikely to collide |
| **Local autoincrement row ids** | `orders.id` `order_table.dart:4`, `order_products.id` `order_product_table.dart:6`, `tickets.id` `ticket_table.dart:5`, `refunds.id` `refund_table.dart:13,85`, `cash_movements.id` `cash_movement_table.dart:14`, `notes.id` `note_table.dart:5`; rowid for `cash_sessions.id` `cash_session_table.dart:4`, `zs.id` `z_table.dart:12`, and `customers.id` when created at the till (`customer_repository.dart:126`) | per DB | **Yes.** These are exposed in LAN URLs: `PUT /orders/<orderId>` (`server_service.dart:206`, parsed `:1114`), `PUT /orders/products/<id>` (`:207`, `:1265`), `DELETE /waiters/orders/<code>/products/<opId>` (`:248`, `:4132`). They are also used as keys in `ticket_draft_splits.orderProductId`, `SplitLine.localLineId`, `ClaimedQuantities` and the kitchen board. Interfaces should take `orderCode` and `lineUid` instead (`order_product_table.dart:87`, already minted per line; `serverId` at `:27`). |
| KDS change-log cursor | `OrderLogService.getLastUpdateLogId` `order_log_service.dart:119` (local `order_logs` id) | per DB | **Yes.** A KDS reading from two tills gets two different cursors. |
| `/waiters/tables/<tableId>/clear` | table ids come from the catalogue sync (`area_tables.id` is `integer()` with no autoincrement, `area_tables_table.dart:4`) | server id | OK |

---

## 4. Duplicated orchestration (the same business action implemented twice or more)

| # | Action | Copy 1 | Copy 2 (and more) | Difference that bites |
|---|---|---|---|---|
| D-1 | **Create order** | `OrderRepository.saveOrder` `order_provider.dart:827` | LAN waiter `_waiterCreateOrder` `server_service.dart:2853` (insert `:3058`, table `:3095`, lines `:3378`); LAN KDS/kiosk `_createOrder` `:945` (insert `:994`, table `:1019`, lines `:1054`); external `_insertLocalOrder` `external_order_queue_service.dart:206` | **4** implementations of header + lines + options + `sessionOrderNo` + zDay. Only the repository copy emits `OrderInsertedEvent`, writes audit and calls `notifyDiscounts`. |
| D-2 | **Add lines to a saved order** | `updateOrder` new-line branch `order_provider.dart:1521` (`writeComponents` `:1368`) | `_waiterAddProductsToOrder` `server_service.dart:3609` (`:3649`); `_waiterAddProductToOrder` `:4558` (`:4625`); `_insertWaiterLine` `:3378` | Pricing and options resolution are duplicated (`_priceWaiterOptions` `:3471`, `_loadOptionCatalog` `:3551`) |
| D-3 | **Remove a line** | `updateOrder` removal branch `order_provider.dart:1530-1620` (`keepCancelledLine` `:1544`, `_logRemovedItems` `:1730`, kitchen cancel `:1671`) | `_waiterRemoveProduct` `server_service.dart:4125` (tombstone + **hard delete** `:4197-4232`) | The repository keeps a cancelled line (cancelled lines v2); the LAN deletes it and sends no kitchen cancellation (known gap, memory: order-line-duplication) |
| D-4 | **Cancel order** | `updateOrderStatus('CANCELED')` `order_provider.dart:2517` + caller frees the table | `_waiterCancelOrder` `server_service.dart:4271` (direct writes `:4326`, `:4335`, `freeTablesForOrder` `:4347`, log `:4352`, notify `:4357`, auto-sync) | The LAN copy skips ticket flagging (`:2656`), the kitchen cancellation print (`:2770`), re-homing and the event. In the UI, 3 callers free the table 3 different ways: `main_screen.dart:2528` (`setTableOrderId(null)`), `order_panel.dart:188` (`freeTablesForOrder`), `orders_management_screen.dart:2335` (none) |
| D-5 | **Transfer table** | `transferOrderToTable` `order_provider.dart:3204` | `_waiterTransferTable` `server_service.dart:4392` (`:4444-4463`) | Two transactions with their own occupancy checks |
| D-6 | **Clear table** | `clearTableOrder` `order_provider.dart:2805` (UI checks unpaid lines at `table_selection_dialog.dart:992`) | `_waiterClearTable` `server_service.dart:4501` (`:4534`) | The unpaid check lives in each caller |
| D-7 | **Persist cart (save-or-update + attach table + reload)** | `main_screen.dart:1750-1784` (Print) | `:2113-2142` (Proceed), `:2231-2248` (Pay quick), `:2659-2677` (Pay screen) | 4 copies of the same 4 calls |
| D-8 | **Take payment + complete** | `main_screen.dart:2183` `_payDirectly` | `payment_screen.dart:3224` + `:3922` `_checkAndCompleteOrder`; `waiter_settlement_dialog.dart:184-266`; `exchange_settle_dialog.dart:212-315`; `OrderRepository.settleOrderAsCash` `order_provider.dart:745` (used by `close_session_dialog.dart:281`, `settle_unpaid_dialog.dart:298`) | 5 sequences of `createPaidTicket` → claim → `settleOrderAndFreeTable` → sync → print. Only the payment screen runs `reconcileTableOccupancy` and `clearDraftSplit`. Only `settleOrderAsCash` uses `clearTableOrder` instead of `freeTablesForOrder`. |
| D-9 | **Pause session** | `top_bar.dart:705-706` | `top_bar.dart:771-772`, `session_details_screen.dart:76-77`, `pos_command_handler.dart:289-290` | Each pairs `pauseSession` + `notifySessionPauseChange` by hand |
| D-10 | **Close session** | `close_session_dialog.dart:560-801` (15 steps) | `main_screen.dart:530-545` (`endSession` + 4 syncs, no log, no X, no table free); `pos_command_handler.dart:273` and `:306-310` (`endSession` only); `z_service.dart:231` (`autoClosed`) | The auto and remote paths skip `logSessionEnd`, `clearTablesForSession`, X print and the notification |
| D-11 | **Set tags** | `main_screen.dart:1866-1867` | `orders_management_screen.dart:1141-1142` | Same 2 calls |
| D-12 | **Order status from KDS vs POS** | `updateOrderStatus` `order_provider.dart:2517` | `_updateOrder` fast path `server_service.dart:1113-1170`; rollup in `applyKitchenLineState` `:1356` | The KDS writes `orders.status` directly, with no ticket flagging or event |

---

## 5. Proposed interfaces (8) and introduction order

Shared rules for all of them:
- **Ids:** inputs use `orderCode` and `lineUid` where possible. `int orderId` is tolerated in the Local implementation only.
- **Business settings:** passed by the service from a `BusinessRules` source, not by the UI.
- **Results:** each method returns a result DTO that includes **what the till must print** (`PrintPlan`). Printing stays per-till, and the Remote hub decides the kitchen delta.
- **Sync kicks** (`autoSyncOrder`, `push*`, `sync*Bulk`) and **logs/notifications** move inside the Local implementation. A Remote implementation drops them.

### 1. `OrderService`: 14 methods
`submitCart(cart, {userId, sessionId, headerOnly})` (A1, absorbs D-7) · `assignWaiter(orderId, waiterId?)` (A2) · `cancelOrder(orderId, {reason, userId})` (A3, absorbs the table free, fixes D-4) · `changeStatus(orderId, status, {reason})` (A4) · `removePaidLine(lineUid, ticketId)` (A5) · `setTags(orderId, tagIds)` (I1) · `confirmExternal(queueItemId, …)` (A6) · `rejectExternal(queueItemId, …)` (A7) · `resetOrderNumber(mode)` (A8) · `reserveSerial` / `releaseSerials` (A9) · LAN parity: `createOrder(request, {requestId})` (A12/A16) · `addLines(orderCode, lines, {requestId})` (A13/A14) · `removeLine(orderCode, lineUid)` (A15) · `printOrderTicket(orderCode)` (A18).
Reads, as `OrderQueries` with 9 methods: `order(id|code)`, `orderAtTable`, `unpaidOrders(filter)`, `orderTotals`, `contentSummaries`, `ordersPage(query)`, `fullDetails`, `heldOrders`, `openAmountParts` (R1-R7, R9).

### 2. `KitchenService`: 7 methods
`fireRound(orderId, {mode, paidLinesStillOwed}) → KitchenRound` (B1) · `setLineState(lineUid, state, {source})` (B2) · `setRush(orderId, bool)` (B3) · `setOrderKitchenStatus(orderId, status, {userId})` (B4) · `signalReady(orderId)` (B6) · `callWaiter(...)` / `ackWaiterCall(callId)` (B7) · reads `kitchenBoard(sessionId)` + `kdsFeed(cursor)` (R13, R14).

### 3. `FloorService`: 6 methods
`floor() → Stream<List<TableState>>` (R11) · `openTable(tableId) → CurrentOrder?` (C7) · `transfer(orderId, from, to)` (C2, absorbs D-5) · `clearTable(tableId)` (C3, with the unpaid check inside, absorbs D-6) · `reconcile()` (C5) · `freeTablesForSession(sessionId)` (C6). `attachTable` and `freeTablesForOrder` become internal to `OrderService` and `PaymentService`.

### 4. `PaymentService`: 11 methods
`payOrderInCash(cart, …)` (D1) · `payTicket(orderId, claims, method, {tendered})` (D2, includes ticket numbering + complete) · `payAmountPart(orderId, plan, amount, method)` (D3) · `payAll(orderId, drafts)` (D4) · `saveDraftSplit(orderId, drafts)` / `clearDraftSplit` (D5) · `settleOrdersAsCash(orderIds, …)` (D6) · `settleWaiter(waiterId, orderIds, method)` (D7) · `editTicket(ticketId, {method, amount})` (D8) · `deleteTicket(ticketId)` (D9) · `recordReprint(ticketId)` (D10).
Reads: `ticketsOfOrder`, `ticket(id)`, `ticketsPage`, `ticketFigures`, `draftSplit` (R8, R10). All of D-8 collapses into `settle(orderId)`, which is private and shared.

### 5. `ReturnsService` (refunds & exchanges): 2 writes + 4 reads
`refund(request) → RefundResult` (E1) · `settleExchange(draft, newOrderId, …)` (E2) · reads `refundedQuantities`, `refundsForOrder`, `localRefunds`, `policyContext` / `slip` (R19).

### 6. `CashSessionService`: 8 methods
`openOrResume({cashierId, float, …}) → OpenSessionResult` (F1, includes Z attach) · `resume(sessionId)` (F2) · `pause(sessionId)` (F3, absorbs D-9) · `close(CloseSessionRequest) → CloseSessionResult` (F4, includes the optional Z close, absorbs D-10 so the auto and remote paths get the same steps) · `closeAll()` (F8) · `delete(sessionId)` (F5) · `recordMovement(...)` (F6) · `deleteMovement(id)` (F7).
Reads: `active(cashierId)`, `session(id)`, `summary(id)`, `page(query)`, `movements(sessionId)` (R15, R18).

### 7. `DayService` (Z + X/Z figures): 5 writes + reports
`ensureForLogin(user)` (G1) · `openManually(userId, {override})` (G2) · `closeZ(zId, {mode, endedBy, print})` (G3, absorbs the `zCloseBlock` check) · `printZReport(zId, {isX})` (G4) · `refreshConfig()` (G5).
Reads: `openZ`, `z(id)`, `recentZs`, `sessionsOfZ`, `zDayOptions`, `closeBlock(zId)` (R16) and `ReportService`-style figures: `zReport`, `sessionReport`, `ordersList`, `productsSummary`, `staffSales`, `optionsSummary`, `unpaidSummary` (R12, R17).

### 8. `CustomerService` (+ notes): 1 + 5 methods
`upsertByPhone(...)` (H1), with the reads `search`, `byIds`, `findByPhone`, `watchAll`. `NotesService` (K1-K5) can join it or stay local until notes are meant to be shared. Reservations (J1-J6) **stay as `ReservationService`**: they are already online-only against BMS, so they need no hub interface.

**Method counts: OrderService 14 (+9 reads), KitchenService 7, FloorService 6, PaymentService 11 (+5 reads), ReturnsService 2 (+4 reads), CashSessionService 8 (+5 reads), DayService 5 (+13 reads), CustomerService 1 (+4 reads) + Notes 5.**

### Recommended order (lowest risk / highest hub value first)

1. **`FloorService`.** It is small (6 methods), and table occupancy is the first thing two tills fight over. It removes D-5 and D-6 by making the LAN handlers call it, and it is already well isolated in the repository (`order_provider.dart:2798-3292`). Its result type (`TableState`) is the seed of the hub's floor stream.
2. **`KitchenService`.** `applyKitchenLineState` and `setOrderRush` already have a single implementation (`server_service.dart:1302`, `:1380`), so wrapping them is almost free. It also moves kitchen logic out of `ServerService`, so the kitchen board stops importing the server. Add `fireRound` here as well, so printed-quantity stamps stop being written by `PrintingService` (`printing_service.dart:5034`).
3. **`OrderService` (writes), plus switching the LAN handlers onto it.** Start with `cancelOrder`, `setTags` and `assignWaiter`: small, with D-4 and D-11 as visible bugs. Then `submitCart`, which removes 4 copies in `main_screen.dart`. Then point `_waiterCreateOrder`, `add-products`, `_waiterRemoveProduct` and `_createOrder` at the same methods (D-1 to D-3). From this step on the hub has one writer. `sessionOrderNo` and order-code minting move behind this interface.
4. **`OrderQueries` + `PaymentService`.** This is the biggest UI orchestration (D-8: 5 copies) and it needs ticket-number minting behind the interface (§3b). Do it after OrderService, because `payOrderInCash` and the exchange path call `submitCart`.
5. **`CashSessionService` + `DayService`.** Close/open orchestration (D-9, D-10) and Z rules. This matters for the hub only once tills share a Z (a contract change, see §3b), so it comes later. It also removes the direct `SessionService(db)` constructions (`main.dart:536`, `app_exit_service.dart:166`, `pos_command_handler.dart:271-306`).
6. **`ReturnsService`.** Refunds already check the cloud. This mostly absorbs the dialog sequences (E1, E2).
7. **`CustomerService` / `NotesService`.** Low value and low risk. Do them last, or alongside step 3 for the customer upsert inside `confirmExternal`.

Step 0 for every interface: an abstract class, a `Local…` implementation that only delegates to today's code (no behaviour change), and a provider override point, so the Remote swap is one `ProviderScope` override. Tests can then pin the Local implementation before the call sites move.

---

## 6. As built (2026-11-27): the swap points

Every screen now reaches business data through one of these interfaces (`lib/domain/services`, plain Dart). Standalone, each provider builds the local implementation; a hub-linked till overrides the provider, and nothing else changes. `test/screens_use_service_interfaces_test.dart` fails if a screen reads the database, builds a local service, or reads a provider typed by a concrete class.

| Interface | Provider to override | Local implementation |
|---|---|---|
| **Actions** | | |
| `OrderService` | `orderServiceProvider` | `LocalOrderService` |
| `KitchenService` | `kitchenServiceProvider` | `LocalKitchenService` |
| `FloorService` | `floorServiceProvider` | `LocalFloorService` |
| `PaymentService` | `paymentServiceProvider` | `LocalPaymentService` |
| `CashSessionService` | `cashSessionServiceProvider` | `LocalCashSessionService` |
| `DayService` (Z) | `dayServiceProvider` | `LocalDayService` (runs `z_actions.dart`) |
| `ReturnsService` | `returnsServiceProvider` | `LocalReturnsService` |
| `CustomerService` | `customerServiceProvider` | `CustomerRepository` |
| `ReservationService` | `reservationServiceProvider` | `LocalReservationService` |
| `ExternalOrderService` | `externalOrderQueueServiceProvider` | `ExternalOrderQueueService` |
| `SerialService` | `serialServiceProvider` | `LocalSerialService` |
| `QuickProductService` | `quickProductServiceProvider` | `LocalQuickProductService` |
| `NotesService` | `notesServiceProvider` | `NotesRepository` |
| `DeviceService` | `deviceServiceProvider` | `DeviceRepository` |
| `UserService` | `userServiceProvider` | `UserRepository` |
| `CatalogueService` | `catalogueServiceProvider` | `CatalogueRepository` |
| `AuditLog` | `auditLogProvider` | `ActivityLogService` |
| `PendingOperations` | `pendingOperationsProvider` | `PendingOperationsService` |
| `SyncService` | `syncServiceProvider`, `syncServiceFactoryProvider` | `LocalSyncService` over `DataSyncService` |
| **Reads** | | |
| `OrderQueries` | `orderQueriesProvider` | `OrderRepository` |
| `TicketQueries` | `ticketQueriesProvider` | `TicketRepository` |
| `SessionQueries` | `sessionQueriesProvider` | `SessionService` |
| `ZQueries` | `zQueriesProvider` | `ZService` |
| `ReportQueries` (X/Z, session, products, staff) | `reportQueriesProvider` | `DailySummaryService` |
| `UnpaidQueries` | `unpaidQueriesProvider` | `UnpaidOrdersService` |
| `FloorQueries` (areas, tables, waiters) | `floorQueriesProvider` | `FloorRepository` |
| `KdsStatsQueries` | `kdsStatsServiceProvider` | `KdsStatsService` |

The reactive providers the screens watch (`areasProvider`, `categoriesProvider`, `productComponentsProvider`, `orderCancellationsProvider`, `unpaidTablesProvider`, `openZStreamProvider`, …) no longer query Drift: each calls a `watch…` method of one of these interfaces, so they follow the override.

**Still outside the interfaces**, deliberately or for a later step:
- **The LAN server** (`server_service.dart`) and its own order writes (waiter create/add/remove, kiosk create). Decided 2026-11-27: a till is either the LAN server (standalone) or a hub client, never both, so the server stays as it is and runs only in standalone mode. With a hub, waiter and kiosk orders reach the hub over HTTP through a service of their own, and the till sees them through `OrderQueries` like any other order. Hub mode must therefore not start the LAN server. Open point: who prints the kitchen ticket of a waiter order (today the LAN server does, when `print_waiter_paper` is on).
- **Account-level cloud calls from screens** (`apiServiceProvider`: sign-in, tokens, subscription, account status, tenant URL, demo mode, terminal names, issue reports, admin notices). They are the real backend's in every mode and stay direct. Till data from the cloud (another till's order, the business's refunds) goes through `OrderQueries` / `ReturnsService`; the guard fails on any other `ApiService` call from a screen.
- **Printing** reads the till's synced catalogue copy for option types (`printing_service.dart`). The printer is the till's own; it stays local.
- Services that build `SessionService` themselves inside the service layer (`pos_notifications.dart`, `update_resume_service.dart`, `refund_sandbox.dart`). They are behind the interfaces, not called from screens.
- **Contract tests** exist for the action interfaces (`test/contracts/`). The read interfaces are pinned by the repositories' own tests; a hub implementation needs contract tests of its own for them, or shared golden fixtures.
