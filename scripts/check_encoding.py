"""Check which product names contain characters that thermal printers
   commonly fail to encode."""
import sqlite3
from pathlib import Path

DB = Path(__file__).resolve().parent.parent / "sqd.db"
con = sqlite3.connect(DB)
con.row_factory = sqlite3.Row
cur = con.cursor()

# Inspect order 79 specifically — the failing one
print("=" * 72)
print("Order 79 (948A5007) raw items — byte-level")
print("=" * 72)
for r in cur.execute(
    "SELECT op.id, p.name FROM order_products op "
    "JOIN products p ON op.product_id = p.id "
    "WHERE op.order_id = 79 ORDER BY op.id"
):
    name = r["name"]
    print(f"\n  op#{r['id']:<4} {name!r}")
    non_ascii = [(i, ch, hex(ord(ch))) for i, ch in enumerate(name) if ord(ch) > 127]
    if non_ascii:
        print(f"      Non-ASCII chars:")
        for i, ch, hx in non_ascii:
            print(f"        pos {i:<3} char {ch!r:<6} codepoint {hx}")
        # Try encoding with the various code pages
        for cp in ("cp437", "cp850", "cp858", "cp1252", "cp864"):
            try:
                b = name.encode(cp)
                print(f"      {cp:<8} encode OK → {b!r}")
            except UnicodeEncodeError as e:
                print(f"      {cp:<8} FAILS → {e}")

# Survey all Thai-station products for the same character class
print("\n" + "=" * 72)
print("All Thai-station product names containing 'œ' / 'Œ' / 'ß'")
print("=" * 72)
thai_products = cur.execute(
    "SELECT id, name FROM products WHERE station_id = 7 ORDER BY id"
).fetchall()
suspects = []
for r in thai_products:
    name = r["name"]
    if any(ch in name for ch in "œŒßÿ"):
        suspects.append((r["id"], name))
for pid, name in suspects:
    print(f"  prod#{pid:<5} {name!r}")
print(f"  TOTAL: {len(suspects)} products with œ/Œ/ß/ÿ in Thai station")

# Cross-check: do Sushi/boisson stations have the same chars?
print("\n" + "=" * 72)
print("Same character check across other stations")
print("=" * 72)
for sid, sname in [(8, "Sushi"), (10, "boisson")]:
    rows = cur.execute(
        "SELECT id, name FROM products WHERE station_id = ? ORDER BY id", (sid,)
    ).fetchall()
    bad = [(r["id"], r["name"]) for r in rows if any(ch in r["name"] for ch in "œŒßÿ")]
    print(f"\n  Station {sname} (id={sid}): {len(bad)}/{len(rows)} products with œ/Œ/ß/ÿ")
    for pid, name in bad[:10]:
        print(f"    prod#{pid} {name!r}")

con.close()
