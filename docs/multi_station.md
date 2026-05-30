# caisse212 POS — Multi-Station Products (backend contract)

Lets a single product belong to **multiple stations**, so it shows up on multiple
KDS screens and prints on **all** of those stations' kitchen tickets. The existing
single `stationId` is kept as the **primary** station for backward compatibility.

---

## 1. Concept

- Each product keeps its current `stationId` (its **primary / default** station).
- A product may have **extra** stations on top of that.
- The client treats a product's effective stations as:

  ```
  effectiveStations(product) = { stationId }  ∪  stationIds[]
  ```

  i.e. `stationIds` is **additive** to `stationId`. A product with one station
  needs no extra data and behaves exactly as before.

---

## 2. Backend storage (recommended)

Keep `products.station_id` as-is, and add a join table for the extras:

```
product_stations(
  product_id  FK -> products.id,
  station_id  FK -> stations.id,
  PRIMARY KEY (product_id, station_id)
)
```

(You may store the primary station in this table too; the client de-duplicates, so
it doesn't matter.)

---

## 3. API contract

### `GET /pos/products`
Each product keeps every existing field, **plus** a `stationIds` array:

```json
{
  "id": 42,
  "name": "Cheeseburger",
  "price": 8.0,
  "finalPrice": 8.0,
  "categoryId": 3,
  "stationId": 1,
  "stationIds": [1, 3, 5],
  "...": "all other existing product fields unchanged"
}
```

Rules:
- `stationId` — unchanged (primary station, or `null`).
- `stationIds` — array of integer station ids. May include the primary or just the
  extras (client unions with `stationId` either way). **Omit or send `[]`** for a
  normal single-station product → legacy behavior.
- The values must be valid `stations.id`.

### Writing (admin assigning stations)
However the backend exposes product editing, persist the chosen station set into
`product_stations` and return it in `stationIds` on the next `GET /pos/products`.

---

## 4. How the client uses it

After sync, the client stores the extras in a local `product_stations` table and:
- **KDS order feed** (LAN server `/orders?station=…`): an order item is sent to a
  station's KDS if `product.stationId == station` **OR** the station is in the
  product's `product_stations`.
- **Kitchen tickets**: an item is printed on **every** station it belongs to (one
  ticket per station), instead of just its primary station.
- **Fallback**: a product with no extra rows uses only `stationId`, exactly as today.

---

## 5. Semantics note — additive vs authoritative

The client currently treats `stationIds` as **additive** to `stationId` (union).
This means you cannot "remove" the primary station via `stationIds` alone.

If you want `stationIds`, when present, to be the **authoritative full set** (so the
primary can be excluded), say so — the client switch is small: use `stationIds` when
non-empty, otherwise fall back to `stationId`.

---

## 6. Migration / back-compat checklist

- Existing products with only `stationId` keep working with no `product_stations`
  rows and no `stationIds` in the payload.
- Adding `stationIds` is purely additive to the API — old clients ignore it.
- `stationId` must remain populated for the primary station.
