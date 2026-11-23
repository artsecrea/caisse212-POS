# Refund Policy — POS ⇄ BMS Contract (v1 proposal, 2026-10-07)

Refunds already work end to end. The POS records them offline, pushes them to `POST /pos/refunds/bulk` (idempotent on `code`, per-record verdict), and handles the restock/waste flag, the over-refund and amount caps, the slip, the session/Z totals and the drawer. Four tokens already exist: `pos:refunds:view|create|waste|amount:override`, seeded by V148.

This contract adds the **policy**: rules set in BMS that decide which refunds a till may give, who has to approve the exceptions, and how refunds show up in the current Z and in stock.

## 0. The problem it fixes

Today the POS **hides the Refund button as soon as the order's session is closed**. A customer who comes back the next day, or even after a shift change, cannot be refunded at all. Staff work around it, and the refund never reaches the books.

The fix: a refund is always booked into the **current** open session and Z. The original sale's closed Z is never touched. Whether a past sale may be refunded is decided by the policy and by permissions, not by a hard lock.

## 1. Principles

1. **A refund belongs to the Z it is paid out in**, not to the Z of the sale. The closed Z stays immutable. Today's Z shows "refunds: −X". Today's drawer expects X less cash (cash refunds only).
2. **The POS enforces the policy at the till**, before any money moves. The till works offline, so it uses the last policy it fetched.
3. **The server never rejects a refund for a policy reason.** By the time the refund reaches the server, the money has already been handed back. If the policy changed in between, or the till was offline, the server **stores the refund and flags it** (`policyFlags`). It still rejects only structural errors, as today: over-refund, unknown order or line, amount above the derived value.
4. **Permissions decide who can exceed a limit.** A cashier without the token gets a "supervisor approval" step at the till, where a supervisor enters their credentials. The refund then records `approvedBy`.
5. **No policy fetched means today's behaviour**, apart from the session lock, which is removed. Nothing breaks before BMS ships its side.

## 2. `GET /api/pos/refund-policy` (new)

The external path is `/api/api/pos/refund-policy`. Headers are the same as every POS call (Bearer, X-POS-Name, X-Tenant-ID, X-Business-Id). Resolution: a business-level policy, optionally overridden per terminal, like session-rules.

```json
{
  "enabled": true,
  "windowDays": 30,
  "closedZNeedsPermission": true,
  "approvalAbove": 500.00,
  "requireReason": true,
  "reasons": [
    { "code": "DEFECTIVE",      "label": "Produit défectueux" },
    { "code": "WRONG_ITEM",     "label": "Erreur de commande" },
    { "code": "CUSTOMER_CHANGE","label": "Changement d'avis" },
    { "code": "OTHER",          "label": "Autre" }
  ],
  "allowedMethods": ["CASH", "CARD", "TRANSFER", "CHECK"],
  "methodMustMatchPayment": false,
  "allowPartial": true,
  "defaultRestock": true
}
```

| Field | Type | Default (absent/null) | Meaning at the till |
|---|---|---|---|
| `enabled` | bool | `true` | `false` = refunds switched off for this business. No permission can bypass it. |
| `windowDays` | int? | `null` = no limit | Max business days between the sale's `zDay` and today's `zDay`. Beyond that, `pos:refunds:override` is required. |
| `closedZNeedsPermission` | bool | `true` | Refunding an order whose Z is already **closed** needs `pos:refunds:closed-z`. With `false`, anyone holding `pos:refunds:create` can, inside the window. |
| `approvalAbove` | number? | `null` = never | A refund whose **total** is above this needs `pos:refunds:override`. |
| `requireReason` | bool | `false` | A reason is mandatory. |
| `reasons` | array | `[]` | Preset reasons as `{code, label}`. If not empty, the cashier picks one; `OTHER` (when present) opens free text. If empty, free text only. |
| `allowedMethods` | string[] | all four | Methods offered. Anything else needs `pos:refunds:override`. |
| `methodMustMatchPayment` | bool | `false` | The method must be one the order was **paid** with (a card sale is refunded to a card). Otherwise `pos:refunds:override` is required. |
| `allowPartial` | bool | `true` | `false` = only a full refund of what remains on the order. A partial one needs `pos:refunds:override`. |
| `defaultRestock` | bool | `true` | Initial position of the per-line "return to stock" switch. Changing it still needs `pos:refunds:waste`. |

Responses:
- `200` + body → stored (cached like session-rules).
- `404` → older server; keep the cache, and if there is no cache, use the defaults.
- `204` → no policy configured; use the defaults.

When the POS fetches it: at login, on every full sync or Update, and on the SSE command `refund_policy_updated` (§7).

## 3. Product flag: `refundable`

`GET /pos/products` items gain `"refundable": true|false` (absent = `true`). BMS may resolve it from the category. A non-refundable line can only be refunded with `pos:refunds:override`, for example food that was served.

## 4. Permissions

| Token | Status | Gates |
|---|---|---|
| `pos:refunds:view` | exists (V148) | Sees refunds on orders |
| `pos:refunds:create` | exists | Can open the refund flow at all |
| `pos:refunds:waste` | exists | Can switch a line to "not returned to stock" |
| `pos:refunds:amount:override` | exists | Can type a lower amount than the derived one |
| **`pos:refunds:closed-z`** | **new** | Refund an order whose Z is closed (an earlier day/Z), when `closedZNeedsPermission` |
| **`pos:refunds:override`** | **new** | Approve or exceed the policy: past `windowDays`, total above `approvalAbove`, method not allowed or not matching the payment, non-refundable product, partial when `allowPartial=false` |

Seeding request: both new tokens go to the admin roles and `POS_SUPERVISOR`, **not** `POS_CASHIER`. A cashier gets the supervisor-approval step instead.

The POS keeps its existing rollout rule: a user holding **none** of the `pos:refunds:*` tokens keeps the old permissive behaviour. Once any of them is present, the set is enforced.

## 5. Changes to `POST /pos/refunds/bulk` (additive)

Each refund object gains these fields. All are optional, so older POS builds keep working:

```json
{
  "code": "RF-T1-20261007-101500-000",
  "orderCode": "...",
  "method": "CASH",
  "reason": "Produit défectueux",
  "reasonCode": "DEFECTIVE",
  "refundedBy": 12,
  "refundedAt": "2026-10-07T10:15:00Z",
  "zDay": "2026-10-07T00:00:00.000",
  "sessionCode": "CS-T1-20261007-0800",
  "approvedBy": 3,
  "policyFlags": ["CLOSED_Z", "WINDOW"],
  "lines": [ { "orderProductId": 991, "quantity": 1, "restock": true } ]
}
```

| Field | Meaning |
|---|---|
| `sessionCode` | The cash session the money left from, so the server can tie the refund to **today's** session and Z, not the sale's. |
| `reasonCode` | The preset reason code (`reason` still carries the text). |
| `approvedBy` | User id of the supervisor who approved an exception. Null when no approval was needed. |
| `policyFlags` | Which policy limits this refund went past at the till: `CLOSED_Z`, `WINDOW`, `AMOUNT`, `METHOD`, `NON_REFUNDABLE`, `PARTIAL`. Empty = a plain refund. |

The server stores these fields as sent and never rejects a refund because of them. It may add its own flag (for example `POLICY_CHANGED`) when its current policy disagrees, for the back-office report.

## 6. Z and stock

**Z / session.** The refund carries `sessionCode` and `zDay` of the session open when it was given. Per Z contract v3, the server's Z figures are the sum of its sessions' `details`. Today `details.refunds` holds `{total, cash}`. This contract adds:

```json
"refunds": {
  "total": 120.00,
  "cash": 80.00,
  "count": 3,
  "byMethod": [ { "method": "CASH", "count": 2, "amount": 80.00 },
                { "method": "CARD", "count": 1, "amount": 40.00 } ],
  "earlierSales": 60.00,
  "waste": 15.00
}
```

All figures are additive. `byMethod` merges on `method`, as the v3 merge rules already do for arrays.
- `earlierSales` = the part of the refunds whose order belongs to an earlier, closed Z.
- `waste` = the value of the lines refunded **without** returning them to stock.

**Stock.** No change to the semantics: `restock: true` posts a positive stock movement, and `restock: false` (waste) leaves the goods counted as sold. The request to BMS is to **tag the restock movement with the refund `code` and `reasonCode`**, so the stock history shows *why* the goods came back. For serial-tracked units, a full restock refund makes the unit available again (as today).

## 7. SSE

`{"type":"refund_policy_updated"}` → the POS re-reads `GET /pos/refund-policy`. Fire it when the policy is saved in BMS. It is optional: the POS also refreshes the policy at login and on every sync.

## 8. The till (POS side, for reference)

- **Orders screen → order menu → Refund**: now also shown for orders from closed sessions or Zs. The dialog explains what the policy requires.
- **Top bar → Refund a receipt**: type or scan an order code. The till looks it up locally first, then on the server (an order sold on another till).
- **Refund dialog**:
  - preset reason picker (when `reasons` is set);
  - methods limited to `allowedMethods`, with the method(s) the order was paid with shown;
  - the restock switch defaults to `defaultRestock`;
  - every policy limit the refund goes past is listed. Without the token, the button reads **"Supervisor approval"**, and a user holding the required token signs in to approve.
- **A refund needs an open cash session** of the cashier. The money comes out of a drawer, so it must land in a session and a Z.
- **X/Z paper and session close**: the refunds section shows the count, the split by method, the earlier-sales part and the waste.

---

## 9. As built (2026-10-07)

**BMS** (repo `bms`, migration `V192__refund_policy.sql`): built and tested, **not committed, not deployed**.
- `GET /pos/refund-policy` returns `200` with the effective policy: the terminal override is applied over the business policy field by field, with every field filled. It returns `204` when nothing is configured. `404` only happens on an old server.
- Caveat: a terminal override cannot set `windowDays` or `approvalAbove` back to "unlimited" when the business has a value. It has to use a large number instead.
- Back office API: `GET/PUT /api/refund-policy?businessId=`, `PUT /api/refund-policy/terminal/{id}`, `PUT /api/refund-policy/products/{id}/refundable` and `.../categories/{id}/refundable`. Writes need ADMIN. **The frontend screen is not built** (the frontend is a separate repo).
- Each policy save pushes `refund_policy_updated` over SSE. A product or category `refundable` change sends nothing and reaches the till on the next product sync.
- `/pos/products` always carries `refundable` (product ?? category ?? true).
- Both tokens are seeded to the `%admin%` roles plus POS_ADMIN(100) and POS_SUPERVISOR(102) of tenant 1. **Other tenants' supervisor roles need a manual grant.**
- Bulk refunds: the new fields are stored as sent and never cause a rejection.
  - `pos_terminal_id` is now the **refunding** terminal; the new `sale_pos_terminal_id` holds the order's terminal.
  - The server computes its own `earlier_sale`.
  - Restock goes to the refunding terminal's warehouse. The movement notes read `refund <code> [<reasonCode>]`.
  - Restock does **not** reverse BOM/recipe ingredients.
- Session `details` is free JSON. **Numbers only**: strings are not summed into the Z.

**POS** (schema v58): built, uncommitted, never run against the BMS build.
- `RefundPolicy` with a pure `refundPolicyIssues()` (`lib/domain/models/refund_policy.dart`), cached by `RefundPolicyStore`, exposed through `refundPolicyProvider`.
- The policy is fetched in `syncAllData`, which covers login, Update and `sync_all`, and on the SSE command `refund_policy_updated`.
- The Refund entry now shows for orders of closed sessions and Zs. "Refund a receipt" is in the user menu.
- The dialog needs an open session. It shows the preset reasons, the payment methods, the policy's default restock and the issue list, and asks for supervisor approval through `showAdminCredentialDialog(permissions: …)`.
- The payload carries `sessionCode`, `reasonCode`, `approvedBy` and `policyFlags`.
- The Z breakdown (`RefundBreakdown`) feeds the session details and the X/Z paper.
- Test mode has a "Refund policy" section.

## 10. Online-only refunds + Refunds screen (2026-10-07, user decision)

A refund needs the network. The till always reads the order (`GET /pos/orders/{code}`) and every refund already given on it, **on any till** (`GET /pos/refunds?orderCode=`, which returns a plain array and `[]` when there are none), fresh from the server.
- A 404 on the order means "not found".
- Any other failure refuses the refund with "needs internet". It is never treated as "nothing refunded yet".
- Server lines are mapped by `orderProductId` to the local line's `serverId`. Refunds this till already holds are skipped, so they are not counted twice. The over-refund cap now counts the other tills' quantities.

The **refund record** is still written locally and pushed through `POST /pos/refunds/bulk`, so it lands in this session's Z even if the push is delayed.

Entry points:
- the main-screen **Refund** button: `showRefundButton`, on by default, reorderable, toggled in Settings;
- the order menu → Refund.

Both go through `startRefund(orderCode)`. The user menu → **Refunds** opens a screen with two tabs:
- **This till**: local records, filtered by current session, today, 7 days or 30 days, with totals, details and reprint.
- **All tills**: `GET /pos/refunds?from&to&page&size`, a page envelope from BMS, built but not deployed.

## 11. Single-item refunds and exchanges (2026-10-08)

**Single-item and partial refunds.** These already worked: a refund names only the lines it returns, with any quantity, decimals included. BMS confirmed it from code and tests (V192 build):
- the cap is per line, across all tills;
- the batch reports per record;
- a restock moves exactly the refunded quantity, converted to base units.

The same build fixed two BMS bugs:
- refunding one item of a pack restocked a single piece;
- refunding a dish created phantom stock.

**Exchange.** A customer brings goods back and takes other goods in their place. It is one refund plus one new sale, linked:
1. In the refund dialog, choose the returned lines → **Exchange**. The policy applies as for a refund, except the method rule. Nothing is written yet. The main screen shows an exchange banner with the returned goods and the credit, and the cart must be empty.
2. Ring up the new goods → **Pay**. Instead of the payment screen, the exchange settle dialog opens: credit, new total, and the difference (the customer pays it with a till method, or it is given back with a refund method the policy allows).
3. `ExchangeService.settle` writes everything in **one transaction**:
   - the refund, with `exchangeAmount` = credit used, `exchangeOrderId`/`exchangeOrderCode` = the new order, and `method` = how any remainder was given back;
   - on the new order, an `EXCHANGE` ticket for the credit (with `exchangeRefundCode`);
   - a ticket for what the customer paid;
   - all new lines settled.
4. **One receipt** shows: RETURNED (old order) with each item at minus its value, NEW ITEMS, Total, Exchange credit −X, Paid {method} Y or Given back {method} Z, and the refund code.

**Accounting.**
- The refund total stays the full returned value.
- Only `totalAmount − exchangeAmount` is paid back (`refundCashPaidBack`), and only that leaves the drawer.
- `EXCHANGE` is its own payment bucket: never cash, never "other", and not selectable on the payment screen.
- Net sales = new sale − returned value. Expected cash moves only by real cash.
- X/Z show "Exchange credit" under payments and "of which exchanged" under refunds.
- Session details carry `payments.byMethod` EXCHANGE and `refunds.exchange`, as numbers.

**Push order.** The new order (with its tickets) goes before the refund that names it.

**BMS** (V193__refund_exchange.sql, uncommitted and not deployed):
- `EXCHANGE` is accepted as a ticket method (free text);
- `exchangeRefundCode` is stored on tickets;
- `exchangeAmount` and `exchangeOrderCode` are stored on refunds (exchangeAmount outside 0..total+0.01 is a structural reject);
- dashboards split exchange refunds by method plus an EXCHANGE bucket.

**Schema.** POS schema v59.

**Verified** in Test mode → Run refund test: checks 6 and 7, the exchange ticket export, and the X with drawer 245.

## 12. Closed-Z refunds are free by default (user ruling 2026-10-08)

`closedZNeedsPermission` now **defaults to `false`**, both when absent and with no policy at all. Refunding an earlier sale is the whole point of a refund: any user holding `pos:refunds:create` may refund an order from a closed Z, inside the other limits. A business can still turn the requirement on, and then `pos:refunds:closed-z` (or a supervisor's approval) is needed.

The refund still records `earlierSale`, and the Z still reports "of which earlier sales" either way. `CLOSED_Z` is only sent in `policyFlags` when the rule is on.
