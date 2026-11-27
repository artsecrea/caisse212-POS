# Hub handoff

For whoever starts the Go hub (a person or a new Claude session) without the conversations that led here. Read this first, then the files in §2. State as of 2026-11-27.

## 1. Where things stand

- **The till is ready for a hub.** Branch `pos-hub-ready` of `github.com/artsecrea/caisse212-POS`. Every screen reads and writes through 27 service interfaces (`lib/domain/services/`), each with a local Drift implementation whose provider is the hub swap point. A guard test (`test/screens_use_service_interfaces_test.dart`) keeps it that way. The full suite passes (the 2 Windows updater tests fail on one dev machine only; environmental).
- **The hub has no code yet.** Its design is done; the open questions are the user's to answer (§11 of the design).
- **The money and rule cases are ready:** 172 golden cases in `test/golden/`, generated from the Dart code. The Go domain must pass them all.

## 2. Read these, in this order

1. `docs/hub_server_design.md`: decisions (§1), setup and HTTPS (§2.1, §2.2), the till API (§5), the LAN-compatible API (§6), the cloud mirror (§8), the standby hub (§9), the rules to reproduce (§10), open questions (§11), the Go layout (§13), **the order of work (§14)**.
2. `docs/hub_action_catalogue.md`: every till action, its interface, and the provider each one swaps (§6).
3. `test/golden/README.md`: fixture format, conventions, how a rule changes.
4. `docs/pos_hub_ready_branch.md`: what to check on a real till with this branch.

Existing contracts the hub inherits: `ORDER_CANCELLATIONS_CONTRACT.md`, `REFUND_POLICY_CONTRACT.md`, `SUBSCRIPTION_CONTRACT.md`, `session_rules_api.md`, `sse_pos_commands.md`, `SSE_STABILITY.md`, `ORDER_TAGS.md`, `waiter_api_reference.md`, `waiter_api_errors.md`, `waiter_app_changes_2026-11.md`. **`Z_TRACKING_API.md` is obsolete:** the Z contract is v3, in the backend repo (`docs/POS_Z_CONTRACT.md`), summarised in §4.

## 3. Working rules (from the user)

- **Commit each step**, one change per commit, with a message that says what and why. **No `Co-Authored-By: Claude` or `Claude-Session:` lines** in commits. Push only when the user asks.
- **No junk code, no skipping.** Remove dead code only when it is really dead (nothing calls it, nothing will).
- **Steady:** one step at a time, tests green before the next. A real decision (anything listed in design §11, any new rule) goes to the user; don't decide it in code.
- **Standalone stays exactly as today.** A till with no hub must behave the same as before; nothing for the hub may change that path.
- **In hub mode the till is only an interface:** it mints no ids or counters (order #N, ticket numbers, Z sequence, session codes), keeps no database, and does no cloud sync. The hub generates, saves and syncs.
- **A till is either the LAN server (standalone) or a hub client, never both.** In hub mode its LAN server never starts.
- **Back-office data comes from the real backend** (users, waiters, catalogue, stations, tenant, subscription). The hub mirrors it read-only (design §8.1) and never invents it. Stations are not created on the till.
- **A rule change starts in Dart:** change the Dart code, regenerate the fixtures (`GOLDEN_UPDATE=1 flutter test test/golden_fixtures_test.dart`), then make Go match the diff. Never hand-edit an `expected`.
- **Money is `float64` in Go**, rounded with `math.Round(v*100)/100`, never `shopspring/decimal`: the till rounds binary doubles (`1.005 → 1.00`, `2.675 → 2.68`), and decimal would disagree.
- **One session per branch.** Till-side work for the hub (the Super admin Mode tab, the `Hub…` implementations, the offline outbox) is done on `pos-hub-ready` in the POS repo, by one session at a time.

## 4. The cloud backend: facts the code doesn't make obvious

The hub replaces the tills as the shop's cloud client, so it must talk to the backend exactly as the till does (`lib/services/api_service.dart`, `lib/services/data_sync_service.dart`).

- **The double `/api` is correct.** The stored base URL is `https://app.caisse212.com/api` and the client adds `/api/pos/...`, so the real path is `/api/api/pos/...`. Verified against the deployed server; the backend source shows a single `/api`, so something in the deploy adds one. Don't "fix" it without testing the live server.
- **Headers on every call:** `Authorization: Bearer <token>` and `X-POS-Name` (the terminal is found by `X-POS-Name` plus the JWT tenant; a missing header gives 500). The till also sends `X-POS-Id`, `X-Tenant-ID` and `X-Business-Id`.
  - `X-Business-Id` must be the **real business id** (`posTerminal.businessId` from login), **never the tenant id**: that gives 403 "Business does not belong to the current tenant". No header is safer than a wrong one.
  - The SSE stream (`GET {base}/api/pos/queue/subscribe`) **requires** `X-Business-Id`. Without it the server answers an empty 200 that closes at once, and the client loops reconnecting.
  - A proxy (Cloudflare) in front of the backend has been seen stripping the `X-*` headers. "Missing X-POS-Name" or the empty 200 can be that, not the client.
  - Two terminals with the same name in one tenant make the backend answer 500 "Query did not return a unique result".
- **`zDay` is always `yyyy-MM-dd`** (`formatZDay`). A datetime-shaped zDay is silently nulled on orders and tickets, and a database trigger then re-derives the day in UTC (sessions and cash movements answer 400 instead).
- **Datetimes go out as the till sends them:** local wall clock with no offset (`DateTime.toIso8601String()` on local time, `formatLocalMillis` for cancellations), except `refundedAt`, which is UTC with `Z`. The backend reads them that way today. Store `timestamptz` inside the hub, but format each field like the till.
- **Orders are born `COMPLETED`** (the cloud's terminal status). Kitchen states live on each line's `state` and stay on the LAN; the cloud never sees PREPARING/READY. Never classify an order as open, done or unpaid by `order.status`.
- **Paid means the line has a ticket** (`ticketId`, see `line_payment.dart`). The push still sends `PAID` for ticketed lines that aren't cancelled (wire contract unchanged).
- **A pull never subtracts.** A pull removes a line only when the server marks it `deletedAt`, never because a stale snapshot lacks it. It keeps the local kitchen state, except when the server says CANCELED or PAID.
- **Cancellations ride the normal order push (v2):** `PUT /pos/v2/orders/{code}` and `POST /pos/v2/orders/bulk`. Each line carries a `lineUid` (1 to 7 characters when the till mints it, 8 for the server's own) and a running `canceledQuantity`. v2 is used only when every line has a uid. **In v2 a line missing from the push is deleted**, so never push a partial line list. Details in `ORDER_CANCELLATIONS_CONTRACT.md`.
- **On the web, delete means cancel.** An admin's removal arrives as a cancellation, and a web undo makes `canceledQuantity` go down.
- **The Z is v3:** a label on sessions (terminal, zDay, zSeq), not an entity. At start the till reads `GET /pos/identity` (timezone, business day start hour), `/pos/session-rules` and `/pos/z/current` to resume the counter. Closing a Z means re-pushing its last session with the close fields and `isClosingSession: true`. The rules are in `lib/services/z_rules.dart` (golden-tested).
- **A disabled account answers 423** and locks sign-in until reactivated. An expired subscription only warns.
- **Line price model:** `unitaryPrice` is TTC with the catalogue discount already taken off, and `unitaryTva` is an amount per unit, not a rate. Options are per unit of the line. The golden `line_money` cases pin it.
- **Backend features that may not be live.** Built in the backend between October and November 2026, but last known as not confirmed deployed: cancellations v2, web delete-means-cancel, the zDay parse fix, refund policy, order tags, reservations, account deactivation, component rules. Check the live server (or ask the user) before the hub relies on one.

## 5. The other repositories

- **Backend (bms):** Kotlin/Spring, branch `production`, on the user's Linux box (`/home/artecrea/projects/bms`). Other sessions and people work on it. The hub doesn't change it. New endpoints the design mentions (for example the hub lease, design §9) are requests to the backend team, through the user.
- **Waiter app:** the live one is `github.com/artsecrea/caisse212-waiter-app`. The copy inside the POS folder (`pos/caisse212_waiter`) is months out of date; don't read it. The waiter app vendors `component_rules.dart` verbatim, so an option-rule change must be ported there too.
- **KDS web board:** ships inside the POS as `kds_web.zip`, served by the LAN server. In hub mode the hub serves it (design §6).

## 6. Where to start

1. Clone the POS repo and check out `pos-hub-ready`. Flutter is needed only to run the till's tests or regenerate the fixtures.
2. Create the hub in its own folder (for example `caisse212 apps/hub`), laid out as design §13. Whether it is a new GitHub repo is the user's call.
3. **Design §14 step 1:** the Go `internal/domain` package, with one test adapter per golden `fn`, passing all 172 cases. `test/golden/golden_functions.dart` shows exactly how each input becomes a call and how the result is written. Read the fixtures from the POS checkout (a path in config), or copy them with a check that the copy matches; never edit them by hand.
4. The rules the fixtures don't cover need a database: payment settlement, X/Z figures, session open rules and order numbers. Port them from the Dart tests listed at the end of the golden README.
5. Then §14 step 2 (the skeleton: Postgres schema, the shop's certificate authority and HTTPS, `/health`, pairing, the event stream), and so on in the order given there.
