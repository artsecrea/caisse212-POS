# Golden fixtures

JSON cases (input → expected) for the till's business rules. The till's tests run them (`test/golden_fixtures_test.dart`) and the Go hub's tests must run the **same files** and get the same answers. That is how the hub is kept from drifting from the till on money and rules (`docs/hub_server_design.md` §10).

The `expected` values are **generated from the Dart code**, then checked by hand. They state what the till does today, including the odd cases (named as such).

## Files

| File | What | Dart |
|---|---|---|
| `fixtures/line_money.json` | one line's net, gross, discounts, VAT; owed or not; order percentage; the report's line split; VAT rate from the amount | `order_money.dart`, `cash_report_sections.dart` (`LineMoney`, `vatRateOf`) |
| `fixtures/order_money.json` | an order's totals, as the waiter API sends them and as the till's cart computes them | `waiter_order_money.dart`, `order_models.dart` (`CurrentOrder`) |
| `fixtures/options.json` | option checks and pricing (groups, free quantity, conditional groups, caps), opening selection, charged removals | `component_rules.dart` |
| `fixtures/z_rules.json` | business day, rule times, which Z the next session joins, open/close checks, auto close, warnings | `z_rules.dart` |
| `fixtures/refund_policy.json` | reading the policy, the limits a refund passes and who may approve them | `refund_policy.dart` |
| `fixtures/tables.json` | paid line, settled order, table release, table blocked for a new order | `line_payment.dart`, `table_occupancy.dart` |
| `fixtures/splits.json` | cent rounding, equal split parts, next ticket number | `split_bill.dart` |

## Format

```json
{
  "area": "options",
  "about": "what the cases cover and the conventions of this file",
  "dart": "the Dart source of truth",
  "cases": [
    {"name": "unique in the file", "fn": "priceOptions", "input": {}, "expected": {}, "note": "optional"}
  ]
}
```

`fn` names the function; `test/golden/golden_functions.dart` shows exactly how each input is turned into the Dart call and how the result is written. A Go runner needs one adapter per `fn`.

## Conventions

- **Numbers:** compare with a tolerance of `1e-6`. Expected doubles are written to 6 decimals. An integer field (quantity of an option, zSeq, a component id) is an integer.
- **Optional input fields** take the Dart default when missing: an amount is `0`, an order-line `quantity` is `1`, a `state` is `PENDING`, an optional flag is `false` (except `isFullRefund`, `true`). The other fields are required; `golden_functions.dart` shows which.
- **Maps keyed by id** (`picked`, `catalogue`, `groupOf`, `maxEach`, `seeded`) use the id as a string, because JSON keys are strings. In `groupOf`, `null` is the ungrouped bucket.
- **Order that carries no meaning is sorted:** option `lines` by `componentId` then `unitPrice`; `warnings`, `methods` and `permissionsNeeded` alphabetically. Every other list is in its real order: refund `issues` come in the order the till checks them, `amounts` part by part.
- **Enum values** are the Dart names (`notOffered`, `tooLateToOpen`, `orderSettled`, `continueOpen`…), except refund flags, which are their wire values (`CLOSED_Z`, `WINDOW`…).
- **Times** are the shop's wall clock, `yyyy-MM-ddTHH:mm:ss` with no offset. Business days are `yyyy-MM-dd`. No case crosses a daylight-saving change.
- **Money is a binary double, rounded half away from zero on `value * 100`.** So a half cent goes the way the double product lands: `1.005 → 1.00` but `2.675 → 2.68`, and the order `3 × 3.335 + 6.93 = 16.935` is sent as `16.93`. Go `float64` with `math.Round(v*100)/100` gives the same results; `shopspring/decimal` does not. Keep `float64` for anything the till also computes, or both sides stop agreeing.
- **The waiter API's amounts are rounded once, at the end:** `paidAmount` is `round(total − balance)` on the unrounded figures, not the difference of two rounded ones.

## Changing a rule

1. Change the Dart code (a decided rule change only).
2. `GOLDEN_UPDATE=1 flutter test test/golden_fixtures_test.dart` rewrites every `expected`.
3. Read the diff: it is exactly what the hub must change too. Commit both together.

To add a case, write its `input` (no `expected`) and run step 2.

## Not covered here, and why

These need a database or the clock, so they are pinned by the till's database tests instead. The interface contracts (`test/contracts/`) will also run against the hub; the others are till-only today and need a shared form before the hub copies them:

- payment settlement: by line and by amount in `payment_service_contract.dart`; by quantity in `ticket_settlement_service_test.dart` (till only);
- session open rules (`SessionService.checkOpenRules` counts sessions and reads the clock): `cash_session_service_contract.dart`;
- the X/Z report figures (`CashReportBuilder` reads the stored rows): `cash_report_sections_test.dart`, `z_report_tags_test.dart`, `delivery_fee_totals_test.dart` (till only);
- per-scope order numbers (`AppDatabase.nextSessionOrderNo`): `session_order_no_test.dart` (till only); order and session code formats.
