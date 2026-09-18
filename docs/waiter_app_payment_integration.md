# Waiter App — Payment (DEPRECATED)

> **This document is obsolete. Waiter-side payment was removed.**
>
> All payment now happens **on the POS only**. The waiter app does **not**
> take payment: there is no `POST /waiters/orders/{code}/pay` endpoint, no
> pay-on-create (`pay`/`method`), and no "pre-paid waiter orders" setting.

## What the waiter app does instead

- Creates orders **open/unpaid** (`POST /waiters/orders`).
- Adds/removes lines, transfers tables, cancels **unpaid** orders.
- Can **see** paid state (`paid`, `balanceAmount`, `allPaid`) on the order /
  detail responses — this reflects what the **cashier** has settled on the POS.

## Where payment happens

The **cashier** settles waiter orders on the POS via the waiter settlement /
profile dialog (the normal POS payment primitives). A waiter order is
indistinguishable from a cashier order once rung up.

## See instead

- `waiter_api_reference.md` — the complete, current waiter API reference.
- `waiter_app_printing.md` — printing & order attribution.
- `waiter_app_pin_login.md` — login/discovery.
