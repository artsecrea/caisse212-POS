"""Fill the agenda with mock data so the calendar UI has something to
render. Backs up `sqd.db` first so the real data can be restored with
one command.

Usage:
    python scripts/mock_agenda.py                # backup + insert mock
    python scripts/mock_agenda.py --show         # print current mock rows
    python scripts/mock_agenda.py --restore      # restore from backup
    python scripts/mock_agenda.py --clear-only   # delete mock without
                                                 # touching backup

Strategy:
    * Backup = a byte-for-byte copy of `sqd.db` -> `sqd.db.pre-mock.bak`.
      Refuses to overwrite an existing backup unless --force given, so
      a second accidental run doesn't clobber the safety copy.
    * Mock data goes into freshly-created `orders` rows tagged with
      `source = 'MOCK'` and `code` prefixed with `MOCK-`. That marker
      makes `--clear-only` surgical (delete only mock rows) without
      having to know the parent IDs.
    * `order_products` are linked to those mock orders by `order_id`,
      so wiping the mock orders also wipes their plan rows (we do the
      child wipe explicitly first — SQLite FKs are off in this app).
"""
import argparse
import random
import shutil
import sqlite3
import sys
import uuid
from datetime import datetime, timedelta
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DB = REPO_ROOT / "sqd.db"
BAK = REPO_ROOT / "sqd.db.pre-mock.bak"

# Anchor everything around "today" so the cashier sees mock rows the
# moment they open the agenda. We spread across today + the next 2
# days so date-navigation has something to show.
NOW = datetime.now().replace(microsecond=0)
TODAY = NOW.replace(hour=0, minute=0, second=0)

# Product ids to schedule (these are the ones marked plannable by
# `mark_products_plannable.py` — using their actual durations means the
# slots look right on the calendar).
PLANNABLE = [
    # (product_id, duration_minutes)
    (96,  30),
    (101, 45),
    (109, 60),
    (115, 90),
    (124, 120),
    (158, 60),
]

# State strings drive the entry color via `_stateColor` in agenda_screen:
#   PENDING   -> blue
#   PREPARING -> orange
#   COMPLETED -> green
#   CANCELED  -> red
STATES = ['PENDING', 'PREPARING', 'COMPLETED', 'PENDING', 'PENDING']


def _iso(dt: datetime) -> str:
    """Drift stores DateTime as ISO 8601 TEXT — match its format."""
    return dt.toIsoFormat() if False else dt.isoformat()


def backup(force: bool = False) -> None:
    if not DB.exists():
        sys.exit(f"sqd.db not found at {DB}")
    if BAK.exists() and not force:
        print(f"  Backup already exists at {BAK.name} — refusing to overwrite.")
        print(f"  Re-run with --force-backup to overwrite, or --restore to use it.")
        sys.exit(1)
    shutil.copy2(DB, BAK)
    print(f"  Backed up sqd.db -> {BAK.name} ({BAK.stat().st_size} bytes)")


def restore() -> None:
    if not BAK.exists():
        sys.exit(f"No backup at {BAK} — nothing to restore.")
    shutil.copy2(BAK, DB)
    print(f"  Restored sqd.db from {BAK.name}")
    print("  Backup file kept in place. Delete it manually if you don't need it.")


def clear_mock(con) -> tuple[int, int]:
    """Delete every mock order + its order_products."""
    cur = con.cursor()
    order_ids = [r[0] for r in cur.execute(
        "SELECT id FROM orders WHERE source = 'MOCK'"
    ).fetchall()]
    if not order_ids:
        return (0, 0)
    placeholders = ','.join('?' * len(order_ids))
    op_count = cur.execute(
        f"DELETE FROM order_products WHERE order_id IN ({placeholders})",
        order_ids,
    ).rowcount
    o_count = cur.execute(
        f"DELETE FROM orders WHERE id IN ({placeholders})",
        order_ids,
    ).rowcount
    con.commit()
    return (o_count, op_count)


def pick_customer(cur) -> int | None:
    rows = cur.execute(
        "SELECT id FROM customers ORDER BY id LIMIT 1"
    ).fetchall()
    return rows[0][0] if rows else None


def pick_waiter_ids(cur, n: int = 3) -> list[int]:
    rows = cur.execute(
        "SELECT id FROM waiters WHERE is_active = 1 ORDER BY id LIMIT ?",
        (n,),
    ).fetchall()
    return [r[0] for r in rows]


def insert_mock(con) -> int:
    cur = con.cursor()
    customer_id = pick_customer(cur)
    waiter_ids = pick_waiter_ids(cur)

    # Verify the plannable products actually exist locally (the user may
    # have synced after running mark_products_plannable.py, which would
    # have wiped the flags but kept the rows).
    product_meta = {}
    for pid, _ in PLANNABLE:
        row = cur.execute(
            "SELECT name, final_price FROM products WHERE id = ?", (pid,),
        ).fetchone()
        if row:
            product_meta[pid] = {'name': row[0], 'price': row[1]}
    if not product_meta:
        sys.exit(
            "None of the plannable product ids exist in the DB.\n"
            "Run `python scripts/peek_products.py` to see what's there and\n"
            "edit PLANNABLE in this script."
        )

    # Lay slots out across 3 days × business hours. Slot start times are
    # not perfectly contiguous on purpose — they overlap a bit so the
    # column-stacking / collision-rendering can be exercised.
    slots: list[tuple[datetime, int, int]] = []  # (start, product_id, duration)
    for day_offset in range(3):
        day_anchor = TODAY + timedelta(days=day_offset)
        hour_starts = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
        # Shuffle the product list per day so we get variety
        products = list(product_meta.items())
        random.shuffle(products)
        for i, hour in enumerate(hour_starts[: len(products)]):
            pid, meta = products[i % len(products)]
            duration = next(d for p, d in PLANNABLE if p == pid)
            start = day_anchor.replace(hour=hour, minute=random.choice([0, 15, 30, 45]))
            slots.append((start, pid, duration))

    inserted_orders = 0
    for slot_idx, (start, pid, duration) in enumerate(slots):
        end = start + timedelta(minutes=duration)
        state = STATES[slot_idx % len(STATES)]
        waiter_id = random.choice(waiter_ids) if waiter_ids else None
        meta = product_meta[pid]

        # One mock order per slot (simpler than batching multiple plan
        # rows under one order — agenda doesn't care either way).
        order_code = f"MOCK-{uuid.uuid4().hex[:8].upper()}"
        cur.execute(
            """
            INSERT INTO orders
              (code, status, type, priority, persons, source, source_id,
               discount_percentage, client_id, taken_by, waiter_id, note,
               is_synced, created_at, updated_at, date)
            VALUES (?, ?, ?, 0, 1, 'MOCK', NULL, 0.0, ?, NULL, ?, ?, 0, ?, ?, ?)
            """,
            (
                order_code,
                'PENDING',
                'DINE_IN',
                customer_id,
                waiter_id,
                f"Mock agenda entry · slot {slot_idx + 1}",
                _iso(NOW),
                _iso(NOW),
                _iso(start),
            ),
        )
        order_id = cur.lastrowid

        cur.execute(
            """
            INSERT INTO order_products
              (order_id, product_id, variant_id, quantity, unitary_price,
               unitary_discount, manual_discount, unitary_tva, note, state,
               plan_start_at, plan_end_at, plan_waiter_id, updated_at)
            VALUES (?, ?, NULL, 1, ?, 0.0, 0.0, 0.0, ?, ?, ?, ?, ?, ?)
            """,
            (
                order_id,
                pid,
                meta['price'] or 0.0,
                f"Booking: {meta['name']}",
                state,
                _iso(start),
                _iso(end),
                waiter_id,
                _iso(NOW),
            ),
        )
        inserted_orders += 1

    con.commit()
    return inserted_orders


def show_mock(con) -> None:
    cur = con.cursor()
    rows = cur.execute(
        """
        SELECT o.id, o.code, op.plan_start_at, op.plan_end_at, op.state,
               op.plan_waiter_id, p.name
        FROM orders o
        JOIN order_products op ON op.order_id = o.id
        LEFT JOIN products p ON p.id = op.product_id
        WHERE o.source = 'MOCK'
        ORDER BY op.plan_start_at
        """
    ).fetchall()
    if not rows:
        print("  No mock agenda rows in the DB.")
        return
    print(f"  {len(rows)} mock row(s):")
    for r in rows:
        oid, code, start, end, state, waiter, pname = r
        print(
            f"    #{oid:<4} {code}  {start[:16]} -> {end[:16]}  "
            f"[{state:<10}] waiter={waiter}  {pname!r}"
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--restore", action="store_true",
                        help="Restore sqd.db from the .pre-mock.bak backup")
    parser.add_argument("--show", action="store_true",
                        help="Print current mock rows and exit")
    parser.add_argument("--clear-only", action="store_true",
                        help="Delete mock rows without restoring from backup")
    parser.add_argument("--force-backup", action="store_true",
                        help="Overwrite an existing backup (use with care)")
    args = parser.parse_args()

    if args.restore:
        print("=" * 68)
        print("Restoring sqd.db from backup")
        print("=" * 68)
        restore()
        return

    if args.show:
        print("=" * 68)
        print("Mock agenda rows")
        print("=" * 68)
        con = sqlite3.connect(DB)
        show_mock(con)
        con.close()
        return

    if args.clear_only:
        print("=" * 68)
        print("Deleting mock agenda rows (no backup restore)")
        print("=" * 68)
        con = sqlite3.connect(DB)
        o, p = clear_mock(con)
        con.close()
        print(f"  Deleted {o} mock orders and {p} mock plan rows.")
        return

    # Default path: backup + insert
    print("=" * 68)
    print("Backing up sqd.db")
    print("=" * 68)
    backup(force=args.force_backup)

    con = sqlite3.connect(DB)
    print("\n" + "=" * 68)
    print("Clearing any prior mock rows (idempotent re-run)")
    print("=" * 68)
    o, p = clear_mock(con)
    print(f"  Removed {o} prior mock orders, {p} prior plan rows.")

    print("\n" + "=" * 68)
    print("Inserting mock agenda rows")
    print("=" * 68)
    n = insert_mock(con)
    print(f"  Inserted {n} mock entries spread across today + 2 days.")

    print("\n" + "=" * 68)
    print("Final mock set")
    print("=" * 68)
    show_mock(con)
    con.close()

    print("\nRestore with:")
    print("  python scripts/mock_agenda.py --restore")


if __name__ == "__main__":
    main()
