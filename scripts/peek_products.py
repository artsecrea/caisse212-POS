"""Quick inspection of products + is_plannable state in sqd.db."""
import sqlite3
from pathlib import Path

DB = Path(__file__).resolve().parent.parent / "sqd.db"
con = sqlite3.connect(DB)
con.row_factory = sqlite3.Row
cur = con.cursor()

print("=" * 72)
print("Products table — relevant columns")
print("=" * 72)
schema = cur.execute("PRAGMA table_info(products)").fetchall()
for col in schema:
    if col["name"] in (
        "id",
        "name",
        "is_plannable",
        "plan_duration_minutes",
        "category_id",
        "station_id",
        "final_price",
    ):
        print(f"  {col['name']:<25} {col['type']:<10} default={col['dflt_value']}")

print("\n" + "=" * 72)
print("Currently plannable products")
print("=" * 72)
rows = cur.execute(
    "SELECT id, name, is_plannable, plan_duration_minutes, final_price "
    "FROM products WHERE is_plannable = 1 ORDER BY id"
).fetchall()
if rows:
    for r in rows:
        print(
            f"  #{r['id']:<4} {r['name']!r:<50} "
            f"duration={r['plan_duration_minutes']:<5} price={r['final_price']}"
        )
else:
    print("  (none)")

print("\n" + "=" * 72)
print("All products (first 20, by id) — for picking candidates")
print("=" * 72)
rows = cur.execute(
    "SELECT id, name, is_plannable, plan_duration_minutes, final_price "
    "FROM products ORDER BY id LIMIT 20"
).fetchall()
for r in rows:
    plan = "PLAN" if r["is_plannable"] else "    "
    dur = r["plan_duration_minutes"] or "-"
    print(
        f"  #{r['id']:<4} [{plan}] dur={dur:<4} price={r['final_price']:<8} {r['name']!r}"
    )

print(f"\nTotal products in DB: "
      f"{cur.execute('SELECT COUNT(*) FROM products').fetchone()[0]}")
con.close()
