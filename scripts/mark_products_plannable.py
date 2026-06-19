"""Mark a few products in sqd.db as plannable so the agenda screen has
something to schedule. Idempotent — re-running just overwrites the
same fields.

Usage:
    python scripts/mark_products_plannable.py            # apply defaults
    python scripts/mark_products_plannable.py --reset    # clear all flags
    python scripts/mark_products_plannable.py --show     # show current state
"""
import argparse
import sqlite3
from pathlib import Path

DB = Path(__file__).resolve().parent.parent / "sqd.db"

# (product_id, duration_minutes) — chosen to give variety across:
#   * short slots (30 min) for a quick service-like item
#   * standard (60 min)
#   * longer (90 / 120 min)
# Pick from the existing menu so we don't have to invent new rows.
# Adjust ids to whatever products you actually want to schedule —
# any id from `peek_products.py` works.
PLANNABLE = [
    (96,  30),   # 'Nems aux epinards 3pcs - Poulet'
    (101, 45),   # 'Edamame'
    (109, 60),   # 'Salade yum woon sen'
    (115, 90),   # 'Soupe Tom Yum aux Gambas'
    (124, 120),  # 'Wok Boeuf Lok Lak'
    (158, 60),   # 'Thai mango sticky rice'
]


def show(cur):
    rows = cur.execute(
        "SELECT id, name, is_plannable, plan_duration_minutes "
        "FROM products WHERE is_plannable = 1 ORDER BY id"
    ).fetchall()
    if not rows:
        print("  No plannable products.")
        return
    for r in rows:
        print(
            f"  #{r[0]:<4} dur={r[3]:<4} min  {r[1]!r}"
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reset", action="store_true",
                        help="Clear is_plannable / plan_duration_minutes on every product")
    parser.add_argument("--show", action="store_true",
                        help="Just print current plannable rows and exit")
    args = parser.parse_args()

    con = sqlite3.connect(DB)
    cur = con.cursor()

    print("=" * 68)
    if args.show:
        print("Current plannable products")
        print("=" * 68)
        show(cur)
        con.close()
        return

    if args.reset:
        print("Clearing all plannable flags")
        print("=" * 68)
        cur.execute(
            "UPDATE products SET is_plannable = 0, plan_duration_minutes = NULL"
        )
        con.commit()
        print(f"  Cleared {cur.rowcount} rows.")
        con.close()
        return

    print("Applying plannable flags")
    print("=" * 68)
    applied = 0
    skipped = 0
    for pid, duration in PLANNABLE:
        row = cur.execute(
            "SELECT name FROM products WHERE id = ?", (pid,)
        ).fetchone()
        if not row:
            print(f"  #{pid:<4} SKIPPED — product not found")
            skipped += 1
            continue
        cur.execute(
            "UPDATE products SET is_plannable = 1, plan_duration_minutes = ? "
            "WHERE id = ?",
            (duration, pid),
        )
        print(f"  #{pid:<4} dur={duration:<4} min  {row[0]!r}")
        applied += 1
    con.commit()
    print()
    print(f"  Applied: {applied}   Skipped: {skipped}")

    print("\n" + "=" * 68)
    print("Final plannable set")
    print("=" * 68)
    show(cur)
    con.close()


if __name__ == "__main__":
    main()
