# Session Rules API Contract

Backend endpoint consumed by the POS app to enforce cashier session restrictions.

---

## Endpoint

```
GET /api/pos/session-rules
```

### Authentication

Same as all other POS endpoints:

| Header | Value |
|---|---|
| `Authorization` | `Bearer <access_token>` |
| `X-POS-Name` | POS device name (e.g. `caisse-1`) |
| `X-Tenant-ID` | Business tenant identifier |

---

## Response — 200 OK

```json
{
  "minStartHour": 8,
  "cantOpenAfterHour": 22,
  "maxSessionDurationMinutes": 480,
  "maxEndHour": 23,
  "maxSessionsPerUserPerDay": 2
}
```

All fields are **nullable integers**. A `null` value (or the field being absent) means "no restriction for that rule".

| Field | Type | Description |
|---|---|---|
| `minStartHour` | `int \| null` | Block session opens before this hour of day (0–23). Example: `8` → no sessions before 08:00. |
| `cantOpenAfterHour` | `int \| null` | Hard block — cannot open a new session **at or after** this hour (0–23). Example: `22` → no new sessions from 22:00 onwards. |
| `maxSessionDurationMinutes` | `int \| null` | Auto-close session after this many minutes **when the order panel is empty**. Example: `480` → auto-close after 8 h of inactivity. |
| `maxEndHour` | `int \| null` | Auto-close session at or after this hour **when the order panel is empty**. Example: `23` → auto-close at 23:00 if panel is clear. |
| `maxSessionsPerUserPerDay` | `int \| null` | Maximum number of sessions a single cashier may open per calendar day. Example: `2` → after 2 sessions in one day, the cashier is blocked. |

---

## Response — 404 Not Found

Returned when session rules have not been configured for this tenant.  
The POS treats a 404 as "no restrictions" and keeps using any previously cached rules unchanged.

---

## Response — 401 / 403

The POS skips the update and uses cached rules. The cashier session is not interrupted.

---

## Admin bypass

Admins (user type = `admin`) bypass **all** session rules on the POS side regardless of what the backend sends. This is enforced in the POS client; the backend does not need to handle this distinction.

---

## POS caching behaviour

- Rules are fetched during the full sync (`syncAllData`) and stored in `SharedPreferences` under the key `session_rules_json`.
- The in-memory `sessionRulesProvider` is updated immediately after a successful fetch.
- If the device is offline, cached rules from the previous sync are used.
- Rules are re-fetched on every manual sync triggered from the POS settings.
