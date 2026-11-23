# SSE stability — diagnosis and asks (2026-10-02)

Stream: `GET {base}/api/pos/queue/subscribe` (Authorization, X-POS-Name,
X-Business-Id). Needed for external orders, `pos-command`, and next for
`order-updated` + admin approvals (`docs/ORDER_REFRESH_CONTRACT.md`).

## What was measured

**LAN dev server `192.168.11.163:8080` — server is healthy.** curl held the
stream 70 s: `200`, `Content-Type: text/event-stream`, chunked, `connected`
immediately, then `heartbeat` every 25 s.

**POS logs** (`build/windows/x64/runner/*/logs.txt`):

| Build | Server | What happened |
|---|---|---|
| Debug (Oct) | LAN | 424 connects; **225 killed by the POS's own watchdog** after 5–65 s; 6 × 401 (expired token, never refreshed); 181 refused (dev box down) |
| Release (Sep 22–23) | `https://app.caisse212.com` (Cloudflare) | **86 × HTTP 524** after ~2 min each, HTML body; 89 × "connection closed before full header"; 61 connect timeouts |

## Fixed on the POS (uncommitted)

1. **Watchdog ignored heartbeats** — it was fed only by business events, so
   every quiet minute the till dropped a healthy stream. Now any byte counts.
2. Stale connections could schedule reconnects that tore down the newer one
   (and double the backoff). Each connection now has a generation; only the
   current one acts.
3. **401 → refresh the token and retry in 3 s.** Before, every reconnect
   reused the expired token. The token is also refreshed before each connect
   when it is about to expire.
4. Backoff resets only once data flows (not on a 200 that closes at once).
5. Network back → reconnect immediately (was up to 60 s of backoff).
6. Multi-line `data:` joined per spec.
7. On every `connected` event the POS refreshes its open sessions' orders —
   catch-up for events missed while disconnected (see ask 3).

Tests: `test/sse_stability_test.dart` (local fake server).

## Asks for the backend

1. **Production 524 (most important).** Cloudflare returns 524 when the origin
   sends no response bytes for 100 s. On the LAN the same endpoint answers at
   once, so something between Cloudflare and Spring buffers the stream.
   - Spring: set `X-Accel-Buffering: no` and `Cache-Control: no-cache` on the
     subscribe response; flush `connected` immediately (already done on LAN).
   - Reverse proxy (nginx or other) for that location: `proxy_buffering off;
     proxy_cache off; proxy_read_timeout 3600s; proxy_http_version 1.1;
     proxy_set_header Connection "";` and no gzip on `text/event-stream`.
   - Cloudflare: no caching/transform on that path.
   - Verify: curl through `app.caisse212.com` with a real terminal token for
     2 minutes must show `connected` at once and a heartbeat every 25 s.
   - Also re-check the known header stripping of `X-POS-Name` /
     `X-Business-Id` at the edge (memory 2026-07-27).
2. **Rate limit.** The subscribe answer carries `X-RateLimit-Limit: 100`.
   Exclude `/queue/subscribe` from the limiter (or give it its own bucket), or
   a reconnect storm after an outage turns into 429s.
3. **No replay.** Events carry no `id:`, so anything sent while a till is
   disconnected is lost. For `order-updated` and approval decisions, either
   add `id:` + honour `Last-Event-ID`, or accept that the POS catches up by
   refreshing on connect (done, needs the session-orders endpoint).
4. Confirm: several emitters per terminal are allowed (a reconnect can briefly
   overlap the old one) and dead emitters are removed on
   completion/timeout/error; emitter timeout is unlimited (heartbeat keeps it).
