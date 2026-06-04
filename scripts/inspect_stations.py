"""One-off diagnostic: where do products route in the local DB?"""
import sqlite3
import sys
from pathlib import Path

DB = Path(__file__).resolve().parent.parent / "sqd.db"
con = sqlite3.connect(DB)
con.row_factory = sqlite3.Row
cur = con.cursor()


def hr(title=""):
    print("\n" + "=" * 72)
    if title:
        print(title)
        print("-" * 72)


hr("Stations table")
rows = cur.execute("SELECT id, name FROM stations ORDER BY id").fetchall()
for r in rows:
    print(f"  id={r['id']:<5} name={r['name']!r}")
print(f"  TOTAL stations: {len(rows)}")
stations_by_id = {r["id"]: r["name"] for r in rows}

# Find Thai (case-insensitive)
thai_ids = [sid for sid, name in stations_by_id.items() if "thai" in name.lower()]
if not thai_ids:
    print("\n  *** No station with 'Thai' in its name found ***")
else:
    print(f"\n  Thai-matching station IDs: {thai_ids}")

hr("Products with stationId = a Thai station")
if thai_ids:
    qs = ",".join("?" * len(thai_ids))
    rows = cur.execute(
        f"SELECT id, name, station_id FROM products WHERE station_id IN ({qs}) ORDER BY id",
        thai_ids,
    ).fetchall()
    for r in rows:
        print(f"  prod#{r['id']:<5} stationId={r['station_id']:<3} name={r['name']!r}")
    print(f"  TOTAL: {len(rows)} products with primary stationId in Thai")

hr("productStations join rows pointing at Thai")
if thai_ids:
    qs = ",".join("?" * len(thai_ids))
    rows = cur.execute(
        f"SELECT ps.product_id, ps.station_id, p.name "
        f"FROM product_stations ps LEFT JOIN products p ON ps.product_id = p.id "
        f"WHERE ps.station_id IN ({qs}) ORDER BY ps.product_id",
        thai_ids,
    ).fetchall()
    for r in rows:
        marker = "" if r["name"] else "  <ORPHAN — product missing>"
        print(f"  prod#{r['product_id']:<5} stationId={r['station_id']:<3} name={r['name']!r}{marker}")
    print(f"  TOTAL: {len(rows)} join rows pointing at Thai")

hr("All productStations rows (full table)")
rows = cur.execute("SELECT product_id, station_id FROM product_stations ORDER BY product_id, station_id").fetchall()
for r in rows:
    sname = stations_by_id.get(r["station_id"], "<MISSING>")
    print(f"  prod#{r['product_id']:<5} -> station#{r['station_id']:<3} ({sname})")
print(f"  TOTAL: {len(rows)} join rows")

hr("Products without any station (primary AND join both empty)")
rows = cur.execute(
    "SELECT p.id, p.name, p.station_id FROM products p "
    "WHERE p.station_id IS NULL AND p.id NOT IN (SELECT product_id FROM product_stations) "
    "ORDER BY p.id"
).fetchall()
for r in rows[:30]:
    print(f"  prod#{r['id']:<5} name={r['name']!r}")
print(f"  TOTAL: {len(rows)} products with NO station at all")

hr("Recent orders (last 10) — look for the failing one")
rows = cur.execute(
    "SELECT id, code, status, type, payment_id, updated_at "
    "FROM orders ORDER BY id DESC LIMIT 10"
).fetchall()
for r in rows:
    paid = "PAID" if r["payment_id"] is not None else "unpaid"
    print(f"  ord#{r['id']:<5} code={r['code']:<15} {r['type']:<10} {r['status']:<10} {paid:<6} {r['updated_at']}")

hr("For each recent DELIVERY order: items and where they'd route")
rows = cur.execute(
    "SELECT id, code FROM orders WHERE type = 'DELIVERY' ORDER BY id DESC LIMIT 5"
).fetchall()
for o in rows:
    print(f"\n  Order {o['code']} (id={o['id']}):")
    items = cur.execute(
        "SELECT op.id, op.product_id, op.quantity, op.ticket_id, op.kds_printed_at, p.name, p.station_id "
        "FROM order_products op LEFT JOIN products p ON op.product_id = p.id "
        "WHERE op.order_id = ? ORDER BY op.id",
        (o["id"],),
    ).fetchall()
    for it in items:
        prim = stations_by_id.get(it["station_id"], "—") if it["station_id"] else "—"
        extra = [
            stations_by_id.get(r["station_id"], f"#{r['station_id']}")
            for r in cur.execute(
                "SELECT station_id FROM product_stations WHERE product_id = ?",
                (it["product_id"],),
            ).fetchall()
        ]
        routes = [prim] if prim != "—" else []
        for e in extra:
            if e not in routes:
                routes.append(e)
        if not routes:
            routes = ["<unrouted -> General>"]
        paid_marker = "PAID" if it["ticket_id"] is not None else "unpaid"
        stamp_marker = "stamped" if it["kds_printed_at"] is not None else "not-stamped"
        print(
            f"    op#{it['id']} qty={it['quantity']} {paid_marker:<6} {stamp_marker:<11} "
            f"name={it['name']!r} -> [{', '.join(routes)}]"
        )

con.close()
