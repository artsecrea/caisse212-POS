# Waiter app: POS changes to absorb (November 2026)

What changed on the POS side of the waiter API, and what the waiter app
(`caisse212 waiter/caisse212-waiter-app`) has to do about it. Read this beside
`waiter_api_reference.md` and `waiter_api_errors.md`, which are updated to
match.

Summary of the work for the app:

1. Stop relying on the option prices it sends. The POS prices them now.
2. Handle four new `400` errors on create, add-product and add-products.
3. Port `priceOptions` into the vendored `component_rules.dart`, so the
   tablet refuses and prices the same selections as the till before it sends.
4. Expect totals that leave cancelled lines out.

---

## 1. The POS prices the options

**Before:** `products[].components[].price` was stored as sent. The tablet was
the pricing authority for options.

**Now:** the POS checks and prices options exactly as its own product dialog
does. The function is `priceOptions` in `lib/domain/models/component_rules.dart`.

- Only options this product offers (`GET /waiters/product-components`) and that
  are not 86'd (`isActive = false`) are accepted.
- An option in a group the selection keeps hidden (`visibleWhenComponentIds`)
  is refused.
- Each visible group's `minSelection` / `maxSelection` is enforced. A required
  group with nothing picked is refused.
- Price = the product link's `defaultPrice` when it has one, else the
  component's own `price`. The group's `freeQuantity` covers the most
  expensive units, exactly as on the till.
- **`price` and `name` in a component entry are ignored.** The stored name is
  the catalogue name.

The request shape does not change. Entries are summed per `componentId`, so:

- one entry per component is enough, since splitting a component into a free
  row and a charged row yourself is no longer needed;
- a client that still splits gets the same result.

Zero-quantity entries for an offered option are kept as zero rows at price 0.

Rows are stored the way the till stores them: a component whose free allowance
covers part of its quantity becomes two rows, one at `0.0` and one at the
catalogue price. `GET /waiters/orders/{code}` returns them as two entries with
the same `componentId`.

## 2. New errors

On `POST /waiters/orders`, `PUT …/add-product` and `PUT …/add-products`:

| HTTP | `error` | When | Extra fields |
|---|---|---|---|
| 400 | `option_not_offered` | The option is not on this product, or is 86'd. | `productId`, `componentId` |
| 400 | `option_group_hidden` | The option is in a group the rest of the selection hides. | `productId`, `componentId` |
| 400 | `option_group_too_few` | A visible group has fewer units than its `minSelection`. | `productId`, `componentGroupId`, `minSelection` |
| 400 | `option_group_too_many` | A visible group has more units than its `maxSelection`. | `productId`, `componentGroupId`, `minSelection`, `maxSelection` |

Every one carries a `message` that can be shown as-is. Nothing is written when
one is returned:

- **create:** no order, and no table is taken.
- **add-product:** no line.
- **add-products:** the **whole round** is refused. `index` says which entry of
  `products` is at fault.

Example:

```json
{
  "error": "option_group_too_many",
  "message": "Group \"Extras\" allows at most 2 option(s).",
  "productId": 10,
  "componentGroupId": 3,
  "minSelection": 0,
  "maxSelection": 2,
  "index": 1
}
```

**What the app should do:**

- These mean the tablet's catalogue or rule copy is out of step with the till.
- Re-pull `/waiters/products`, `/components`, `/component-groups`,
  `/product-components` and `/product-component-groups`.
- Re-open the product sheet on the faulty line so the waiter can fix it.
- Do not retry the same body: it will be refused again.

## 3. Port `priceOptions` into the vendored rules

The app vendors `component_rules.dart` verbatim. Copy the new `OptionProblem`,
`OptionPricing` and `priceOptions` from the POS file (it still has no imports
beyond `dart:convert`). Run the selection through it before sending:

- the cart shows exactly what the till will charge;
- the app refuses locally what the till would refuse.

## 4. Totals and cancelled lines

A line is `CANCELED` when the web cancels it ("delete means cancel") or when
the order is cancelled.

- **A cancelled line is not owed.** It no longer counts in `totalAmount`,
  `balanceAmount` or the tables' `totalAmount`.
- **A line cancelled after it was paid still counts.** The money was taken,
  and giving it back is a refund.
- `allPaid` is now `false` for an order whose every line was cancelled before
  any payment: nothing is owed, but nothing was settled either. An order with
  no lines at all still reads `allPaid: true`, as before.
- Cancelled lines are still returned in the order detail with their `state`,
  so the app can strike them through.

## 5. Waiter dashboard and tables

- `GET /waiters/dashboard`: `expectedCash` and `totalCash` now take the order's
  discount percentage off and skip cancelled lines. They used to ignore the
  discount, which the cashier can apply to a waiter order.
- `GET /waiters/tables`: a table's `totalAmount` (its unpaid balance) does the
  same.

## 6. Smaller changes

- `PUT …/add-product` now writes the line, its options and the order's sync
  flag in one transaction, through the same code as create and add-products.
  The line state stays `PENDING` and the response is unchanged.
- Variant lines: `unitaryDiscount` is `0` everywhere now. The waiter API
  already did this; the till now does too. Line totals did not change.

## 7. Already known, not part of this round

- The app still calls `POST /waiters/orders/{code}/pay`, which the POS no
  longer has (waiter payment was removed). It answers `404` with the JSON
  body `{"error": "Endpoint not found"}`. Remove the call.
- `chargeOnRemoval` stays read-only: there is still no way to send a charged
  removal from the app (see `waiter_api_reference.md` §7).
