# Waiter API — Error Reference

Every error the waiter app can receive from the POS's waiter endpoints, so the
client can handle each one deliberately. Companion to `waiter_api_reference.md`.

---

## 1. Error shape

All errors are JSON with at least an `error` field:

```json
{ "error": "<code_or_message>" }
```

- Newer errors also carry a human-readable **`message`** you can show directly:
  ```json
  { "error": "session_paused", "message": "The cash session is paused. Ask the cashier to resume it before taking orders." }
  ```
- **`500`** responses add `details` (the server exception string) — for logs,
  not for users.

> **How to match:** branch on the **HTTP status + the `error` value together**.
> Some `error` values are machine codes (`snake_case`, stable) and some are
> human sentences (older endpoints). Prefer the machine codes where present;
> for the sentence ones, match the exact string. Where a `message` is present,
> it's safe to surface to the user as-is.

---

## 2. Quick reference — machine codes

| `error` | HTTP | Endpoint(s) | New? | Has `message`? |
|---|---|---|---|---|
| `no_open_session` | 409 | `POST /waiters/orders` | ✅ | ✅ |
| `session_paused` | 409 | `POST /waiters/orders` | ✅ | ✅ |
| `table_taken_by_other_waiter` | 409 | `POST /waiters/orders` | ✅ | ✅ |
| `cannot_remove_paid_line` | 400 | `DELETE …/products/{opId}` | ✅ | ✅ |
| `order_has_payments` | 400 | `POST …/cancel` | ✅ | ✅ |
| `target_table_occupied` | 400 | `POST …/transfer-table` | ✅ | ✅ |
| `pin_required` | 400 | `POST /waiters/login` | — | — |
| `invalid_pin` | 403 | `POST /waiters/login` | — | — |
| `login_failed` | 500 | `POST /waiters/login` | — | — |
| `printing_disabled` | 503 | `POST …/print` | — | — |
| `option_not_offered` | 400 | create, `add-product`, `add-products` | ✅ | ✅ |
| `option_too_many` | 400 | create, `add-product`, `add-products` | ✅ | ✅ |
| `option_group_hidden` | 400 | create, `add-product`, `add-products` | ✅ | ✅ |
| `option_group_too_few` | 400 | create, `add-product`, `add-products` | ✅ | ✅ |
| `option_group_too_many` | 400 | create, `add-product`, `add-products` | ✅ | ✅ |

All other errors use a human sentence as the `error` value (see per-endpoint
tables below).

---

## 3. Cross-cutting errors (any endpoint)

| HTTP | `error` | When | Client action |
|---|---|---|---|
| 403 | `Invalid or missing server password` | A server password is configured and the request's `X-Server-Password` header is missing/wrong. | Prompt for / re-send the server password. Applies to **every** endpoint except `GET /health`. |
| 404 | `Endpoint not found` | Unknown path/method. | Fix the request; check the base URL/path. |
| 500 | `Internal server error` / `Failed to …` (+`details`) | Unhandled server exception. | Show a generic "server error, try again"; log `details`. |
| — | *(network failure: timeout / connection refused)* | POS unreachable (Wi-Fi drop, server not started, wrong IP). | "Can't reach POS — check Wi-Fi"; offer the manual-IP fallback. |

---

## 4. Session gate (NEW) — `POST /waiters/orders`

Order creation now requires a cash session that is **open and not paused**.
The session's live status is read from the POS at request time.

| HTTP | `error` | `message` | When | Client action |
|---|---|---|---|---|
| 409 | `no_open_session` | "No cash session is open. …" | No session is open (app just launched, or the cashier ended the session). | Block the "create order" UI; show "Waiting for the cashier to open a session." Poll `GET /waiters/tables` (cheap) or retry on user action. |
| 409 | `session_paused` | "The cash session is paused. …" | The cashier paused the session. | Block creation; show "Session paused — ask the cashier to resume." |

> **Only creation is gated.** Browsing (`tables`, `orders`, `dashboard`,
> catalog) and editing an already-open order (`add-product`, remove, cancel,
> transfer, print) are **not** blocked by the session gate. Note the read
> endpoints `dashboard` and `orders` are still *scoped* to the current session
> (empty when none is open) — that's not an error, just an empty result.

---

## 5. Per-endpoint errors

### `POST /waiters/login`
| HTTP | `error` | When |
|---|---|---|
| 400 | `pin_required` | Body missing `pin` (or empty after trim). |
| 403 | `invalid_pin` | Unknown PIN, inactive waiter, **or** the PIN doesn't match the selected `waiterId` profile. Deliberately ambiguous — don't try to disambiguate. |
| 500 | `login_failed` | Server exception (`details` present). |

### `GET /waiters/profiles`
| HTTP | `error` | When |
|---|---|---|
| 500 | `Failed to fetch profiles` | Server exception. |

### `GET /waiters/dashboard`
| HTTP | `error` | When |
|---|---|---|
| 400 | `waiterId is required` | Missing `waiterId` query param. |
| 400 | `Invalid waiterId` | `waiterId` not an integer. |
| 500 | `Failed to get dashboard` | Server exception. |

### Catalog: `GET /waiters/products` · `/categories` · `/components` · `/component-groups` · `/product-components`
| HTTP | `error` | When |
|---|---|---|
| 500 | `Failed to fetch <thing>` | Server exception. (No input params to validate.) |

### `GET /waiters/product-variants`
| HTTP | `error` | When |
|---|---|---|
| 400 | `productId is required` | Missing `productId`. |
| 400 | `Invalid productId` | Not an integer. |
| 404 | `Product not found` | No product with that id. |
| 500 | `Failed to fetch product variants` | Server exception. |

### `GET /waiters/tables`
| HTTP | `error` | When |
|---|---|---|
| 400 | `waiterId is required` | Missing `waiterId`. |
| 400 | `Invalid waiterId` | Not an integer. |
| 500 | `Failed to fetch tables` | Server exception. |

### `GET /waiters/orders`
| HTTP | `error` | When |
|---|---|---|
| 400 | `waiterId is required` | Missing `waiterId`. |
| 400 | `Invalid waiterId` | Not an integer. |
| 500 | `Failed to fetch orders` | Server exception. |

### `GET /waiters/orders/{code}`
| HTTP | `error` | When |
|---|---|---|
| 400 | `waiterId is required` | Missing `waiterId`. |
| 404 | `Order not found` | No order with that code. |
| 403 | `Not authorized to view this order` | Order's `waiter_id` ≠ `waiterId`. |
| 500 | `Failed to fetch order` | Server exception. |

### `POST /waiters/orders` (create)
| HTTP | `error` | When |
|---|---|---|
| 400 | `waiterId is required` | Missing `waiterId`. |
| 409 | `no_open_session` / `session_paused` | See §4. |
| 400 | `tableId is required for DINE_IN orders` | `type=DINE_IN` without `tableId`. |
| 400 | `Invalid or inactive waiter` | Waiter doesn't exist or is inactive. |
| 400 | `Table not found` | `tableId` doesn't exist. |
| 403 | `Waiter not assigned to this table's area` | Area-restricted waiter targeting a table outside their areas. |
| 409 | `table_taken_by_other_waiter` *(+message)* | The target table already has an **active** order owned by someone else (another waiter, or a cashier order). To add to your own open order, use `PUT …/add-product`. |
| 400 | `option_not_offered` / `option_too_many` / `option_group_hidden` / `option_group_too_few` / `option_group_too_many` *(+message)* | A line's options are not a selection the till accepts. Carries `productId` and `componentId` or `componentGroupId` (+ `minSelection` / `maxSelection`). Nothing is written. See `waiter_app_changes_2026-11.md` §2. |
| 500 | `Failed to create order` | Server exception. |

### `PUT /waiters/orders/{code}/add-product`
| HTTP | `error` | When |
|---|---|---|
| 400 | `waiterId and productId are required` | Missing field(s). |
| 404 | `Order not found` | No such order. |
| 403 | `Not authorized to modify this order` | Not the owner. |
| 400 | `Product not found` | `productId` doesn't exist. |
| 400 | `option_not_offered` / `option_group_hidden` / `option_group_too_few` / `option_group_too_many` *(+message)* | As for create. Nothing is written. On `add-products` the whole round is refused and `index` names the faulty entry. |
| 500 | `Failed to add product` | Server exception. |

### `DELETE /waiters/orders/{code}/products/{opId}` (remove line) — NEW
| HTTP | `error` | When |
|---|---|---|
| 400 | `waiterId and a valid line id are required` | Missing `waiterId` query / bad `opId`. |
| 404 | `Order not found` | No such order. |
| 403 | `Not authorized to modify this order` | Not the owner. |
| 404 | `Line not found on this order` | `opId` isn't a line on this order. |
| 400 | `cannot_remove_paid_line` *(+message)* | The line is already paid (on a ticket). Refund is cashier-side. |
| 500 | `Failed to remove line` | Server exception. |

### `POST /waiters/orders/{code}/cancel` — NEW
| HTTP | `error` | When |
|---|---|---|
| 400 | `waiterId is required` | Missing `waiterId`. |
| 404 | `Order not found` | No such order. |
| 403 | `Not authorized to cancel this order` | Not the owner. |
| 400 | `order_has_payments` *(+message)* | Some line is already paid — must be voided by the cashier. |
| 500 | `Failed to cancel order` | Server exception. |

### `POST /waiters/orders/{code}/transfer-table` — NEW
| HTTP | `error` | When |
|---|---|---|
| 400 | `waiterId and tableId are required` | Missing field(s). |
| 404 | `Order not found` | No such order. |
| 403 | `Not authorized to move this order` | Not the owner. |
| 404 | `Target table not found` | `tableId` doesn't exist. |
| 403 | `Not allowed to use the target table` | Area-restricted waiter targeting a table outside their areas. |
| 400 | `target_table_occupied` *(+message)* | Target table already has another order. |
| 500 | `Failed to transfer table` | Server exception. |

### `POST /waiters/tables/{tableId}/clear` — NEW
| HTTP | `error` | When |
|---|---|---|
| 400 | `waiterId and a valid tableId are required` | Missing `waiterId` / bad `tableId`. |
| 404 | `Table not found` | No such table. |
| 403 | `Not allowed to clear this table` | Area-restricted waiter, table outside their areas. |
| 500 | `Failed to clear table` | Server exception. |

### `POST /waiters/orders/{code}/print`
| HTTP | `error` | When |
|---|---|---|
| 400 | `waiterId is required` | Missing `waiterId`. |
| 404 | `Order not found` | No such order. |
| 403 | `Not authorized to print this order` | Not the owner. |
| 503 | `printing_disabled` (`{printed:false}`) | Master printing is off / printer offline. |
| 500 | `Failed to print` / `Failed to load order` | Server exception. |

---

## 6. Recommended client handling

- **409 `no_open_session` / `session_paused`** — the two most important to
  handle well. Don't treat them as hard failures: disable order creation, show
  the `message`, and let the waiter retry once the cashier opens/resumes. Keep
  the cart intact so nothing is lost.
- **403 ownership** (`Not authorized to …`) — hide edit/pay/print controls for
  orders the waiter doesn't own; if one slips through, refresh the list.
- **404 `Order not found` / `Table not found`** — the local cache is stale;
  re-fetch `orders`/`tables`.
- **409 `table_taken_by_other_waiter`** — the table already has an active
  order owned by someone else. Show the `message`. If it's the waiter's *own*
  order, the app should route to that order and `add-product` instead of
  creating a new one.
- **400 business rules** (`cannot_remove_paid_line`, `order_has_payments`,
  `target_table_occupied`) — show the `message`; the action is legitimately
  blocked, so don't retry blindly.
- **400 validation** (`… is required`, `Invalid …`) — a client bug; fix the
  request. Shouldn't reach production UI.
- **503 `printing_disabled`** — inform the waiter the receipt/ticket didn't
  print; the underlying order action (if any) still succeeded.
- **500** — generic retry; log `details`.
- **Network failure** — "Can't reach POS"; offer manual IP + retry.

> Match on the **machine codes** in §2 first (they're stable). The sentence-style
> `error` strings on older endpoints may be reworded over time — prefer matching
> those on **HTTP status** and treat the sentence as a fallback label.
