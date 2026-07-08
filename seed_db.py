#!/usr/bin/env python3
"""
caisse212 POS — SQLite seed script
Usage:
  python seed_db.py --domain restaurant
  python seed_db.py --domain patisserie
  python seed_db.py --domain clothes
  python seed_db.py --domain grocery
  python seed_db.py --domain cafe
  python seed_db.py --clear               # wipe data only (keep schema)
  python seed_db.py --domain restaurant --db path/to/sqd.db

Default DB:  C:/Users/Test/Documents/sqd.db
Credentials: username admin / caissier  — password admin123
"""

import argparse
import os
import sqlite3
import sys
from datetime import datetime

NOW = datetime.now().strftime("%Y-%m-%dT%H:%M:%S.000")

# ---------------------------------------------------------------------------
# bcrypt — falls back to a pre-hashed constant if the library is absent
# ---------------------------------------------------------------------------
try:
    import bcrypt as _bcrypt

    def hash_password(plain: str) -> str:
        return _bcrypt.hashpw(plain.encode(), _bcrypt.gensalt(rounds=10)).decode()

except ImportError:
    # Pre-hashed "admin123" cost-10.
    # Regen: python -c "import bcrypt; print(bcrypt.hashpw(b'admin123', bcrypt.gensalt(10)).decode())"
    _PRECOMPUTED = "$2b$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi"
    print("[WARN] 'bcrypt' not installed — using a pre-computed hash for 'admin123'.")
    print("       pip install bcrypt")

    def hash_password(plain: str) -> str:  # noqa: F811
        return _PRECOMPUTED


# ---------------------------------------------------------------------------
# Unsplash image URLs  (400×400, cropped)
# ---------------------------------------------------------------------------
def _u(photo_id: str) -> str:
    return f"https://images.unsplash.com/photo-{photo_id}?w=400&h=400&fit=crop&auto=format"


IMG = {
    # ── starters / salads ──
    "soup":         _u("1547592166-23ac45744acd"),
    "salad":        _u("1512621776951-a57141f2eefd"),
    "charcuterie":  _u("1544025162-d76538b4e259"),
    "bruschetta":   _u("1572441711-c8db38173d04"),
    "escargots":    _u("1509042239860-f550ce710b93"),   # fallback espresso look
    # ── mains ──
    "chicken":      _u("1598103442097-8b74394b95c8"),
    "tajine":       _u("1574484284002-091bf62376b6"),
    "couscous":     _u("1574484284002-091bf62376b6"),
    "lasagna":      _u("1555949258-eb67b1ef0ceb"),
    "pasta":        _u("1555949258-eb67b1ef0ceb"),
    # ── fish / seafood ──
    "fish":         _u("1519708227418-c8fd9a32b7a2"),
    "salmon":       _u("1519708227418-c8fd9a32b7a2"),
    "sea_bass":     _u("1519708227418-c8fd9a32b7a2"),
    "shrimp":       _u("1563245372-f21724e3856d"),
    # ── grilled ──
    "steak":        _u("1558030006-450675393462"),
    "grill":        _u("1544025162-d76538b4e259"),
    "lamb":         _u("1544025162-d76538b4e259"),
    "brochettes":   _u("1529530765808-44d0c4a30b21"),
    "burger":       _u("1568901346375-23c9450c58cd"),
    # ── desserts ──
    "creme_brulee": _u("1488477181946-6428a0291777"),
    "mousse":       _u("1578985545062-69928b1d9587"),
    "tart":         _u("1565958011703-44f9829ba187"),
    "profiteroles": _u("1551529934-8df3a8f05a71"),
    "cake":         _u("1578985545062-69928b1d9587"),
    "opera_cake":   _u("1571115177098-24ec42ed204d"),
    "mille_feuille":_u("1603532648955-039310d9ed75"),
    "fraisier":     _u("1565958011703-44f9829ba187"),
    "cheesecake":   _u("1533134242443-d4fd215305ad"),
    "brownie":      _u("1564355808539-22fda35bed7e"),
    "muffin":       _u("1558401391-7899b2d7a784"),
    "cookie":       _u("1499636136210-6f4ee915583e"),
    # ── drinks (hot) ──
    "espresso":     _u("1509042239860-f550ce710b93"),
    "cappuccino":   _u("1572442388796-11668a67e53d"),
    "latte":        _u("1461023058943-07fcbe16d735"),
    "hot_choc":     _u("1542990253-0d0f5be5f0ed"),
    "tea":          _u("1597318181409-cf64d0b5d8a2"),
    "chai":         _u("1597318181409-cf64d0b5d8a2"),
    # ── drinks (cold) ──
    "water":        _u("1548839140-29a749e1cf4d"),
    "soda":         _u("1554866585-cd94860890b7"),
    "juice":        _u("1621506289937-a8e4df240d0b"),
    "smoothie":     _u("1553530666-ba11a7da3888"),
    "lemonade":     _u("1621506289937-a8e4df240d0b"),
    "ice_tea":      _u("1499638673689-79a0b5115d87"),
    "wine":         _u("1510812431401-41d2bd2722f3"),
    "cocktail":     _u("1551538827-9c037cb4f32a"),
    # ── bakery / viennoiseries ──
    "croissant":    _u("1555507036-ab1f4038808a"),
    "pain_choc":    _u("1549931319-a545dcf3bc7a"),
    "chausson":     _u("1555507036-ab1f4038808a"),
    "kouign":       _u("1555507036-ab1f4038808a"),
    "cinnamon":     _u("1592985949-c89efbcacb90"),
    "macaron":      _u("1558326567-98ae2405596b"),
    "baguette":     _u("1509440159596-0249088772ff"),
    "bread":        _u("1509440159596-0249088772ff"),
    "brioche":      _u("1509440159596-0249088772ff"),
    # ── sandwichs / snacks ──
    "sandwich":     _u("1528735602780-2552fd46c7af"),
    "croque":       _u("1528735602780-2552fd46c7af"),
    "club":         _u("1528735602780-2552fd46c7af"),
    "panini":       _u("1528735602780-2552fd46c7af"),
    "toast_avo":    _u("1603046891726-36bfd957e0bf"),
    # ── breakfast ──
    "breakfast":    _u("1533089860892-a7c6f0a88666"),
    "omelette":     _u("1525755662778-989d0524087e"),
    "pancakes":     _u("1528207776546-365bb710ee93"),
    # ── clothes ──
    "men_shirt":    _u("1602810318383-e386cc2a3ccf"),
    "men_pants":    _u("1490481651871-ab68de25d43d"),
    "men_jacket":   _u("1551488831-00ddcb6c6bd3"),
    "men_pull":     _u("1490481651871-ab68de25d43d"),
    "women_dress":  _u("1515372399756-5f9462ade9b4"),
    "women_top":    _u("1445205170230-053b83016050"),
    "women_jeans":  _u("1445205170230-053b83016050"),
    "women_skirt":  _u("1494790108377-be9c29b29330"),
    "women_coat":   _u("1539109136881-3be0616acf4b"),
    "kids":         _u("1471286174890-9c112ffaa5f5"),
    "shoes":        _u("1542291026-7eec264c27ff"),
    "boots":        _u("1542291026-7eec264c27ff"),
    "bag":          _u("1553062407-98eeb64c6a62"),
    "belt":         _u("1553062407-98eeb64c6a62"),
    "scarf":        _u("1490481651871-ab68de25d43d"),
    "sport":        _u("1461896836374-0b55d8e4bca3"),
    "sale":         _u("1607082348823-ab4dfc97ae80"),
    # ── grocery ──
    "vegetables":   _u("1540420773420-3366772f4999"),
    "tomato":       _u("1540420773420-3366772f4999"),
    "fruits":       _u("1619566636858-adf3ef46400b"),
    "dairy":        _u("1550583724-b2692b85b150"),
    "milk":         _u("1550583724-b2692b85b150"),
    "meat":         _u("1607623814075-e51df1bdc82f"),
    "chicken_raw":  _u("1607623814075-e51df1bdc82f"),
    "grocery_dry":  _u("1474979266404-7eaacbcd87c5"),
    "oil":          _u("1474979266404-7eaacbcd87c5"),
    "hygiene":      _u("1584308666744-24d5c474f2ae"),
    "frozen":       _u("1621501103258-d00b434b2b53"),
    "pizza_frozen": _u("1513104890138-7c749659a591"),
}

# ---------------------------------------------------------------------------
# Tables cleared on --clear (FK-safe order)
# ---------------------------------------------------------------------------
CLEAR_ORDER = [
    "order_product_components", "order_products", "payments", "transactions",
    "tickets", "orders", "cash_sessions", "pending_sync_operations",
    "order_logs", "activity_logs", "notes", "product_variants",
    "product_components", "product_stations", "waiter_areas", "waiters",
    "products", "categories", "components", "component_groups",
    "area_tables", "areas", "stations", "customers", "commercials", "users",
]


def clear_data(conn: sqlite3.Connection):
    conn.execute("PRAGMA foreign_keys = OFF;")
    cur = conn.cursor()
    for table in CLEAR_ORDER:
        try:
            cur.execute(f"DELETE FROM {table};")
            print(f"  cleared {table}")
        except sqlite3.OperationalError as e:
            print(f"  skip {table}: {e}")
    conn.execute("PRAGMA foreign_keys = ON;")
    conn.commit()
    print("All data cleared.")


# ---------------------------------------------------------------------------
# Insert helpers
# ---------------------------------------------------------------------------

def insert_user(cur, uid, username, first, last, role):
    pwd = hash_password("admin123")
    cur.execute(
        """INSERT OR IGNORE INTO users
           (id, username, password, first_name, last_name, type, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (uid, username, pwd, first, last, role, NOW, NOW),
    )


def insert_category(cur, cid, name, color, order_n, image_url=None):
    cur.execute(
        """INSERT OR IGNORE INTO categories
           (id, name, color, display_order, image_url, is_active, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, 1, ?, ?)""",
        (cid, name, color, order_n, image_url, NOW, NOW),
    )


def insert_product(cur, pid, name, price, cat_id, color=None, image_url=None, description=None):
    final = round(price, 2)
    cur.execute(
        """INSERT OR IGNORE INTO products
           (id, name, price, final_price, category_id, color, image_url, description,
            tva_amount, discount_amount, is_active, is_variant, is_plannable,
            created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0.0, 0.0, 1, 0, 0, ?, ?)""",
        (pid, name, final, final, cat_id, color, image_url, description, NOW, NOW),
    )


def insert_area(cur, aid, name, description=None):
    cur.execute(
        """INSERT OR IGNORE INTO areas (id, name, description, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?)""",
        (aid, name, description, NOW, NOW),
    )


def insert_table(cur, tid, name, area_id, capacity=4):
    cur.execute(
        """INSERT OR IGNORE INTO area_tables
           (id, name, area_id, capacity, table_state, created_at, updated_at)
           VALUES (?, ?, ?, ?, 'AVAILABLE', ?, ?)""",
        (tid, name, area_id, capacity, NOW, NOW),
    )


def insert_waiter(cur, wid, first, last, pin):
    cur.execute(
        """INSERT OR IGNORE INTO waiters
           (id, first_name, last_name, pin, is_active, created_at, updated_at)
           VALUES (?, ?, ?, ?, 1, ?, ?)""",
        (wid, first, last, pin, NOW, NOW),
    )


def insert_station(cur, sid, name, description=None):
    cur.execute(
        """INSERT OR IGNORE INTO stations (id, name, description, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?)""",
        (sid, name, description, NOW, NOW),
    )


# ---------------------------------------------------------------------------
# Common seed
# ---------------------------------------------------------------------------

def seed_common_users(cur):
    insert_user(cur, 1, "admin",    "Admin",    "Principal", "admin")
    insert_user(cur, 2, "caissier", "Caissier", "Dupont",    "cashier")


# ---------------------------------------------------------------------------
# RESTAURANT
# ---------------------------------------------------------------------------

def seed_restaurant(cur):
    print("Seeding: Restaurant")
    seed_common_users(cur)

    insert_station(cur, 1, "Cuisine chaude", "Plats, grillades")
    insert_station(cur, 2, "Cuisine froide", "Entrées, salades")
    insert_station(cur, 3, "Bar",            "Boissons & desserts")

    cats = [
        (1, "Entrées",          "#FF8C00", 1, IMG["soup"]),
        (2, "Plats principaux", "#B22222", 2, IMG["chicken"]),
        (3, "Poissons",         "#4169E1", 3, IMG["fish"]),
        (4, "Grillades",        "#8B0000", 4, IMG["steak"]),
        (5, "Desserts",         "#FF69B4", 5, IMG["cake"]),
        (6, "Boissons",         "#2E8B57", 6, IMG["juice"]),
        (7, "Salades",          "#228B22", 7, IMG["salad"]),
    ]
    for c in cats:
        insert_category(cur, *c)

    # (id, name, price, cat_id, color, image_url)
    products = [
        # Entrées
        (1,  "Soupe de légumes",          22.00, 1, "#FF8C00", IMG["soup"]),
        (2,  "Salade niçoise",             38.00, 1, "#FF8C00", IMG["salad"]),
        (3,  "Assiette de charcuterie",    55.00, 1, "#FF8C00", IMG["charcuterie"]),
        (4,  "Bruschetta tomates",         30.00, 1, "#FF8C00", IMG["bruschetta"]),
        (5,  "Escargots bourguignons",     65.00, 1, "#FF8C00", IMG["escargots"]),
        # Plats
        (6,  "Poulet rôti aux herbes",     95.00, 2, "#B22222", IMG["chicken"]),
        (7,  "Tajine bœuf aux olives",    110.00, 2, "#B22222", IMG["tajine"]),
        (8,  "Couscous royal",            120.00, 2, "#B22222", IMG["couscous"]),
        (9,  "Lasagnes maison",            88.00, 2, "#B22222", IMG["lasagna"]),
        (10, "Pasta carbonara",            78.00, 2, "#B22222", IMG["pasta"]),
        # Poissons
        (11, "Sole meunière",             130.00, 3, "#4169E1", IMG["fish"]),
        (12, "Saumon grillé",             125.00, 3, "#4169E1", IMG["salmon"]),
        (13, "Loup de mer en papillote",  145.00, 3, "#4169E1", IMG["sea_bass"]),
        (14, "Crevettes sautées à l'ail", 115.00, 3, "#4169E1", IMG["shrimp"]),
        # Grillades
        (15, "Entrecôte 250g",            145.00, 4, "#8B0000", IMG["steak"]),
        (16, "Côtelettes d'agneau",       135.00, 4, "#8B0000", IMG["lamb"]),
        (17, "Brochettes mixtes",         105.00, 4, "#8B0000", IMG["brochettes"]),
        (18, "Hamburger maison",           85.00, 4, "#8B0000", IMG["burger"]),
        # Desserts
        (19, "Crème brûlée",              42.00, 5, "#FF69B4", IMG["creme_brulee"]),
        (20, "Mousse au chocolat",         38.00, 5, "#FF69B4", IMG["mousse"]),
        (21, "Tarte tatin",               45.00, 5, "#FF69B4", IMG["tart"]),
        (22, "Profiteroles",              48.00, 5, "#FF69B4", IMG["profiteroles"]),
        # Boissons
        (23, "Eau minérale 50cl",          12.00, 6, "#2E8B57", IMG["water"]),
        (24, "Coca-Cola 33cl",             18.00, 6, "#2E8B57", IMG["soda"]),
        (25, "Jus d'orange pressé",        28.00, 6, "#2E8B57", IMG["juice"]),
        (26, "Café express",               15.00, 6, "#2E8B57", IMG["espresso"]),
        (27, "Thé à la menthe",            12.00, 6, "#2E8B57", IMG["tea"]),
        (28, "Bouteille de vin 75cl",      95.00, 6, "#2E8B57", IMG["wine"]),
        # Salades
        (29, "Salade César",               52.00, 7, "#228B22", IMG["salad"]),
        (30, "Salade grecque",             48.00, 7, "#228B22", IMG["salad"]),
    ]
    for p in products:
        insert_product(cur, *p)

    insert_area(cur, 1, "Salle principale", "Intérieur climatisé")
    insert_area(cur, 2, "Terrasse",          "Espace extérieur")
    insert_area(cur, 3, "Salon VIP",         "Privé — réservation requise")

    tables = [
        (1,  "T01", 1, 2), (2,  "T02", 1, 4), (3,  "T03", 1, 4),
        (4,  "T04", 1, 4), (5,  "T05", 1, 6), (6,  "T06", 1, 6),
        (7,  "T07", 1, 2), (8,  "T08", 1, 4),
        (9,  "TR1", 2, 2), (10, "TR2", 2, 4), (11, "TR3", 2, 4),
        (12, "TR4", 2, 6), (13, "TR5", 2, 2),
        (14, "VIP1", 3, 8), (15, "VIP2", 3, 10), (16, "VIP3", 3, 12),
    ]
    for t in tables:
        insert_table(cur, *t)

    insert_waiter(cur, 1, "Karim",   "Benali",    "1111")
    insert_waiter(cur, 2, "Sara",    "Moumou",    "2222")
    insert_waiter(cur, 3, "Youssef", "Alami",     "3333")
    insert_waiter(cur, 4, "Nadia",   "Cherkaoui", "4444")
    print("  Restaurant seed complete.")


# ---------------------------------------------------------------------------
# PATISSERIE
# ---------------------------------------------------------------------------

def seed_patisserie(cur):
    print("Seeding: Patisserie / Boulangerie")
    seed_common_users(cur)

    insert_station(cur, 1, "Laboratoire", "Préparation")
    insert_station(cur, 2, "Four",         "Cuisson")
    insert_station(cur, 3, "Bar",          "Boissons")

    cats = [
        (1, "Gâteaux",           "#FF1493", 1, IMG["cake"]),
        (2, "Viennoiseries",     "#DAA520", 2, IMG["croissant"]),
        (3, "Tartes & Quiches",  "#CD853F", 3, IMG["tart"]),
        (4, "Macarons",          "#EE82EE", 4, IMG["macaron"]),
        (5, "Boissons chaudes",  "#8B4513", 5, IMG["cappuccino"]),
        (6, "Jus & Smoothies",   "#FF6347", 6, IMG["smoothie"]),
        (7, "Sandwichs",         "#F4A460", 7, IMG["sandwich"]),
        (8, "Brioches & Pains",  "#DEB887", 8, IMG["baguette"]),
    ]
    for c in cats:
        insert_category(cur, *c)

    products = [
        # Gâteaux
        (1,  "Opéra",                      55.00, 1, "#FF1493", IMG["opera_cake"]),
        (2,  "Forêt noire",                 58.00, 1, "#FF1493", IMG["cake"]),
        (3,  "Mille-feuille",               45.00, 1, "#FF1493", IMG["mille_feuille"]),
        (4,  "Entremets framboise",         65.00, 1, "#FF1493", IMG["fraisier"]),
        (5,  "Tarte chocolat (part)",       40.00, 1, "#FF1493", IMG["cake"]),
        (6,  "Fraisier",                    52.00, 1, "#FF1493", IMG["fraisier"]),
        # Viennoiseries
        (7,  "Croissant pur beurre",        12.00, 2, "#DAA520", IMG["croissant"]),
        (8,  "Pain au chocolat",            14.00, 2, "#DAA520", IMG["pain_choc"]),
        (9,  "Chausson aux pommes",         15.00, 2, "#DAA520", IMG["chausson"]),
        (10, "Kouign-amann",                18.00, 2, "#DAA520", IMG["kouign"]),
        (11, "Cinnamon roll",               22.00, 2, "#DAA520", IMG["cinnamon"]),
        # Tartes
        (12, "Tarte citron meringuée",      38.00, 3, "#CD853F", IMG["tart"]),
        (13, "Tarte aux fraises",           42.00, 3, "#CD853F", IMG["tart"]),
        (14, "Quiche lorraine",             35.00, 3, "#CD853F", IMG["tart"]),
        (15, "Tarte aux pommes",            36.00, 3, "#CD853F", IMG["tart"]),
        # Macarons
        (16, "Macaron framboise",           12.00, 4, "#EE82EE", IMG["macaron"]),
        (17, "Macaron chocolat",            12.00, 4, "#EE82EE", IMG["macaron"]),
        (18, "Macaron caramel-beurre salé", 12.00, 4, "#EE82EE", IMG["macaron"]),
        (19, "Boîte 6 macarons",            65.00, 4, "#EE82EE", IMG["macaron"]),
        (20, "Boîte 12 macarons",          120.00, 4, "#EE82EE", IMG["macaron"]),
        # Boissons chaudes
        (21, "Café express",                15.00, 5, "#8B4513", IMG["espresso"]),
        (22, "Cappuccino",                  22.00, 5, "#8B4513", IMG["cappuccino"]),
        (23, "Latte",                       24.00, 5, "#8B4513", IMG["latte"]),
        (24, "Chocolat chaud",              22.00, 5, "#8B4513", IMG["hot_choc"]),
        (25, "Thé vert à la menthe",        15.00, 5, "#8B4513", IMG["tea"]),
        # Jus
        (26, "Jus d'orange pressé",         25.00, 6, "#FF6347", IMG["juice"]),
        (27, "Smoothie fraise-banane",       30.00, 6, "#FF6347", IMG["smoothie"]),
        (28, "Citronnade maison",            22.00, 6, "#FF6347", IMG["lemonade"]),
        # Sandwichs
        (29, "Club sandwich",               38.00, 7, "#F4A460", IMG["club"]),
        (30, "Croque-monsieur",             30.00, 7, "#F4A460", IMG["croque"]),
        # Pains
        (31, "Baguette tradition",          10.00, 8, "#DEB887", IMG["baguette"]),
        (32, "Pain de campagne",            18.00, 8, "#DEB887", IMG["bread"]),
        (33, "Brioche individuelle",        15.00, 8, "#DEB887", IMG["brioche"]),
    ]
    for p in products:
        insert_product(cur, *p)

    insert_area(cur, 1, "Salon de thé", "Espace détente")
    insert_area(cur, 2, "Terrasse",      "Extérieur")
    tables_data = [
        (1, "S01", 1, 2), (2, "S02", 1, 2), (3, "S03", 1, 4),
        (4, "S04", 1, 4), (5, "S05", 1, 2), (6, "S06", 1, 6),
        (7, "T01", 2, 2), (8, "T02", 2, 4), (9, "T03", 2, 4),
    ]
    for t in tables_data:
        insert_table(cur, *t)

    insert_waiter(cur, 1, "Amina", "Tazi",  "1111")
    insert_waiter(cur, 2, "Houda", "Raiss", "2222")
    print("  Patisserie seed complete.")


# ---------------------------------------------------------------------------
# CLOTHES STORE
# ---------------------------------------------------------------------------

def seed_clothes(cur):
    print("Seeding: Magasin de vêtements")
    seed_common_users(cur)

    cats = [
        (1, "Homme",       "#1E3A5F", 1, IMG["men_shirt"]),
        (2, "Femme",       "#C2185B", 2, IMG["women_dress"]),
        (3, "Enfant",      "#F57F17", 3, IMG["kids"]),
        (4, "Accessoires", "#6A1B9A", 4, IMG["bag"]),
        (5, "Chaussures",  "#4E342E", 5, IMG["shoes"]),
        (6, "Soldes",      "#D32F2F", 6, IMG["sale"]),
        (7, "Sport",       "#00695C", 7, IMG["sport"]),
        (8, "Lingerie",    "#AD1457", 8, IMG["women_top"]),
    ]
    for c in cats:
        insert_category(cur, *c)

    products = [
        # Homme
        (1,  "T-shirt col rond blanc",      120.00, 1, "#1E3A5F", IMG["men_shirt"]),
        (2,  "Chemise Oxford bleue",         280.00, 1, "#1E3A5F", IMG["men_shirt"]),
        (3,  "Pantalon chino beige",         350.00, 1, "#1E3A5F", IMG["men_pants"]),
        (4,  "Jean slim noir",               399.00, 1, "#1E3A5F", IMG["men_pants"]),
        (5,  "Veste blazer marine",          650.00, 1, "#1E3A5F", IMG["men_jacket"]),
        (6,  "Pull col V cachemire",         480.00, 1, "#1E3A5F", IMG["men_pull"]),
        (7,  "Short de plage",              180.00, 1, "#1E3A5F", IMG["men_pants"]),
        # Femme
        (8,  "Robe florale d'été",           320.00, 2, "#C2185B", IMG["women_dress"]),
        (9,  "Blouse en soie",               290.00, 2, "#C2185B", IMG["women_top"]),
        (10, "Jean skinny femme",            380.00, 2, "#C2185B", IMG["women_jeans"]),
        (11, "Jupe midi plissée",            250.00, 2, "#C2185B", IMG["women_skirt"]),
        (12, "Veste en cuir synthétique",    590.00, 2, "#C2185B", IMG["women_coat"]),
        (13, "Manteau long camel",           890.00, 2, "#C2185B", IMG["women_coat"]),
        (14, "Ensemble co-ordiné",           450.00, 2, "#C2185B", IMG["women_dress"]),
        # Enfant
        (15, "T-shirt dinosaure enfant",      90.00, 3, "#F57F17", IMG["kids"]),
        (16, "Jogging enfant 4-14 ans",      150.00, 3, "#F57F17", IMG["kids"]),
        (17, "Robe petite fille",            130.00, 3, "#F57F17", IMG["kids"]),
        (18, "Pyjama enfant imprimé",        110.00, 3, "#F57F17", IMG["kids"]),
        # Accessoires
        (19, "Ceinture cuir noire",          130.00, 4, "#6A1B9A", IMG["belt"]),
        (20, "Écharpe laine",               160.00, 4, "#6A1B9A", IMG["scarf"]),
        (21, "Bonnet tricoté",               85.00, 4, "#6A1B9A", IMG["scarf"]),
        (22, "Sac à main femme",            650.00, 4, "#6A1B9A", IMG["bag"]),
        (23, "Portefeuille cuir",            220.00, 4, "#6A1B9A", IMG["bag"]),
        # Chaussures
        (24, "Sneakers blanches",            590.00, 5, "#4E342E", IMG["shoes"]),
        (25, "Mocassins homme",             680.00, 5, "#4E342E", IMG["shoes"]),
        (26, "Bottines femme",              750.00, 5, "#4E342E", IMG["boots"]),
        (27, "Sandales été",               380.00, 5, "#4E342E", IMG["shoes"]),
        # Soldes
        (28, "Chemise dégriffée -50%",      120.00, 6, "#D32F2F", IMG["sale"]),
        (29, "Robe d'été -40%",             180.00, 6, "#D32F2F", IMG["sale"]),
        (30, "Jean slim -30%",              199.00, 6, "#D32F2F", IMG["sale"]),
        # Sport
        (31, "Legging sport femme",         230.00, 7, "#00695C", IMG["sport"]),
        (32, "T-shirt dry-fit homme",       190.00, 7, "#00695C", IMG["sport"]),
        (33, "Short sport",                 160.00, 7, "#00695C", IMG["sport"]),
    ]
    for p in products:
        insert_product(cur, *p)

    insert_waiter(cur, 1, "Fatima", "El Amrani", "1111")
    insert_waiter(cur, 2, "Hassan", "Sebti",     "2222")
    print("  Clothes store seed complete.")


# ---------------------------------------------------------------------------
# GROCERY
# ---------------------------------------------------------------------------

def seed_grocery(cur):
    print("Seeding: Épicerie / Supermarché")
    seed_common_users(cur)

    cats = [
        (1, "Fruits & Légumes",        "#4CAF50", 1, IMG["vegetables"]),
        (2, "Produits laitiers",        "#2196F3", 2, IMG["dairy"]),
        (3, "Boucherie / Charcuterie",  "#F44336", 3, IMG["meat"]),
        (4, "Épicerie sèche",           "#FF9800", 4, IMG["grocery_dry"]),
        (5, "Boulangerie",              "#795548", 5, IMG["bread"]),
        (6, "Boissons",                 "#9C27B0", 6, IMG["soda"]),
        (7, "Hygiène & Beauté",         "#E91E63", 7, IMG["hygiene"]),
        (8, "Surgelés",                 "#00BCD4", 8, IMG["frozen"]),
    ]
    for c in cats:
        insert_category(cur, *c)

    products = [
        # Fruits & Légumes
        (1,  "Tomates (kg)",           8.00, 1,  "#4CAF50", IMG["tomato"]),
        (2,  "Pommes de terre (kg)",   5.00, 1,  "#4CAF50", IMG["vegetables"]),
        (3,  "Oignons (kg)",           4.00, 1,  "#4CAF50", IMG["vegetables"]),
        (4,  "Pommes Golden (kg)",    12.00, 1,  "#4CAF50", IMG["fruits"]),
        (5,  "Bananes (kg)",          10.00, 1,  "#4CAF50", IMG["fruits"]),
        (6,  "Carottes (kg)",          5.00, 1,  "#4CAF50", IMG["vegetables"]),
        (7,  "Citrons (kg)",           8.00, 1,  "#4CAF50", IMG["fruits"]),
        (8,  "Pastèque (pièce)",      25.00, 1,  "#4CAF50", IMG["fruits"]),
        # Laitier
        (9,  "Lait entier 1L Centrale", 8.50, 2, "#2196F3", IMG["milk"]),
        (10, "Yaourt nature x4",       14.00, 2, "#2196F3", IMG["dairy"]),
        (11, "Fromage Kiri x8",        22.00, 2, "#2196F3", IMG["dairy"]),
        (12, "Beurre Président 250g",  18.00, 2, "#2196F3", IMG["dairy"]),
        (13, "Crème fraîche 25cl",     12.00, 2, "#2196F3", IMG["dairy"]),
        # Boucherie
        (14, "Viande hachée bœuf (kg)",75.00, 3, "#F44336", IMG["meat"]),
        (15, "Escalope veau (kg)",     95.00, 3, "#F44336", IMG["meat"]),
        (16, "Poulet entier (kg)",     28.00, 3, "#F44336", IMG["chicken_raw"]),
        (17, "Côtelettes agneau (kg)",120.00, 3, "#F44336", IMG["meat"]),
        (18, "Merguez (kg)",           60.00, 3, "#F44336", IMG["meat"]),
        # Épicerie
        (19, "Huile Lesieur 1L",       22.00, 4, "#FF9800", IMG["oil"]),
        (20, "Sucre 1kg",              10.00, 4, "#FF9800", IMG["grocery_dry"]),
        (21, "Farine 1kg",              8.50, 4, "#FF9800", IMG["grocery_dry"]),
        (22, "Riz Basmati 1kg",        18.00, 4, "#FF9800", IMG["grocery_dry"]),
        (23, "Pâtes Barilla 500g",     14.00, 4, "#FF9800", IMG["grocery_dry"]),
        (24, "Conserve tomates 400g",  10.00, 4, "#FF9800", IMG["grocery_dry"]),
        (25, "Thon en boîte 160g",     18.00, 4, "#FF9800", IMG["grocery_dry"]),
        # Boulangerie
        (26, "Pain de mie 500g",       12.00, 5, "#795548", IMG["bread"]),
        (27, "Baguette",                4.00, 5, "#795548", IMG["baguette"]),
        (28, "Biscottes x36",          22.00, 5, "#795548", IMG["bread"]),
        # Boissons
        (29, "Eau Sidi Ali 1.5L",       5.50, 6, "#9C27B0", IMG["water"]),
        (30, "Coca-Cola 1.5L",         16.00, 6, "#9C27B0", IMG["soda"]),
        (31, "Jus Cappy 1L",           22.00, 6, "#9C27B0", IMG["juice"]),
        (32, "Café Nescafé 200g",      45.00, 6, "#9C27B0", IMG["espresso"]),
        # Hygiène
        (33, "Savon Dove 100g",        18.00, 7, "#E91E63", IMG["hygiene"]),
        (34, "Shampoing Pantene 400ml",38.00, 7, "#E91E63", IMG["hygiene"]),
        (35, "Dentifrice Colgate 75ml",22.00, 7, "#E91E63", IMG["hygiene"]),
        (36, "Déodorant Axe 150ml",    35.00, 7, "#E91E63", IMG["hygiene"]),
        # Surgelés
        (37, "Pizza 4 fromages",       55.00, 8, "#00BCD4", IMG["pizza_frozen"]),
        (38, "Frites McCain 1kg",      38.00, 8, "#00BCD4", IMG["frozen"]),
        (39, "Crevettes surgelées 500g",65.00, 8, "#00BCD4", IMG["frozen"]),
    ]
    for p in products:
        insert_product(cur, *p)

    insert_waiter(cur, 1, "Rachid", "Amrani",  "1111")
    insert_waiter(cur, 2, "Meryem", "Berrada", "2222")
    print("  Grocery store seed complete.")


# ---------------------------------------------------------------------------
# CAFÉ
# ---------------------------------------------------------------------------

def seed_cafe(cur):
    print("Seeding: Café / Coffee Shop")
    seed_common_users(cur)

    insert_station(cur, 1, "Bar",     "Cafés & boissons")
    insert_station(cur, 2, "Cuisine", "Sandwichs & snacks")

    cats = [
        (1, "Cafés",                  "#4E342E", 1, IMG["espresso"]),
        (2, "Thés & Infusions",       "#388E3C", 2, IMG["tea"]),
        (3, "Boissons froides",       "#0288D1", 3, IMG["smoothie"]),
        (4, "Snacks salés",           "#F57C00", 4, IMG["sandwich"]),
        (5, "Pâtisseries",            "#C2185B", 5, IMG["croissant"]),
        (6, "Breakfast",              "#FBC02D", 6, IMG["breakfast"]),
        (7, "Cocktails sans alcool",  "#7B1FA2", 7, IMG["cocktail"]),
    ]
    for c in cats:
        insert_category(cur, *c)

    products = [
        # Cafés
        (1,  "Espresso simple",        12.00, 1, "#4E342E", IMG["espresso"]),
        (2,  "Espresso double",        18.00, 1, "#4E342E", IMG["espresso"]),
        (3,  "Cappuccino",             22.00, 1, "#4E342E", IMG["cappuccino"]),
        (4,  "Latte",                  25.00, 1, "#4E342E", IMG["latte"]),
        (5,  "Flat white",             24.00, 1, "#4E342E", IMG["latte"]),
        (6,  "Café noisette",          16.00, 1, "#4E342E", IMG["espresso"]),
        (7,  "Americano",              18.00, 1, "#4E342E", IMG["espresso"]),
        (8,  "Café glacé",             28.00, 1, "#4E342E", IMG["latte"]),
        (9,  "Caramel macchiato",      32.00, 1, "#4E342E", IMG["latte"]),
        (10, "Mocha",                  30.00, 1, "#4E342E", IMG["cappuccino"]),
        # Thés
        (11, "Thé à la menthe",        12.00, 2, "#388E3C", IMG["tea"]),
        (12, "Thé vert nature",        12.00, 2, "#388E3C", IMG["tea"]),
        (13, "Thé noir Earl Grey",     14.00, 2, "#388E3C", IMG["tea"]),
        (14, "Tisane camomille",       14.00, 2, "#388E3C", IMG["tea"]),
        (15, "Chaï latte",             28.00, 2, "#388E3C", IMG["chai"]),
        # Boissons froides
        (16, "Limonade maison",        22.00, 3, "#0288D1", IMG["lemonade"]),
        (17, "Ice Tea pêche",          20.00, 3, "#0288D1", IMG["ice_tea"]),
        (18, "Smoothie mangue",        32.00, 3, "#0288D1", IMG["smoothie"]),
        (19, "Eau minérale 50cl",       8.00, 3, "#0288D1", IMG["water"]),
        (20, "Coca-Cola 33cl",         18.00, 3, "#0288D1", IMG["soda"]),
        # Snacks
        (21, "Croissant jambon-fromage",30.00, 4, "#F57C00", IMG["croque"]),
        (22, "Sandwich club",          40.00, 4, "#F57C00", IMG["club"]),
        (23, "Toast avocat",           38.00, 4, "#F57C00", IMG["toast_avo"]),
        (24, "Panini mozzarella",      35.00, 4, "#F57C00", IMG["panini"]),
        # Pâtisseries
        (25, "Croissant beurre",       12.00, 5, "#C2185B", IMG["croissant"]),
        (26, "Muffin myrtille",        20.00, 5, "#C2185B", IMG["muffin"]),
        (27, "Cookie chocolat",        15.00, 5, "#C2185B", IMG["cookie"]),
        (28, "Brownie",                22.00, 5, "#C2185B", IMG["brownie"]),
        (29, "Cheesecake (part)",      42.00, 5, "#C2185B", IMG["cheesecake"]),
        # Breakfast
        (30, "Formule petit déjeuner", 55.00, 6, "#FBC02D", IMG["breakfast"]),
        (31, "Omelette nature",        35.00, 6, "#FBC02D", IMG["omelette"]),
        (32, "Pancakes au miel",       40.00, 6, "#FBC02D", IMG["pancakes"]),
        # Cocktails
        (33, "Mojito virgin",          35.00, 7, "#7B1FA2", IMG["cocktail"]),
        (34, "Sunrise tropical",       38.00, 7, "#7B1FA2", IMG["cocktail"]),
        (35, "Blue lagoon",            38.00, 7, "#7B1FA2", IMG["cocktail"]),
    ]
    for p in products:
        insert_product(cur, *p)

    insert_area(cur, 1, "Salle intérieure", "Climatisé")
    insert_area(cur, 2, "Terrasse",          "Extérieur")
    tables_data = [
        (1,  "T01", 1, 2), (2,  "T02", 1, 2), (3,  "T03", 1, 4),
        (4,  "T04", 1, 4), (5,  "T05", 1, 6), (6,  "T06", 1, 2),
        (7,  "T07", 2, 2), (8,  "T08", 2, 4), (9,  "T09", 2, 2),
        (10, "T10", 2, 4),
    ]
    for t in tables_data:
        insert_table(cur, *t)

    insert_waiter(cur, 1, "Imane", "Bennis",   "1111")
    insert_waiter(cur, 2, "Tarik", "Hassoune", "2222")
    print("  Café seed complete.")


# ---------------------------------------------------------------------------
# Domain map & entry point
# ---------------------------------------------------------------------------
DOMAINS = {
    "restaurant": seed_restaurant,
    "patisserie": seed_patisserie,
    "clothes":    seed_clothes,
    "grocery":    seed_grocery,
    "cafe":       seed_cafe,
}

DEFAULT_DB_PATHS = [
    r"C:\Users\Test\Documents\sqd.db",
    r"C:\Users\Test\Documents\posecrea\sqd.db",
]


def find_db() -> str:
    for path in DEFAULT_DB_PATHS:
        if os.path.exists(path):
            return path
    raise FileNotFoundError("Could not find sqd.db. Pass the path with --db <path>")


def main():
    parser = argparse.ArgumentParser(description="caisse212 POS — seed / clear tool")
    parser.add_argument("--domain", "-d", choices=list(DOMAINS.keys()), help="Domain to seed")
    parser.add_argument("--clear", "-c", action="store_true", help="Clear all data (keeps schema)")
    parser.add_argument("--db", default=None, metavar="PATH", help="Path to sqd.db")
    args = parser.parse_args()

    if not args.clear and not args.domain:
        parser.error("Specify --domain and/or --clear. Use --help for options.")

    db_path = args.db if args.db else find_db()
    if not os.path.exists(db_path):
        print(f"[ERROR] DB not found: {db_path}")
        sys.exit(1)

    print(f"Using DB: {db_path}")
    conn = sqlite3.connect(db_path)

    try:
        if args.clear or args.domain:
            print("Clearing existing data...")
            clear_data(conn)

        if args.domain:
            DOMAINS[args.domain](conn.cursor())
            conn.commit()

        print("Done.")
    except Exception as e:
        conn.rollback()
        print(f"[ERROR] {e}")
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
