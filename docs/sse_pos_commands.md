# SSE POS Commands — Backend Contract

This document describes all remote commands the POS accepts via the Server-Sent Events (SSE) channel. Commands let the backend (or an admin dashboard) control a live POS terminal without requiring the cashier to act.

---

## Transport

Commands arrive as a **`pos-command`** SSE event on the existing subscription endpoint:

```
GET /api/pos/queue/subscribe
Accept: text/event-stream
Authorization: Bearer <access_token>
X-POS-Name: <pos_name>
X-Tenant-ID: <tenant_id>
```

Event wire format:

```
event: pos-command
data: {"type":"<command_type>", ...extra fields}

```

*(Two newlines terminate the event block — standard SSE.)*

The POS matches `type` case-insensitively, executes the action, and writes a row to the `activity_logs` table with `action_type = 'POS_COMMAND'`.

---

## Command Reference

### Sync — Full

Triggers a complete master-data refresh: wipes and re-fetches users, categories, products, variants, components, areas, tables, commercials, customers, waiters. Also pulls order/ticket deltas from the server.

| Field | Value |
|---|---|
| `type` | `sync_all` |
| Aliases | `reload_all`, `update:db`, `reload_menu` |

```json
{ "type": "sync_all" }
```

---

### Sync — Menu (fast, no full wipe)

Re-fetches and upserts categories, stations, products, variants, component groups, components, and product-components only. No other tables are touched. Faster than `sync_all`.

| Field | Value |
|---|---|
| `type` | `sync_menu` |
| Aliases | `sync_products`, `reload_products` |

```json
{ "type": "sync_menu" }
```

---

### Sync — Categories

Re-fetches and upserts categories (and the rest of the menu graph, since categories and products are fetched together).

```json
{ "type": "sync_categories" }
```

---

### Sync — Users

Re-fetches and upserts the user list only. Preserves local `lastLogin` and `displayName` fields.

```json
{ "type": "sync_users" }
```

---

### Sync — Areas & Tables

Re-fetches and upserts areas and tables. Preserves the current table→order assignment so in-progress orders are not disrupted.

```json
{ "type": "sync_areas" }
```

---

### Sync — Orders

Flushes pending local operations to the server, uploads unsynced orders in bulk, then pulls the latest order deltas from the server.

```json
{ "type": "sync_orders" }
```

---

### Sync — Sessions

Flushes pending operations and uploads any unsynced cash sessions to the server.

```json
{ "type": "sync_sessions" }
```

---

### Sync — Customers

Flushes pending operations and uploads any unsynced customer records to the server.

```json
{ "type": "sync_customers" }
```

---

### Sync — Upload only

Uploads everything local (pending ops → sessions → orders → tickets → customers) without pulling anything from the server. Useful to trigger a push without changing master data.

```json
{ "type": "sync_upload" }
```

---

### Close Current Session

Ends the active (or paused) cash session of the currently logged-in cashier. Clears the session state on the POS. The POS then syncs remaining data and navigates the UI back to the login screen.

| Field | Value |
|---|---|
| `type` | `close_session` |
| Aliases | `close_current_session` |

```json
{ "type": "close_session" }
```

---

### Close All Sessions

Ends **every** active or paused cash session stored in the POS database (not just the current user's). If the current cashier's session is among them, the UI navigates back to the login screen.

```json
{ "type": "close_all_sessions" }
```

---

### Force Logout

Closes the current user's session (same as `close_session`) and immediately signals the UI to navigate to the login screen. Useful for remotely terminating an unattended terminal.

| Field | Value |
|---|---|
| `type` | `force_logout` |
| Aliases | `logout` |

```json
{ "type": "force_logout" }
```

---

### Open Admin Mode

Grants temporary admin-level elevation on the POS without requiring the cashier to enter a PIN. The elevation identity is recorded in the activity log.

| Field | Type | Description |
|---|---|---|
| `type` | `string` | `"open_admin_mode"` |
| `adminId` | `integer` | ID of the admin granting the elevation (use `0` if not applicable) |
| `adminUsername` | `string` | Display name shown in logs and the admin-mode chip (default: `"Remote Admin"`) |

```json
{
  "type": "open_admin_mode",
  "adminId": 42,
  "adminUsername": "Alice"
}
```

**Effect on the POS:** the admin-mode chip appears in the top bar; all permission checks pass for the remainder of the session (or until `close_admin_mode` is sent).

---

### Close Admin Mode

Removes the admin-mode elevation. The cashier reverts to their normal permission level immediately.

| Field | Value |
|---|---|
| `type` | `close_admin_mode` |
| Aliases | `exit_admin_mode` |

```json
{ "type": "close_admin_mode" }
```

---

### Display Alert

Pushes a banner message to the POS screen. The cashier sees a dismissible SnackBar with the message text.

| Field | Type | Description |
|---|---|---|
| `type` | `string` | `"display_alert"` |
| `message` | `string` | The text to display (max ~200 chars recommended) |

```json
{
  "type": "display_alert",
  "message": "Kitchen will close in 15 minutes. No new food orders."
}
```

---

## Activity Log

Every recognised command is written to the `activity_logs` table with:

| Column | Value |
|---|---|
| `action_type` | `POS_COMMAND` |
| `phrase` | Localised string, e.g. `"Remote server command: sync_menu"` |
| `userId` | `null` (server-initiated, no cashier actor) |
| `username` | `null` |
| `timestamp` | UTC time the command was processed |

Commands with extra context include a `—` separator in the phrase:

- `open_admin_mode` → `"Remote server command: open_admin_mode — granted by Alice"`
- `display_alert` → `"Remote server command: display_alert — Kitchen will close in 15 minutes…"`

Unknown or malformed `type` values are ignored and **not** logged.

---

## Error Handling

- Sync commands swallow internal errors — a failed sync does not crash the SSE loop or prevent future commands from being processed.
- Session-close and admin-mode commands do not retry on failure; the caller should re-send if the expected effect is not visible.
- The POS always acknowledges the command by writing to `activity_logs` (even if the underlying action partially failed), so the server can confirm receipt by reading the log endpoint.

---

## Quick Reference

| `type` | Action |
|---|---|
| `sync_all` | Full master-data refresh + delta pull |
| `sync_menu` | Categories + products + variants (fast upsert) |
| `sync_categories` | *(same as sync_menu)* |
| `sync_users` | Users only |
| `sync_areas` | Areas + tables |
| `sync_orders` | Upload orders + pull deltas |
| `sync_sessions` | Upload sessions |
| `sync_customers` | Upload customers |
| `sync_upload` | Upload all (no pull) |
| `close_session` | End current user's session → login screen |
| `close_all_sessions` | End all sessions → login screen |
| `force_logout` | Close session + immediately navigate to login |
| `open_admin_mode` | Grant admin elevation (no PIN required) |
| `close_admin_mode` | Revoke admin elevation |
| `display_alert` | Show banner message to cashier |
| `refresh_token` | Rotate the token pair now (re-reads scope + subscription) — see SUBSCRIPTION_CONTRACT.md |
| `subscription_updated` | Store pushed subscription, or re-read `GET /pos/subscription` — see SUBSCRIPTION_CONTRACT.md |
