# Branch `pos-hub-ready`

The version of the POS prepared for the hub. Cut on 2026-11-27 from `refactor/phase1-consolidate`, 113 commits ahead of `master`. **Behaviour is meant to be unchanged:** every commit moved code behind an interface or fixed a calculation that was listed and agreed.

## What changed

- **Phase 1 (consolidation):** one money formula (`LineAmounts`, `lineCountsInTotal`, `applyOrderDiscount`), one paid-ticket path, one order-code generator; the waiter app's option rules and prices are checked on the till; session codes carry the terminal id (`CS-YYYYMMDD-<posId>-HHMMSS-XXX`).
- **Calculation fixes:** reprint discount (VAT counted twice), external order total, cloud-push discount weights, waiter stats, a paid-then-cancelled line staying on the bill, the waiter balance with an amount split, the paid-line delete ticket amount.
- **Service layer:** 27 interfaces in `lib/domain/services`. No screen reads the database, builds a service, or calls the cloud for till data; `test/screens_use_service_interfaces_test.dart` enforces it. Map in `docs/hub_action_catalogue.md` §6.
- **Dead code removed:** the WebSocket server leftovers, unused providers and screens (each one checked unreferenced).
- **Tests:** 1,777 pass; only the two Windows updater tests fail, as on `master`. Contract tests for every interface in `test/contracts/`.

## Check on a real till before shipping

Run each against a live backend, on one till, then with a waiter tablet and a KDS:

1. **Sign-in:** tenant login, first full sync (progress bar), cashier login with and without a float rule, master password, resume of a paused session, Z opened at login (AUTO and MANUAL).
2. **Selling:** a table order with options (group rules, free quantity, removal charge), a takeaway, held order resumed, order number `#N`, kitchen ticket printed once, rush.
3. **Paying:** quick cash, payment screen by line, by quantity, by amount (split parts in any order), card, change; table freed after payment; receipt reprint.
4. **Editing after save:** remove a line (cancellation recorded, kitchen told), delete a paid line, edit and delete a ticket.
5. **Refund and exchange:** refund by receipt code (online), the refunds screen with all tills' refunds, an exchange with a difference to pay and one with money back.
6. **Session and Z:** cash in/out, pause, close with count (X printed, email report), close the Z (Z printed, sessions ended), the remote console's close and kick.
7. **Waiter app:** login, create, add products (a retried round not doubled), transfer, clear table, remove a line, call.
8. **KDS:** board live, line states, late alert, ready signal; platform orders accepted and signalled ready.
9. **Offline:** pull the network: sell and pay, then reconnect and see everything pushed (sync inspector, pending operations).
10. **Reservations:** agenda, book, move, ring up a booking.

Anything that differs from `master` on these is a regression of this branch.
