# caisse212 hub: design notes (Go + PostgreSQL)

Status: **brainstorm, nothing built.** Written 2026-11-27 on branch `pos-hub-ready`, from the POS code as it stands (27 service interfaces, see `hub_action_catalogue.md` §6). Paths are relative to the POS repo.

---

## 1. Decisions already taken

| Date | Decision |
|---|---|
| 2026-11-25 | The hub is written in **Go**. The POS keeps working **standalone** (today's behaviour) when no hub is configured. |
| 2026-11-26 | **With a hub, the POS is only a front end.** It mints no ids or counters (order code, `#N`, ticket number, session code, Z sequence) and does not sync with the cloud. The hub does both. Only standalone mode generates and saves locally. |
| 2026-11-26 | **Failover:** a second hub URL in settings. When the first hub is down the till switches to the second; when both are down the till **queues its writes** until a hub answers. |
| 2026-11-27 | **A till is either the LAN server (standalone) or a hub client, never both.** `ServerService` stays as it is and runs only standalone. With a hub, the waiter app, kiosk and KDS talk to the hub. |
| 2026-11-27 | **Back-office data comes from the real backend** (users, waiters, catalogue, tenant, subscription). The POS never creates it. The hub mirrors it read-only; account-level calls (login, tokens, subscription) can stay direct. |
| 2026-11-27 | Storage: **PostgreSQL**. |
| 2026-11-27 | **The mode is set on the till**, in the Super admin screen (§2.1). Standalone stays the default. |
| 2026-11-27 | **HTTPS on the shop LAN** for everything the hub serves, with a private certificate authority per shop handed over at pairing (§2.2). |

---

## 2. Topology

```
                 ┌───────────────────────────┐
                 │  Cloud backend (BMS)      │  https://app.caisse212.com/api
                 │  source of back-office    │  + SSE /api/pos/queue/subscribe
                 │  data, reports, platforms │
                 └─────────────┬─────────────┘
                               │ HTTPS (outbox up, deltas + SSE down)
              ┌────────────────┴────────────────┐
              │ Hub A (primary)   Hub B (standby)│  Go + PostgreSQL, on the shop LAN
              │      └── replication ──┘         │
              └──┬────────┬─────────┬──────────┬─┘
     /hub/v1 API │        │ LAN-compat API     │ mDNS _caisse212-hub._tcp + _caisse212._tcp
     (all HTTPS) │        │                    │
            ┌────┴──┐ ┌───┴────┐ ┌────┴───┐ ┌──┴───┐
            │ Tills │ │ Waiter │ │  KDS   │ │Kiosk │
            │ (POS) │ │  app   │ │ screens│ │      │
            └───────┘ └────────┘ └────────┘ └──────┘
```

Modes of a till (one setting, `hubMode`):

| Mode | Data | LAN server | Cloud sync | Ids and counters |
|---|---|---|---|---|
| `standalone` (default, today) | local Drift DB | **on** | the till | the till |
| `hub` | the hub; **the till has no database**, only its settings and the queue of writes made while both hubs are down (§7) | **off** (must never start) | the hub | the hub (provisional ones while queued, §7) |

Switching mode is a provider override at boot: each of the 28 swap-point providers listed in `hub_action_catalogue.md` §6 gets a `Hub…` implementation. Nothing else in the app changes.

### 2.1 Setting a till up: standalone or hub

Decided 2026-11-27: the mode is set **on the till**, in the **Super admin** screen (`presentation/super_admin/`), on a new **Mode** tab. Not in Settings, and not from the back office for now.

- **Why there:** the Super admin screen is protected by the daily master code and opens from the logo on the tenant login screen, so a till can be set up at installation, before anyone signs in, and no cashier or shop admin can flip it by mistake. The mode decides where every sale is saved.
- **Android tills:** the logo taps open the Super admin screen on Windows and Linux only today (`super_admin_tap_target.dart`). A till running on Android needs the Mode tab reachable too, behind the same code; to add when the tab is built.
- **What it holds:**
  1. **Standalone / Hub.** Standalone is the default: every existing till stays as it is.
  2. **Hub address 1 and hub address 2** (failover, §9), with a **Find** button that browses the LAN for hubs. Hubs announce `_caisse212-hub._tcp`, a type of their own, so the search never lists tills (which announce `_caisse212._tcp`).
  3. **Pairing** (§5.9): the till shows a code, someone approves it on the hub, and the hub returns the till's device token and its certificate authority (§2.2). The fingerprint is shown on both screens so the person can check they match.
- **It replaces the LAN server switch:** today's `auto_start_server` setting only applies to standalone. In hub mode the LAN server never starts, whatever that setting says.
- **Switching is guarded,** because data must be in the right place first. A switch that fails a check is refused with the reason, never done halfway:
  - **standalone → hub:** no session open on the till, and nothing left to send to the cloud (pending queue at 0). Otherwise sales that exist only on this till would be stranded.
  - **hub → standalone:** the till's offline queue (§7) is empty, i.e. everything was handed to the hub. The till then does a full sync from the cloud, as on a fresh install.
- **Later:** the back office shows each till's mode, and may set it remotely (`set_config`). Kept on the till first: simpler, and a mistake cannot come from far away.

### 2.2 HTTPS on the shop LAN

Decided 2026-11-27: **everything the hub serves is HTTPS**: the till API (`/hub/v1`), the LAN-compatible API (§6) and the event streams. The hub opens no plain HTTP port. A standalone till's LAN server is not part of this: it stays as today (HTTP + `x-server-password`) until decided otherwise.

A public certificate authority cannot issue a certificate for a LAN address, so the hub brings its own:

1. **A private certificate authority per shop**, created by the hub at first start (key stays on the hub, valid 10 years). It issues the hub's **server certificate** (1 year, renewed automatically), naming the hub's LAN IPs, its mDNS name (`<hub-name>.local`) and `localhost`.
2. **The standby hub uses the same authority** (copied when the standby is set up, §9), with its own server certificate. One trust anchor covers both hubs, so failover needs nothing on the tills.
3. **Apps trust that authority only, and only for the hub.** It is handed over at pairing (§2.1). The till, the waiter app and the KDS app load it into their own HTTP client (Dio with a `SecurityContext` holding just that certificate), not into the system store. No install on the device, no warning, and nobody else's certificate is accepted for the hub.
4. **The hub's IP should not move.** The certificate names the IPs it was issued for. Give the hub a DHCP reservation or a fixed IP. If the IP changes anyway, the hub issues a new server certificate for it at start (same authority, so clients keep trusting it), and devices that found it by mDNS name are unaffected.
5. **Devices also authenticate:** HTTPS protects the link, the device token from pairing says who is calling. `x-server-password` stays on the LAN-compatible routes for the existing clients.

**Browsers are the exception.** A KDS board or kiosk running in a web browser cannot be given a private authority the way an app can. Two ways, to choose (§11):
- **A:** install the shop's authority on that device once (Windows certificate store, or Android's user certificates, which Chrome trusts). Works offline; one step per device.
- **B:** a public name per hub (for example `<hub-id>.lan.caisse212.com`) that resolves to its LAN IP, with a real certificate obtained through the cloud (Let's Encrypt, DNS challenge). No step on the devices, but it needs internet to issue and renew every 90 days, and some routers refuse DNS answers that point to a private IP (DNS rebinding protection).

---

## 3. What the hub owns

1. **The business data of the shop:** orders, lines and their options, cancellations, tickets and payments, draft splits, cash sessions and movements, Zs, refunds and exchanges, customers created at the counter, notes, order tags on orders, serial reservations, the floor (table occupancy), kitchen line states and timers.
2. **Every id and counter:** order code, per-scope order number `#N` (session / Z / manual), ticket number per order, session code, Z `(zDay, zSeq)`, refund code, line `lineUid`.
3. **Every rule and calculation** the POS runs today, done once: money (line amounts, options, discounts, VAT, delivery fee), option rules (`priceOptions`), refund policy, session-open rules, Z open/close rules, unpaid gate, table release, kitchen timing and late alerts.
4. **The cloud link:** the push of everything above (same endpoints as today, §8), the pulls of back-office data and deltas, the cloud SSE (platform orders, remote commands, account status).
5. **The LAN for the other devices:** the waiter app, kiosk and KDS use the hub exactly as they use a standalone till's LAN server today (§6), plus a push channel for them.
6. **Printing coordination** (open, §11): who prints a waiter order's kitchen ticket.

It does **not** own: the till's printers, cash drawer, scanner, scale, customer display, settings, updater, or the back-office data (read-only mirror).

---

## 4. PostgreSQL schema (outline)

All business tables carry `tenant_id`, `business_id`, `created_at`, `updated_at` (`timestamptz`, UTC), `version bigint` (optimistic concurrency) and `deleted_at` (a delete is a cancel, never a row removal: see "pull never subtracts", §8.3). Money is `numeric(12,3)`, never float.

**Mirror of the back office (read-only, refreshed from the cloud):**
`users`, `waiters`, `waiter_areas`, `areas`, `area_tables` (static part), `categories`, `products`, `product_variants`, `variant_attribute_values`, `components`, `component_groups`, `product_components`, `product_component_groups`, `stations`, `commercials`, `payment_methods`, `coupons`, `order_tags` (catalogue), `resources`, `product_resources`, `serials`, `integration_mappings`, `session_rules`, `refund_policy`, `business_day_config`, `terminals` (the tills known to the hub, with their cloud identity).

**Shop data (the hub is the writer):**

| Table | Key points |
|---|---|
| `orders` | the columns of today's `orders` table: `code` (hub-minted, unique), `status` (born `COMPLETED`, cloud-terminal), `type`, `priority` (rush), `persons`, `table_id`, `waiter_id`, `client_id`, `commercial_id`, `created_by`, `taken_by`, `session_id`, `session_order_no` (`#N`, hub-minted per scope), `z_day date`, `discount_percentage`, `discount_reason`, `tip`, `delivery_fee`, `amount_paid`, `balance_due`, `payment_status`, `source` / `source_id` / `external_order_id` / `external_order_code`, `delivery_status`, `courier_name` / `courier_phone`, `ready_signal_at`, `reference`, `reservation_code` (+ link status), `cancellation_reason`, `note`, `address`, `tag_ids`; plus `terminal_id` (the till that rang it up), `cloud_id`, `cloud_synced_at` |
| `order_lines` | today's `order_products`: `line_uid uuid unique` (hub-minted), `order_id`, `product_id`, `variant_id`, `quantity numeric`, `unitary_price` (TTC after catalogue discount), `unitary_tva` (an amount), `unitary_discount`, `manual_discount` (+ reason), `cost`, `state` (kitchen), `course_no`, `ticket_id` (paid = set), `canceled_quantity` / `canceled_at` / `canceled_by`, `kds_printed_at` / `kds_printed_quantity` / `order_ticket_printed_quantity`, `kitchen_at` / `preparing_at` / `ready_at` / `served_at`, `note`, `serial_id`, `sale_uom_id`, `z_day`, `server_id` (cloud line id) |
| `order_line_components` | options of a line, with `price`, `quantity`, `removal_charge` |
| `removed_order_items` | the cancellation record (who, when, reason, quantity, charged or not) |
| `tickets` | `num` per order (hub-minted), `date`, `amount`, `payment_method`, `is_paid`, `is_cancelled`, `session_id`, `z_day date`, `split_details jsonb`, `exchange_refund_code`, `print_count` |
| `ticket_draft_splits` | the payment screen's draft division (shared, so two tills see the same split) |
| `cash_sessions` | `code` (hub-minted `CS-YYYYMMDD-<terminal>-HHMMSS-XXX`), `cashier_id`, `terminal_id`, `status`, `money_at_start`, `counted_cash`, `paused_at`, `z_id` |
| `cash_movements` | IN/OUT, unsigned amount, reason, session |
| `zs` | `(terminal_id?, z_day date, z_seq int)` (see the open question in §11), open/close modes, override flags, totals snapshot |
| `refunds`, `refund_lines` | policy flags, approval, restock, exchange link |
| `customers` | one per normalised phone (`phone_normalized unique`) |
| `notes` | the sticky notes board |
| `serial_reservations` | which basket holds which unit |
| `activity_log` | the audit trail (who, what, when, terminal) |

**Infrastructure tables:**

| Table | Purpose |
|---|---|
| `counters (scope text, key text, value bigint)` | every counter, incremented in the same transaction as the row that uses it (`UPDATE … RETURNING`) |
| `request_log (request_id uuid pk, route, status, response jsonb, created_at)` | idempotency: a replayed write returns the stored answer (generalises today's waiter `requestId` replay) |
| `outbox (id, entity, entity_id, op, payload jsonb, attempts, next_at, dead_at, last_error)` | the cloud push queue (replaces each till's `pending_sync_operations`) |
| `sync_cursors (stream, cursor)` | cloud delta cursors (`/pos/sync/orders`, `/pos/sync/payments`) |
| `events (seq bigserial, topic, entity_id, payload jsonb, at)` | the change feed the hub pushes to clients and replays to a reconnecting client (`Last-Event-ID`), and the log the standby can use (§9) |
| `devices`, `device_sessions` | tills, KDS, kiosks, waiter tablets paired with the hub, their tokens and presence |

Migrations: versioned SQL files (`golang-migrate` or `goose`), run at hub start.

---

## 5. The till API (`/hub/v1`), one group per POS interface

Conventions:
- JSON over HTTPS on the LAN. Every request carries `Authorization: Bearer <device token>` and `X-Hub-Api: 1`. Writes also carry `X-Request-Id: <uuid>` (idempotency, §4 `request_log`).
- A write answers with the resulting resource, including the hub-minted ids and numbers, so the till never has to guess them.
- `watch…` methods = a snapshot `GET` plus the event stream `GET /hub/v1/events?topics=…` (SSE; `Last-Event-ID` resumes). Topics: `orders`, `order:<id>`, `tables`, `kitchen`, `tickets:<orderId>`, `drafts:<orderId>`, `sessions`, `z`, `unpaid`, `catalogue`, `customers`, `notes`, `devices`, `serials`, `sync`, `external_queue`, `reservations`, and `commands:<terminal>` (cloud commands relayed to one till, §8.4).
- Errors: `{ "error": "<code>", "message": "…", "details": {…} }`, with the codes the POS already handles (`table_occupied`, `option_not_offered`, `option_group_too_few`, `z_block_manual_open`, `session_rule_violation`, `refund_policy_…`, `account_locked` 423…).

### 5.1 Orders: `OrderService`, `OrderQueries`

| POS method | Endpoint |
|---|---|
| `submitCart(cart, userId, sessionId, headerOnly)` | `POST /orders` (new cart) · `PUT /orders/{id}` (saved cart; body = full cart, lines keyed by `lineUid`; removed lines become cancellations, §10.4) |
| `updateCart(cart, headerOnly)` | `PUT /orders/{id}?headerOnly=…` |
| `cancelOrder(id, reason, userId)` | `POST /orders/{id}/cancel` (frees its tables, voids its tickets) |
| `changeStatus(id, status, reason)` | `POST /orders/{id}/status` |
| `setTags(id, tagIds)` | `PUT /orders/{id}/tags` |
| `resetOrderNumber(sessionId, mode)` | `POST /order-numbers/reset` `{scope, sessionId}` |
| `getOrderById` / `loadOrderDetails` / `getOrderFullDetails` | `GET /orders/{id}?view=cart\|full` |
| `getOrderRow` / `findOrderRowByCode` / `getOrderByCode` | `GET /orders/{id}` · `GET /orders?code=` |
| `getPaginatedOrdersWithFullDetails(filters…)` | `GET /orders?page=&size=&status=&type=&unpaid=&q=&customer=&cashier=&table=&waiter=&session=&sessions=&from=&to=&sort=&tags=&untagged=` |
| `getHeldOrders` | `GET /orders?held=true` |
| `getUnpaidOrdersForResume(filters)` | `GET /orders/unpaid?type=&table=&customer=&q=&cashier=&limit=` |
| `getOrderTotals(ids)` / `getOrderContentSummaries(ids)` | `POST /orders/totals` · `POST /orders/summaries` (id list in the body) |
| `ordersCreatedBetween` / `recentOrdersForNoteLink` | `GET /orders?from=&to=&user=` · `GET /orders/recent` |
| `linesOfOrder` / `linesForOrders` / `componentsOfLines` / `lineUidsForOrder` | `GET /orders/{id}/lines` · `POST /lines/query` |
| `moneySplitParts(id)` | `GET /orders/{id}/split-parts` |
| `findByMbwCode(plu)` | `GET /catalogue/products?plu=` |
| `businessOrderByCode(code)` | `GET /orders?code=` (the hub holds every till's orders; falls back to the cloud for older ones) |
| `watchOrderRow`, `watchCancellations`, `watchSavedLines`, `watchWaiterIdsByOrder` | snapshot `GET` + topics `order:<id>`, `orders` |

### 5.2 Kitchen: `KitchenService`, `KdsStatsQueries`

| POS method | Endpoint |
|---|---|
| `watchBoard(sessionId)` | `GET /kitchen/board?session=` + topic `kitchen` |
| `setLineState(lineId, state, source)` | `POST /kitchen/lines/{lineUid}/state` |
| `setRush(orderId, rush)` | `POST /kitchen/orders/{id}/rush` |
| `signalOrderReady(orderId)` | `POST /kitchen/orders/{id}/ready` |
| `forSession(sessionId)` | `GET /kitchen/stats?session=` |

### 5.3 Floor: `FloorService`, `FloorQueries`

| POS method | Endpoint |
|---|---|
| `watchTables` | `GET /floor/tables` + topic `tables` |
| `openTable(tableId)` | `POST /floor/tables/{id}/open` (409 `table_occupied`) |
| `transfer(orderId, from, to, by)` | `POST /orders/{id}/transfer` `{toTableId, by: cashier\|waiter}` |
| `clearTable(tableId, by)` | `POST /floor/tables/{id}/clear` |
| `reconcile(freeOnPayment)` | hub-internal after every payment (no endpoint needed) |
| `freeTablesForSession(sessionId)` | part of `POST /sessions/{id}/close` |
| `allTables`, `tableById`, `watchAreas` | `GET /floor/tables`, `GET /floor/tables/{id}`, `GET /floor/areas` |
| `waitersByIds`, `allWaiters`, `watchActiveWaiters`, `waitersForArea`, `areasOfWaiter` | `GET /waiters?ids=&active=&area=` · `GET /waiters/{id}/areas` |
| `waiterStats(id)` | `GET /waiters/{id}/stats` |

### 5.4 Payments: `PaymentService`, `TicketQueries`

| POS method | Endpoint |
|---|---|
| `pay(orderId, method, amount, lines, splitDetails, …)` | `POST /orders/{id}/payments` `{method, amount, lines: none\|unpaid\|rows\|quantities, splitDetails}`. The hub mints the ticket number, settles the lines, completes kitchen when configured and returns `{ticketId, ticketNum, settledRows}` |
| `completeIfSettled(orderId)` | hub-internal after each payment; the answer of `pay` says `completed: true/false` |
| `settleAsCash(orderId, due, sessionId, zDay)` | `POST /orders/{id}/settle-cash` |
| `draftSplit` / `saveDraftSplit` / `clearDraftSplit` | `GET` / `PUT` / `DELETE /orders/{id}/draft-split` + topic `drafts:<id>` |
| `recordPrint(ticketId)` | `POST /tickets/{id}/printed` |
| `editTicket(id, method, amount)` / `deleteTicket(id)` | `PATCH /tickets/{id}` · `DELETE /tickets/{id}` (unlinks its lines) |
| `removePaidLine(lineId, ticketId)` | `DELETE /tickets/{id}/lines/{lineUid}` → `{ticketDeleted}` |
| `getTicketById`, `getTicketsByOrderId`, `ticketsForOrders`, `paidTicketsForOrders` | `GET /tickets/{id}` · `GET /tickets?order=` · `POST /tickets/query` |
| `getTicketsPage`, `getAllFilteredTickets` | `GET /tickets?offset=&limit=&status=&q=&from=&to=&sort=` |
| `linesOfTicket`, `printItemsOf`, `tvaTotalOf`, `discountTotalOf`, `deliveryFeeForTicket` | `GET /tickets/{id}?include=lines,printItems,totals` |
| `watchDraftTicketCount` | topic `drafts:<orderId>` |

### 5.5 Sessions and Z: `CashSessionService`, `SessionQueries`, `DayService`, `ZQueries`

| POS method | Endpoint |
|---|---|
| `openForCashier(cashier, moneyAtStart, isAdmin, zId)` | `POST /sessions/open` → `{session, how: continued\|resumed\|started}` (rules checked by the hub) |
| `pause` / `resume` / `delete` | `POST /sessions/{id}/pause` · `/resume` · `DELETE /sessions/{id}` |
| `close(id, countedCash, notes, autoClosed, closedBy, freeTables)` | `POST /sessions/{id}/close` |
| `publishClose(id, report)` | hub-internal (push + email report + admin notice); nothing for the till |
| `recordMovement` / `deleteMovement` / `movementsOf` | `POST /sessions/{id}/movements` · `DELETE /movements/{id}` · `GET /sessions/{id}/movements` |
| `activeSessionOnTill`, `getActiveSession(cashier)`, `openSessionsOnTill` | `GET /sessions?status=open&terminal=&cashier=` |
| `getSessionById`, `getSessionsByIds`, `getSessionsPage`, `getSessionSummary` | `GET /sessions/{id}` · `GET /sessions?ids=` · `GET /sessions?offset=&limit=&status=` · `GET /sessions/{id}/summary` |
| `refreshConfig` | hub-internal (it pulls rules from the cloud) |
| `ensureForSession(user, superAdmin)` / `openManually(…)` | `POST /z/ensure` · `POST /z/open` |
| `closeBlock(z, perms)` / `autoCloseDue(z)` / `closesWithSession(z, sessionId)` | `GET /z/{id}/close-check?session=` → `{block, autoCloseDue, closesWithSession}` |
| `close(z, closeMode, endedBy)` | `POST /z/{id}/close` |
| `report(zId, isX)` | `GET /z/{id}/report?kind=x\|z` (the till prints it) |
| `getOpenZ`, `watchOpenZ`, `getById`, `recentZs`, `sessionsForZ`, `openSessionsOf`, `zDayOptions`, `reportBlockedByOpenShift` | `GET /z/open` (+ topic `z`) · `GET /z/{id}` · `GET /z?recent=` · `GET /z/{id}/sessions?open=&except=` · `GET /z/day-options` · `GET /z/x-blocked` |

### 5.6 Reports and unpaid: `ReportQueries`, `UnpaidQueries`

| POS method | Endpoint |
|---|---|
| `generateReport(from, to, sessionIds)`, `generateSessionReport`, `dayScopeFor` | `POST /reports/summary` · `GET /reports/sessions/{id}` · `GET /reports/day-scope?session=` |
| `generateProductsSummary`, `generateOptionsSummary`, `generateOrdersList`, `generateStaffSales` | `POST /reports/products` · `/options` · `/orders` · `/staff` |
| `getSessionsInRange`, `sessionIdsForPeriod` | `GET /sessions?from=&to=` |
| `unpaidOrders`, `summary`, `watchSummary` | `GET /unpaid?tablesOnly=` + topic `unpaid` |

### 5.7 Returns: `ReturnsService`

| POS method | Endpoint |
|---|---|
| `lookup(code)` | `GET /refunds/lookup?code=` (the hub pushes first, then asks the cloud for other sites' refunds) |
| `policyContextFor`, `refundedQuantities` | `GET /orders/{id}/refund-context` |
| `refund(…)` | `POST /refunds` (hub mints the code, books into the current Z) |
| `settleExchange(…)` | `POST /exchanges` |
| `publish` | hub-internal |
| `slipFor`, `refundsForOrder`, `refunds`, `businessRefunds` | `GET /refunds/{id}/slip` · `GET /refunds?order=` · `GET /refunds?session=&since=` · `GET /refunds?from=&to=&scope=business` |

### 5.8 People, catalogue, devices

| Interface | Endpoints |
|---|---|
| `UserService` | `GET /users?type=` · `GET /users/{id}` · `GET /users?username=` · `PATCH /users/{id}/display-name` · `POST /users/{id}/last-login` (the hub forwards both writes to the cloud) |
| `CustomerService` | `GET /customers?q=` · `GET /customers/{id}` · `GET /customers?ids=` · `GET /customers?phone=` · `PUT /customers/by-phone` (upsert) + topic `customers` |
| `CatalogueService` | `GET /catalogue/products?barcode=\|ids=\|category=\|active=` · `GET /catalogue/products/{id}` · `/variants/{id}` · `/components/{id}` · `GET /catalogue/products/{id}/components` · `/group-rules` · `/variants` · `/attributes` · `GET /catalogue/categories` · `/order-tags` · `/commercials` · `/component-groups` + topic `catalogue` · `POST /catalogue/products/{id}/availability` |
| `QuickProductService` | `POST /catalogue/products` (forwarded to the cloud, which enforces the plan's product cap) · `GET /catalogue/categories?local=true` |
| `SerialService` | `GET /serials/{id}` · `POST /serials/numbers` · `GET /catalogue/products/{id}/tracked` · `POST /serials/{id}/reserve` · `POST /serials/release` · `GET /serials?product=&available=true` (+ topic `serials`) · `GET /serials/conflicts` · `POST /serials/conflicts/ack` |
| `DeviceService` | `GET /devices?type=kds\|kiosk` · `GET /stations` · `POST /devices` · `PUT /devices/{id}` · `DELETE /devices/{id}` (stations are read-only: they come from the back office) |
| `NotesService` | `GET /notes` + topic `notes` · `POST /notes` · `PUT /notes/{id}` · `PATCH /notes/{id}` (move / resize) · `DELETE /notes/{id}` · `DELETE /notes` |
| `ReservationService` | proxied to the cloud reservation endpoints (they are online-only against BMS today) plus `GET /catalogue/bookable` · `/service-pools` · `/resources` from the mirror |
| `ExternalOrderService` | `GET /queue?page=&size=&source=&status=` · `GET /queue/counts` · `POST /queue/{id}/confirm` · `POST /queue/{id}/cancel` · `GET /orders/live-external` (+ topic `orders`) · `POST /orders/{id}/ready-for-pickup`. The hub reads the cloud queue once for the shop and pushes it to every till; the cloud already refuses a second acceptance (409), and the hub turns that race into a lock every till sees. |
| `AuditLog` | `POST /audit` · `GET /audit?from=&to=&q=&limit=&offset=` · `POST /audit/export` |
| `PendingOperations` | `GET /outbox?entity=` · `GET /outbox` · `POST /outbox/{id}/done` (the hub's cloud queue, inspected from a till) |
| `SyncService` | `GET /sync/status` (+ topic `sync`) · `POST /sync/run?what=all\|orders\|tickets\|sessions\|movements\|refunds\|pending` · `GET /sync/cursors` · `POST /sync/cursors/reset` · `POST /sync/pull-all` · `GET /sync/parked-refunds` · `POST /sync/parked-refunds/{id}/unpark`. `dumpDatabaseBeforeClear` / `clearAllData` stay **local** and only apply to a standalone till (a hub-linked till has no database to wipe). |

### 5.9 Devices, pairing, health

| Endpoint | Purpose |
|---|---|
| `GET /health` | liveness + `{role: primary\|standby, version, dbOk, cloudOk}` |
| `GET /pair/info` | the hub's name, role and certificate-authority fingerprint, for the pairing screen. The only call a device makes before it trusts the hub; it carries no data |
| `POST /pair` | a till, KDS or tablet pairs once with a code shown on the hub (or the admin PIN) → long-lived device token + the shop's certificate authority (§2.2) |
| `POST /devices/heartbeat` | presence (replaces today's KDS presence registry) |
| `GET /hub/info` | terminal list, business, versions, failover peer |

---

## 6. LAN-compatible API (waiter app, KDS, kiosk)

The hub serves **the same routes as `ServerService` today**, so the waiter app, KDS and kiosk keep their requests and payloads. They find it the same way (mDNS `_caisse212._tcp`, advertised by the active hub). Auth stays `x-server-password` (plus the waiter PIN login). **One change on their side:** the hub is HTTPS only (§2.2), so they connect with `https://` and trust the shop's certificate authority, received when they pair. A browser-based KDS board needs option A or B of §2.2.

| Method | Route | Today's handler (`server_service.dart`) |
|---|---|---|
| GET | `/health` | `_healthCheck` |
| GET | `/orders` | `_getOrders` (KDS feed) |
| GET | `/orders/events` | `_kdsEvents` (KDS push nudge) |
| POST | `/orders/events/ticket` | `_kdsEventsTicket` |
| POST | `/kds-api/settings-code` | `_kdsSettingsCode` |
| POST | `/orders` | `_createOrder` (kiosk) |
| PUT | `/orders/<orderId>` | `_updateOrder` |
| PUT | `/orders/products/<id>` | `_updateOrderProduct` (KDS line state) |
| GET | `/stations` | `_getStations` |
| GET | `/kds`, `/kds/<path>` | the KDS web bundle |
| GET | `/waiters/profiles` | `_waiterProfiles` |
| POST | `/waiters/login` | `_waiterLogin` |
| GET | `/waiters/dashboard` | `_waiterDashboard` |
| GET | `/waiters/products`, `/categories`, `/components`, `/component-groups`, `/product-components`, `/product-component-groups`, `/product-variants` | the scoped menu |
| GET | `/waiters/tables` | `_waiterTables` |
| GET | `/waiters/orders`, `/waiters/orders/<code>` | `_waiterOrders`, `_waiterOrderDetail` |
| POST | `/waiters/orders` | `_waiterCreateOrder` (replay-safe `requestId`) |
| PUT | `/waiters/orders/<code>/add-product`, `/add-products` | replay-safe |
| POST | `/waiters/orders/<code>/print` · `/cancel` · `/transfer-table` | |
| DELETE | `/waiters/orders/<code>/products/<opId>` | `_waiterRemoveProduct` |
| POST | `/waiters/tables/<tableId>/clear` | `_waiterClearTable` |
| GET | `/waiters/events` | waiter push channel (SSE) |
| POST | `/waiters/calls/<callId>/ack` | |
| GET | `/waiters/notifications`, POST `/waiters/notifications/read` | |

Payloads and error codes are documented in `docs/waiter_api_reference.md`, `waiter_api_errors.md`, `waiter_app_changes_2026-11.md`, `kds_changes.md`.

**Fix on the way:** the waiter's `DELETE …/products/<opId>` hard-deletes the line today. On the hub it must record a cancellation (`removed_order_items`, `canceled_quantity`) and notify the kitchen, like a cashier's removal (§10.4). The kiosk's `POST /orders` must validate and price options with the same rules as the waiter path (`priceOptions`); today it trusts `extraPrice`.

---

## 7. The till while both hubs are down

1. **Writes go to a local outbox**, each with its `X-Request-Id`. The till keeps no database in hub mode; the outbox is the one thing it stores (decided 2026-11-27): a **small SQLite file of its own** (`hub_outbox.sqlite`, one table: request id, method, path, body, created at), separate from the business database. Each row is deleted as soon as the hub confirms it, so the file is empty in normal running. SQLite rather than SharedPreferences: each write is a transaction that survives a crash or a power cut, rows stay in order, and the settings file is not rewritten on every sale. A separate file rather than a table in the standalone database: the hub-linked till then carries no business schema or migrations, and the queue survives a switch between modes untouched. Reads while both hubs are down: what the till last received from the hub (in memory) plus its own queued writes, marked stale in the UI; nothing from the other tills.
2. **Provisional ids:** a queued order gets a till-local negative id and a provisional code `P-<terminal>-<n>`; a queued payment gets a provisional ticket number `P<n>`. The receipt says *provisional* (legal wording to confirm, §11).
3. **On reconnect** the outbox is replayed in order. The hub answers each request with the real ids and numbers; the till swaps provisional ids for real ones on screen, empties the outbox, and reprints only if asked.
4. **Conflicts** are answered with the normal error codes: a table taken meanwhile → `table_occupied` → the till asks the cashier for another table. A line paid twice can't happen (the hub refuses the second settle). A Z closed meanwhile → the hub books into the open Z, as refunds already do.
5. **What can't be done offline:** refunds that need other tills' refunds (`lookup`), reservations, platform order acceptance, product creation. These are refused, as today when offline.

---

## 8. Mirroring with the cloud (hub ↔ BMS)

The hub becomes the shop's **only cloud client** for business data. It reuses the endpoints the POS already calls (base URL `https://app.caisse212.com/api`, headers `X-POS-Name`, `X-Business-Id`, bearer token with refresh).

### 8.1 Downstream (cloud → hub), the back-office mirror

`GET /pos/users`, `/pos/waiters`, `/pos/areas`, `/pos/tables`, `/pos/categories`, `/pos/products`, `/pos/variants`, `/pos/products/{id}/variants`, `/pos/components`, `/pos/component-groups`, `/pos/product-components`, `/pos/product-component-groups`, `/pos/stations`, `/pos/commercials`, `/pos/customers`, `/pos/coupons`, `/pos/payment-methods`, `/pos/order-tags`, `/pos/resources`, `/pos/serials`, `/pos/mappings`, `/pos/session-rules`, `/pos/refund-policy`, `/pos/identity`, `/pos/subscription`, `/pos/account-status`, `/pos/z/current`.
Deltas: `GET /pos/sync/orders`, `GET /pos/sync/payments` (cursor in `sync_cursors`); `GET /pos/sessions/{code}/orders`, `GET /pos/cash-sessions/{code}`, `GET /pos/orders/{code}`.
Cloud push channel: SSE `GET {base}/api/pos/queue/subscribe` (note the double `/api`, it is correct) with `X-Business-Id`. Events handled today: `connected`, `heartbeat`, `new-order`, `order-updated`, `order-cancelled`, `order-ready`, `order-state-changed`, `order-delivery-status-changed`, `reservation-updated`, `pos-command` (`close_session`, `close_current_session`, `close_all_sessions`, `display_alert`, `force_logout`, `logout`, remote SQL, set config, kick), plus account/subscription signals. In hub mode **only the hub listens to this stream**; which event and command runs where is in §8.4.

### 8.2 Upstream (hub → cloud), the outbox

One outbox worker, ordered per entity, with exponential backoff and a dead-letter state (like today's queue):
- Orders: `POST /pos/v2/orders/bulk` or `PUT /pos/v2/orders/{code}` (v2 once every line has a `lineUid`, cancellations as `canceledQuantity`); `DELETE /pos/orders/{code}`; `PUT|DELETE /pos/order-products/{serverId}`; `PUT /pos/orders/{code}/tags`; `POST /pos/orders/{code}/ready`.
- Tickets: `POST /pos/tickets/bulk`; `PUT|DELETE /pos/tickets/{orderCode}/{num}`.
- Sessions (carry the Z label and the Z close): `POST /pos/cash-sessions/bulk`; `PUT|DELETE /pos/cash-sessions/{code}`; `POST /pos/cash-sessions/{code}/close`; `POST /pos/cash-sessions/{code}/email-report` (idempotency key per session).
- Cash movements: `POST /pos/cash-movements/bulk`; `PUT|DELETE /pos/cash-movements/{code}`.
- Refunds (after their orders and tickets): `POST /pos/refunds/bulk`.
- Platform queue: `POST /pos/queue/{id}/confirm|cancel`.
- Admin notices: `POST /pos/notify`; remote command results: `POST /pos/remote/{requestId}/result`; remote access: `PUT /pos/remote-access`.

**Order of the push** stays what the till does today: sessions → movements → orders → tickets → refunds.

### 8.4 The cloud push channel in hub mode: the hub listens, the till runs device commands

Decided (2026-11-27): in hub mode **the till opens no SSE stream**; the hub is the only listener. Business events are handled by the hub, which tells the tills what changed on its own event stream (§5, topics). **Remote control of the device still runs on the till:** a command aimed at a device is relayed by the hub to that till, the till executes it, and the reply goes back through the hub. A query on the shop's data (`remote_sql`) runs on the hub, since a hub-linked till has no database. Standalone mode is unchanged: the till listens and runs everything itself, as today.

**Which stream.** Today the stream is per terminal: the cloud knows the till by `X-POS-Name` (and `X-Business-Id`) and sends a terminal's commands on that terminal's stream only. Two ways to keep that:

- **A, no cloud change (first):** the hub opens one stream per paired till, with that till's identity. Commands arrive on the target till's stream, so the hub knows where to relay them. A business event that the cloud sends to every terminal then arrives once per stream; the hub handles it once (key: event type + queue item id or order code). *To check with the backend: which events go to every terminal, which to one.*
- **B, later:** one stream for the hub, each command carrying its target terminal. Fewer connections; needs a backend change.

**Events**

| Event | Hub mode | What the tills see |
|---|---|---|
| `connected` | hub: catch-up pull of open sessions and the platform queue (the stream has no replay) | nothing new; a till catches up when its own hub stream reconnects |
| `heartbeat` | hub: watchdog | the hub's own heartbeat |
| `new-order`, `order-ready`, `order-delivery-status-changed` | hub: platform queue, read once for the shop | topic `external_queue` |
| `order-cancelled` | hub: takes the item off the queue | topic `external_queue` + the loud alert on every till, flagged when it was already confirmed |
| `order-updated` | hub: re-pulls that order (pull never subtracts) | topic `orders` |
| `order-state-changed` | hub: logged only, as today | — |
| `reservation-updated` | hub: re-pull (debounced) | topic `reservations`; an open agenda re-reads |

**`pos-command` types**

| Command | Runs on | Notes |
|---|---|---|
| `sync_all`, `reload_all`, `update:db`, `reload_menu`, `sync_menu`, `sync_products`, `reload_products`, `sync_categories`, `sync_users`, `sync_areas`, `sync_upload`, `sync_orders`, `sync_sessions`, `sync_customers` | **hub** | the hub is what syncs; tills refresh from its topics. Not relayed: a hub-linked till does not sync. |
| `order_tags_updated`, `refund_policy_updated`, `sync_refund_policy` | **hub** | back-office mirror; topic `catalogue` |
| `close_session`, `close_current_session`, `close_all_sessions` | **hub + till** | the session lives on the hub, so the hub closes it (no `SESSION_END` log: not a person's close, as today); the till that held it is told and goes to the login screen |
| `force_logout`, `logout`, `force_kick`, `kick` | **till** | relayed to the target till; a kick pauses the shift through the till's normal session call to the hub |
| `open_admin_mode`, `close_admin_mode`, `exit_admin_mode` | **till** | device UI |
| `display_alert`, `custom` | **till** | relayed to the target till |
| `account_disabled`, `account_enabled` (and aliases) | **hub + every till** | the hub keeps taking writes and queues its pushes until re-enabled; each till locks its login as today |
| `refresh_token` (and aliases) | **hub + till** | the hub renews the token it uses for that terminal; the till renews its own for its account-level calls (login, subscription) |
| `subscription_updated` (and aliases) | **till** | account-level: the till re-reads `/pos/subscription` directly, as today |

**Remote console (requests with a `requestId`, `remote_command_service.dart`)**

| Command | Runs on | Notes |
|---|---|---|
| `ping`, `app_info`, `diagnostics`, `get_logs` | **till** | about the device |
| `get_config`, `set_config`, `get_printers`, `set_printers`, `test_print` | **till** | settings and printers are the device's |
| `remote_access_open` | **till** | RustDesk runs on the device |
| `remote_sql` | **hub** | decided 2026-11-27: a hub-linked till has no database, so in hub mode the query runs on the hub's PostgreSQL, read-only with the same guards as the till (a role with `SELECT` only, statement timeout, row and size caps). The reply says `engine: postgres` and the hub's schema version, since the tables and SQL dialect differ from the till's SQLite. A standalone till runs it on its own SQLite, as today. |
| `pending_sync` | **hub + till** | the hub answers with its cloud outbox for that terminal, and adds the till's own queue (§7, usually empty) when the till is connected |

**Replies.** A relayed command reaches the till on its topic `commands:<terminal>`; the till answers `POST /hub/v1/commands/{requestId}/result`, and the hub posts `POST /pos/remote/{requestId}/result` with that terminal's identity. One path, which still works when only the hub has internet. If the target till is not connected to the hub, the hub replies `device_offline` at once rather than letting the back office wait out its timeout. What the hub runs itself (`remote_sql`, the outbox part of `pending_sync`) it answers directly.

**On the till (when the hub client is built):** in hub mode, the SSE provider does not start, and `PosCommandHandler` and `RemoteCommandService` take their commands from the hub stream instead. A relayed sync command is refused there with `not_in_hub_mode`, since a hub-linked till never syncs.

### 8.3 Rules the mirror must keep

- **Pull never subtracts:** a pull removes a line only when the server marks it `deletedAt`, never because a stale snapshot lacks it. The shop's own writes win until they are pushed.
- **Delete means cancel:** a web delete of an order or line arrives as a cancellation; undo lowers `canceledQuantity`.
- **Cloud sees terminal states only:** orders are born `COMPLETED`; kitchen micro-states (`IN_PROGRESS`, `DONE`…) stay on the hub and are not pushed as order status.
- **zDay on the wire is `yyyy-MM-dd`** (a datetime is silently nulled server-side).
- **Datetimes:** store UTC `timestamptz`, but send each field in the shape the till sends today: local wall clock with no offset (`toIso8601String()` on local time, `formatLocalMillis`), except `refundedAt`, UTC with `Z`. The backend reads them that way.
- **Identity per terminal:** the cloud identifies a till by `X-POS-Name` and its terminal record. The hub pushes each row with the terminal that rang it up (it holds every paired till's terminal identity), so cloud reports per terminal stay correct.

---

## 9. Mirroring between two hubs (primary / standby)

Requirement: tills switch to the second hub when the first is down, and queue when both are.

**Recommended: one writer at a time, PostgreSQL streaming replication + a lease.**
1. Hub A is primary: its Postgres is the writer. Hub B runs Postgres as a **hot standby** (physical streaming replication, synchronous commit so an acknowledged write is on both disks).
2. The primary holds a **lease** (renewed every few seconds) in a place both can see. Best: the cloud (`/pos/hub-lease`, new); fallback: a witness on the LAN (the tills vote, or a tiny third process).
3. A till talks to the primary. When it can't reach it, it tries hub B. **B answers writes only once it has taken the lease** (A's lease expired) and promoted its database; until then it returns `503 standby` and the till keeps trying A, then queues.
4. When A comes back it finds the lease held by B, **demotes itself** and re-syncs as B's standby (`pg_rewind`). No split brain: only the lease holder writes.
5. Counters and ids stay unique because there is one writer at a time, and the sequences come with the replicated database.

**Alternative (if the shop's LAN is often partitioned): multi-writer with an operation log.** Each hub writes its own ops to `events` with a hybrid logical clock; ids are UUIDv7, counters are reserved in blocks per hub (A: 1–999, B: 1000–1999 per scope). On rejoin, each replays the other's ops; conflicts (same table, same line) are resolved by rule (first payment wins, cancel beats edit…). More resilient but much more complex; not recommended for v1.

---

## 10. Business logic the hub must reproduce exactly

The hub replaces the till's calculations, so Dart and Go must give **the same numbers**. Ship **golden fixtures** (JSON input → expected output) generated from the Dart code and run by both test suites. **Done for the pure rules:** `test/golden/` (172 cases: line and order money, options, Z rules, refund policy, tables, splits; format and conventions in its README). The rules that need a database (payment settlement, X/Z figures, session open rules, order numbers) are pinned by the till's database tests until they get a shared form.

| Area | Dart reference |
|---|---|
| Line money: `unitaryPrice` is TTC after catalogue discount, `unitaryTva` an amount, options per unit, removal charges | `domain/models/order_money.dart` (`LineAmounts`), `order_money_rows.dart` |
| Owed or not: a cancelled line is not owed unless already paid | `lineCountsInTotal(state, paid:)` |
| Order discount | `applyOrderDiscount`, `orderDiscountAmount` |
| Options: groups, min/max, free quantity, conditional groups, per-option cap | `component_rules.dart` (`priceOptions`, `OptionProblem`, `maxUnitsOf`) |
| Payments: by line, by quantity, by amount (split parts), settle as cash, completing an order | `ticket_settlement_service.dart` (`SettledLines`, `createPaidTicket`), `LocalPaymentService` |
| Table occupancy and release | `orderBlocksTable`, `table_occupancy.dart`, `LocalFloorService` |
| Unpaid gate and summary | `unpaid_orders_service.dart`, `OrderRepository.unpaidOrderSql` |
| Session open rules | `SessionService.checkOpenRules` |
| Z rules: open mode, can't-open-after, earliest close, BY_SESSION, AUTO_AFTER_HOUR, business-day start hour | `z_rules.dart`, `z_actions.dart` |
| Refund policy, closed-Z detection, other-tills cap | `refund_service.dart`, `refund_policy.dart` |
| Reports: X/Z, products, options, staff, tags band, delivery fees excluded from sales | `daily_summary_service.dart`, `session_z_details.dart` |
| Kitchen timing, late alerts, rounds, course sequence | `kitchen_timing.dart`, the KDS feed (`courseLines`, `prepMinutes`, `doneAt`) |
| Order number per scope | `AppDatabase.nextSessionOrderNo` |
| Code formats | `order_code.dart`, session code `CS-YYYYMMDD-<posId>-HHMMSS-XXX` |

### 10.4 Cancellation semantics (one rule for every source)

A line removed after it was saved, by a cashier, a waiter or the web, is a **cancellation**: `canceled_quantity` grows, a `removed_order_items` row records who, why and whether it was charged, and the kitchen gets a cancel ticket. Only an unsaved line simply disappears.

---

## 11. Open questions (for you to decide)

1. **Z with a hub:** one Z per terminal (today's cloud contract v3: `(terminal, zDay, zSeq)`) or **one Z for the shop**? A shop Z needs a cloud contract change; per-terminal keeps the cloud as is.
2. **Kitchen ticket of a waiter order:** which till prints it, or does the hub print it (a network printer reachable from the hub)?
3. **Receipts printed while queued:** what a provisional receipt must say (legal), and whether to reprint with the real number.
4. **The lease:** can the cloud hold it (one small endpoint), or must it work with no internet (LAN witness)?
5. **Where the hub runs:** a dedicated mini-PC (Linux) or one of the tills (Windows service)? This affects updates, backups, and whether "hub down" also means "a till down".
6. **Charged removals and required options** from the waiter app (`waiter_app_changes_2026-11.md` §8, §9).
7. **Multi-site:** one hub per shop (assumed), or one hub serving several businesses?
8. **What a till may create:** stations come from the back office only (Add Station removed from the till, 2026-11-27). Still to decide, for the same reason: quick product create (`POST /pos/products`), category create (`POST /pos/categories`), and anything else the till writes into the back-office data.
9. ~~**Remote SQL in hub mode**~~: decided 2026-11-27, it runs on the hub's PostgreSQL, read-only (§8.4).
10. **Browsers on HTTPS** (§2.2): install the shop's certificate authority on each browser device (A), or a public name per hub with a real certificate (B)?
11. **Older waiter app builds:** the hub is HTTPS only, so a waiter build that only speaks HTTP cannot reach it. Update every tablet before a shop moves to a hub, or let the hub open a temporary HTTP port for the LAN-compatible routes (off by default)?

---

## 12. Enhancements the hub makes possible

- **One floor for every till:** live table state, transfers and payments seen instantly everywhere, no double-occupied table.
- **Shared numbering:** no more per-till order codes or station ids colliding (`max+1`).
- **One "86" list for the shop:** taking a product off (`Products.isAvailable`) is local to each till today, on purpose: it is never sent to the cloud and a catalogue sync keeps it. So a product 86'd on one till is still sold on the others. The hub holds the flag for the whole shop and pushes it to every till and tablet; it still never sends it to the cloud.
- **One platform-order reader:** the queue is polled once per shop instead of once per till, and a pending order shows as taken on every till the moment one accepts it.
- **Central kitchen routing:** lines routed to stations and KDS by the hub; one board for all tills; per-station throughput.
- **Live shop reports:** X/Z and unpaid across all tills, before anything reaches the cloud.
- **Faster and cheaper cloud sync:** one connection, batched, with one cursor instead of one per till.
- **Device management:** KDS/kiosk/tablet pairing, presence, versions and remote restart from one place.
- **Print server** (later): network printers driven by the hub, any till printing to any printer.
- **Stock** (later): serials and quantities decremented once, in real time.
- **Metrics:** request latency, queue depth, sync lag, failover events, exposed on `/metrics` (Prometheus) for the super-admin diagnostics.

---

## 13. Go project sketch

```
hub/
  cmd/hub/main.go            config, migrations, start HTTP servers, workers
  internal/api/tillapi/      /hub/v1 handlers (one file per interface group, §5)
  internal/api/lanapi/       LAN-compatible routes (§6), x-server-password
  internal/events/           event log + SSE fan-out (Last-Event-ID)
  internal/domain/           money, options, payments, Z rules… (pure, golden-tested)
  internal/store/            Postgres (pgx + sqlc), migrations/
  internal/cloud/            BMS client, outbox worker, delta pullers, cloud SSE
  internal/replication/      lease, role (primary/standby), promotion
  internal/discovery/        mDNS _caisse212-hub._tcp (tills) + _caisse212._tcp (LAN-compatible clients)
  internal/pki/              the shop's certificate authority, server certificate issue and renewal (§2.2)
  internal/auth/             pairing, device tokens, waiter PIN, permissions (pos:*)
  testdata/golden/           fixtures shared with the Dart tests
```

Libraries: `net/http` + `chi` (routing), `pgx` + `sqlc` (typed SQL), `goose` (migrations), `grandcat/zeroconf` (mDNS), `float64` for money (not `shopspring/decimal`: the till rounds binary doubles half away from zero, so `1.005` rounds to `1.00`; decimal would give `1.01` and the two sides would disagree, see `test/golden/README.md`), `log/slog` (logs), `prometheus/client_golang` (metrics).

---

## 14. Suggested order of work

1. **Golden fixtures from Dart** (money, options, Z rules, refunds, tables, splits: done, `test/golden/`), then the Go `domain` package passing them.
2. **Hub skeleton:** Postgres schema for the mirror + shop data, the shop's certificate authority and HTTPS (§2.2), `/health`, pairing, event stream. On the POS: the Super admin **Mode** tab (§2.1).
3. **Cloud mirror down** (back-office data, read-only), then **outbox up** for orders/tickets/sessions.
4. **Till API for reads** (§5 GETs) and a `Hub…` implementation of the 8 read interfaces in the POS, behind `hubMode`; run the POS read contract (`test/contracts/read_queries_contract.dart`) against it.
5. **Till API for writes**, interface by interface in the catalogue's order (Floor → Kitchen → Order → Payment → Sessions/Z → Returns → the rest), each with its POS contract test running against the hub.
6. **LAN-compatible API** (§6) and mDNS; point a waiter tablet and a KDS at the hub.
7. **Offline queue on the till** (§7).
8. **Standby hub and lease** (§9).
