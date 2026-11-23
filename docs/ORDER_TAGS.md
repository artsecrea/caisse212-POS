# Order tags (POS side, 2026-10-08)

BMS contract: migration V194__order_tags.sql (not committed or deployed at the time of writing).

## What a tag is

- A short label (1–6 characters) with an optional color, `#RGB` or `#RRGGBB` (upper-case) or null.
- Tags are made **only in the back office**; the till never creates, renames or deletes one.
- An order carries at most 10 tags.
- Tags move no money, so they can be edited on **any** order, including one from a closed session or Z.

## Data (schema v60)

- `order_tags`: the catalogue cache (id = server id, label, color, sortOrder, businessId). It is replaced whole on every fetch, so a tag deleted in the back office disappears here too.
- `orders.tag_ids`: comma-separated server ids. Null means untagged.
- `orders.tags_synced`: false while a change still has to be pushed.
- `orders.tags_sync_error`: the message from a 400, which parks that order's tags.

## Flows

- **Catalogue:** `GET /pos/order-tags` on every full sync (`syncAllData`) and on the SSE pos-command `order_tags_updated`.
- **Main screen:** the **Tag** button (setting `showTagsButton`, toolbar key `tags`, on by default, added to saved button orders by migration) opens a chip picker.
  - An unsaved basket keeps the tags in `CurrentOrder.tagIds`, and `saveOrder` writes them.
  - A saved order is written through `OrderRepository.setOrderTags`, which queues the push.
- **Order panel:** shows the current order's tag chips.
- **Order management:**
  - tag chips on every row;
  - the order menu → **Tags** re-tags any order, locked Z or not;
  - the **Tags** filter chip keeps orders carrying ANY of the chosen tags, plus "Untagged".
  - The filter is applied in `getPaginatedOrdersWithFullDetails`, so paging stays right.
- **Push:** `PUT /pos/orders/{code}/tags` (full replace) in the sync job after the order push, and right after tagging.
  - 200 returns the set the server actually stored. The till replaces its local tags with it, because a tag deleted in the back office while the push was queued is dropped server-side instead of being refused.
  - 404 means the order isn't on the server yet: wait.
  - 400 is parked with its message and not re-sent.
  - A transport failure stops the cycle; the push is idempotent, so re-sending is safe.
- **Pull:** an order snapshot's `tags` replaces the local tags unless this till has an unpushed change (`tags_synced = false`).
  - `[]` means cleared.
  - An absent key (older server) means "no information": keep the local tags.
  - `order-updated` with reason `TAGS` re-reads the order, so this pull applies.

## Not done

- Tags are not printed on tickets.
- No permission token gates tagging (BMS agreed: no money moves).
