# Waiter App — Push Notifications over SSE (LAN)

**Audience:** the developer working on `caisse212-waiter-app`.
**Status:** POS side is implemented, tested and merged. The waiter app side is not started — that is what this document is for.
**POS version:** the build containing `lib/services/lan_notification_hub.dart`.

---

## 1. What this is, and what it is not

The cashier can now ring a waiter's phone from the till. Long-press a waiter in the waiter picker, or long-press an occupied table, choose **Call waiter**, optionally type a message, send. The waiter's phone rings — and, when the setting says so, **keeps ringing until the waiter dismisses the notification**.

Two things about the transport, because they decide how you build this:

- **It is LAN, not cloud.** The stream is served by the POS's own embedded Shelf server — the same host and port the app already uses for `/waiters/login`, `/waiters/orders`, `/waiters/tables`. It is **not** the company backend, there is no bearer token involved, and it keeps working when the restaurant's internet is down. That is deliberate: asking a waiter to walk to table 7 is a room-sized event and must not depend on an ADSL line.
- **It is not FCM.** Nothing is delivered when the phone is off the restaurant Wi-Fi, and nothing is delivered by the OS on your behalf. The stream lives as long as your process holds the socket open. See §6 — this is the single hardest part of the job and the place where a naive implementation quietly fails after five minutes in a pocket.

The channel is generic on the POS side. Waiter calls are what ships first; KDS and other LAN clients will subscribe to the same hub later (`kds:<id>` channels), so the shape below is worth following rather than special-casing.

---

## 2. Endpoints

### 2.1 Subscribe

```
GET /waiters/events?waiterId=<id>
Accept: text/event-stream
X-Server-Password: <password>      # only if the POS has one configured
```

Same base URL as every other `/waiters/*` call. Same `X-Server-Password` rule as every other `/waiters/*` call — this route goes through the same auth middleware, so if your existing client attaches the header, attach it here too.

**Responses**

| Status | Meaning | What the app should do |
|---|---|---|
| `200` | Stream open, `Content-Type: text/event-stream` | Read frames until the socket dies, then reconnect |
| `400` | `waiterId` missing or not a number | Bug in the app — do not retry |
| `403` | `{"error":"unknown_waiter"}` — no such waiter, or deactivated | **Stop reconnecting.** Log the waiter out and show "your account is no longer active". Retrying here is an infinite loop against an endpoint that will keep saying no |
| `403` | `{"error":"Invalid or missing server password"}` | Missing/wrong `X-Server-Password` |

The 403-on-deactivated case is the one to get right. It is a deliberate difference from the other waiter routes: this connection is held for hours, so an identity that has since been revoked has to fail loudly at connect time rather than leave a phone spinning.

### 2.2 Acknowledge a call

```
POST /waiters/calls/<callId>/ack
Content-Type: application/json

{"by": "Amina"}          # optional; defaults to the waiter's name
```

| Status | Meaning |
|---|---|
| `200` | `{"acknowledged":true,"callId":"…","acknowledgedAt":"…"}` |
| `404` | `{"error":"unknown_call"}` — already acknowledged, or expired |

**Call this the moment the waiter dismisses the notification.** It does two things: it stops the same call ringing on that waiter's *other* devices (phone in pocket + tablet on the pass), and it tells the cashier somebody is on the way, so they do not ring again. A `404` is a perfectly fine outcome — stop ringing either way.

### 2.3 Capability probe

`GET /health` (which the app already polls every 15s) carries the switches:

```json
{ "status": "ok", "coursesEnabled": true, "waiterCallsEnabled": true, "catalogVersion": "…",
  "waiterShowKitchenStatus": true, "waiterNotifyReady": true,
  "waiterNotifyCanceled": false, "waiterNotifyRupture": true }
```

`waiterShowKitchenStatus` gates the per-line `kitchenState` / `readyAt` in the order payloads (see `waiter_api_reference.md` §11). The three `waiterNotify*` flags are informational — the POS already withholds those events when off — but let the app explain a silent phone. The same four flags are also in the `connected` hello.

Use it to decide whether to show call-related UI at all, and to answer "nothing rings" support reports with one curl. It reflects the POS setting live, so a cashier flipping the switch reaches every phone within 15s.

---

## 3. The event stream

Standard SSE framing: `event:` line, `data:` line (one line, JSON), blank line terminates the block.

### `connected` — sent immediately on every connect

```
event: connected
data: {"channel":"waiter:12","serverTime":"2026-09-21T16:40:56.255Z","waiterId":12,"callsEnabled":true,"heartbeatSeconds":20}

```

Treat receiving this as "the pipe is genuinely open", not merely "the socket connected". A response that opens and then says nothing is a real failure mode (a proxy buffering, a wrong route), and it looks exactly like a working connection until you notice nothing ever arrives.

### `waiter-call` — ring the phone

```
event: waiter-call
data: {"callId":"9f3c…","waiterId":12,"waiterName":"Amina B","message":"Customer waiting","tableId":7,"tableName":"T7","from":"Sam","ringUntilDismissed":true,"createdAt":"2026-09-21T16:40:56.255Z"}

```

| Field | Type | Notes |
|---|---|---|
| `callId` | `String` (uuid) | Pass back to `/ack`. Also your dedupe key — see §5 |
| `waiterId` | `int` | Always the waiter you subscribed as |
| `waiterName` | `String` | |
| `message` | `String?` | **Nullable.** Most calls have none — the common case is "come here". Render the notification without it |
| `tableId` | `int?` | |
| `tableName` | `String?` | Show it in the notification title/body — the waiter should know where to go without reading the message |
| `from` | `String` | Cashier display name |
| `ringUntilDismissed` | `bool` | `true` → loop the sound until dismissed. `false` → chime once. **Honour it**; it is a POS-side setting so the whole floor behaves one way |
| `createdAt` | ISO-8601 | Local time of the till |

### `waiter-call-cancelled` — stop ringing

```
event: waiter-call-cancelled
data: {"callId":"9f3c…","reason":"acknowledged","by":"Amina"}

```

`reason` is `acknowledged` (dismissed on another device) or `cancelled` (the cashier took it back, or the waiter turned up in person). Either way: **stop the sound and clear the notification for that `callId`.** Ignore it silently if you have no such call.

### Kitchen events (since 2026-09-24)

Three more events ride the same stream. Each is behind its own POS setting (**Settings → Server**), all **off by default**; the POS only sends an event while its switch is on, so the app needs no gating of its own for them. Every kitchen event carries a string **`eventId`** — dedupe by it (§5).

#### `kitchen-ready` — food to carry

Sent to the waiter who owns the order when the KDS moves lines into READY / COMPLETED for the **first** time. A whole-ticket bump arrives as one PUT per line; the POS coalesces those for ~1.5 s, so one bump = one event.

```
event: kitchen-ready
data: {"eventId":"…","orderId":41,"orderCode":"A-12","tableId":7,"tableName":"T7","at":"2026-09-24T13:02:11.000","lines":[{"lineId":301,"name":"Tajine","quantity":2.0,"courseNo":2,"kitchenState":"READY"}]}

```

Setting: `waiterNotifyReady`. Orders without a waiter (counter orders) never produce one.

#### `kitchen-canceled` — the till pulled something

Sent to the order's waiter when the **POS** removes lines from a saved order or cancels it whole. Removals the waiter makes from their own phone are never echoed back.

```
event: kitchen-canceled
data: {"eventId":"…","orderId":41,"orderCode":"A-12","tableId":7,"tableName":"T7","at":"…","wholeOrder":false,"reason":null,"lines":[{"lineId":null,"name":"Salade (grande)","quantity":1.0,"courseNo":null}]}

```

- `wholeOrder: true` → the order is cancelled; `lines` lists what the kitchen had already been sent (may be empty); `reason` is the cashier's text or `null`.
- `lineId` is `null` for removals (the row no longer exists). `courseNo` may be `null`.

Setting: `waiterNotifyCanceled`.

#### `product-availability` — rupture

Broadcast to **every** waiter when the POS marks a product EN RUPTURE, or available again.

```
event: product-availability
data: {"eventId":"…","productId":11,"name":"Pizza Margherita","isAvailable":false,"at":"…"}

```

The catalogue's `catalogVersion` changes at the same moment, so the menu greys the product out on the next `/health` poll anyway; this event is the heads-up. Setting: `waiterNotifyRupture`.

### Heartbeat

Every 20s the server writes a bare SSE comment:

```
: hb

```

No `event:`, no `data:` — your parser must not choke on it. It exists to keep proxies from closing an idle stream and, more importantly, so a phone that walked out of Wi-Fi range is discovered by the *server* on the next write.

### Resumption

There is **no** `Last-Event-ID` support and the server emits no `id:` fields. Do not build around it. Resumption is handled server-side by replay instead — see §5.

---

## 4. Client sketch

The POS's own SSE client (`posecrea/lib/services/sse_service.dart`) is a battle-tested reference for the same problem and worth reading before you write this. It was debugged the hard way; the comments in it are the scar tissue. The important parts, condensed:

```dart
class WaiterEventsService {
  static const _livenessTimeout = Duration(seconds: 60); // 2 missed heartbeats

  HttpClient? _client;
  Timer? _reconnectTimer, _livenessTimer;
  int _backoffSeconds = 3;
  bool _shouldRun = false;

  void start(int waiterId) {
    if (_shouldRun) return;
    _shouldRun = true;
    _connect(waiterId);
  }

  void stop() {                      // call on logout
    _shouldRun = false;
    _livenessTimer?.cancel();
    _reconnectTimer?.cancel();
    _client?.close(force: true);
    _client = null;
  }

  Future<void> _connect(int waiterId) async {
    if (!_shouldRun) return;
    try {
      _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final uri = Uri.parse('$baseUrl/waiters/events?waiterId=$waiterId');
      final req = await _client!.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      if (serverPassword != null) req.headers.set('X-Server-Password', serverPassword!);

      final res = await req.close();

      if (res.statusCode == 403) { stop(); onAuthRevoked(); return; } // do NOT retry
      if (res.statusCode != 200) { _scheduleReconnect(waiterId); return; }

      _backoffSeconds = 3;   // reset only after a real 200
      _markAlive();
      await _read(res, waiterId);
    } catch (_) {
      _scheduleReconnect(waiterId);
    }
  }

  Future<void> _read(HttpClientResponse res, int waiterId) async {
    var eventName = '';
    try {
      await for (final line in res
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        _markAlive();                          // ANY frame proves the pipe is alive
        if (line.startsWith(':')) continue;    // heartbeat comment
        if (line.startsWith('event:')) { eventName = line.substring(6).trim(); continue; }
        if (line.startsWith('data:') && eventName.isNotEmpty) {
          _dispatch(eventName, jsonDecode(line.substring(5).trim()));
          eventName = '';
        }
      }
    } catch (_) {/* socket died — fall through to reconnect */}
    if (_shouldRun) _scheduleReconnect(waiterId);
  }

  /// A stream can go silently dead: a sleeping NIC or a proxy drops it without
  /// closing the socket, so the read never completes and the app looks connected
  /// forever while every call lands in the void. Two missed heartbeats and we
  /// force a reconnect.
  void _markAlive() {
    _livenessTimer?.cancel();
    if (!_shouldRun) return;
    _livenessTimer = Timer(_livenessTimeout, () {
      _client?.close(force: true);   // makes the in-flight read complete
      _client = null;
    });
  }

  void _scheduleReconnect(int waiterId) {
    if (!_shouldRun) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _backoffSeconds), () => _connect(waiterId));
    _backoffSeconds = (_backoffSeconds * 2).clamp(3, 60);
  }
}
```

**Lifecycle:** `start(waiterId)` right after a successful `/waiters/login`, `stop()` on logout and on switching servers. Do not start it on the login screen — you do not have a `waiterId` yet, and the endpoint will 400.

---

## 5. Delivery guarantees (read this before designing the UI)

Push is best-effort; the POS makes it reliable with a **replay queue**, and your app has to cooperate.

- A call placed while the phone was locked, out of range, mid-reconnect, or not yet logged in is **held on the POS** and re-sent the instant that waiter opens a stream. So on every connect you may receive `connected` followed immediately by one or more `waiter-call` frames for calls you have never seen.
- **Corollary: you will receive the same `callId` more than once** — once live, then again after any reconnect that happens before the waiter acknowledges. **Dedupe by `callId`.** A waiter reconnecting three times on a flaky AP must not end up with three notifications for one call.
- Kitchen events (`kitchen-ready`, `kitchen-canceled`, `product-availability`) are replayed the same way: every one sent in the last **10 minutes** to that waiter (or broadcast) is re-sent on connect. They are never acknowledged, so **you will see them again after every reconnect inside that window — dedupe by `eventId`**, and do not re-notify for one you have already shown.
- Unacknowledged calls expire on the POS after **10 minutes**. A call from the lunch rush must not ring a phone at closing time.
- The cashier is told how many devices a call actually reached. Zero devices shows *"not connected — they will be notified at login"* rather than a false "sent". Your side of that bargain is connecting promptly after login and acknowledging promptly on dismiss.

---

### Live updates (not stored, not replayed)

`/health` and the `connected` hello carry `"waiterLiveUpdates": true` on builds that send these two. It is not a setting: open the stream whenever it is true.

#### `order-updated` — re-GET this order

Sent to the order's waiter when the order's money, lines, discount, table or status changes — a payment or a discount at the till, a line added or removed, a table move, a cancellation. The POS watches the data itself (debounced ~1 s), so it also fires after the waiter's own edits; treat it purely as "re-GET".

```
event: order-updated
data: {"eventId":"…","orderId":41,"orderCode":"A-12","tableId":7,"tableName":"7","at":"…","reason":"partial-payment","allPaid":false,"totalAmount":117.0,"balanceAmount":72.0}

```

`reason`: `canceled` | `paid` | `partial-payment` | `table` | `discount` | `lines` | `status` — the most telling change when several happened in the same second. Not in the inbox, not replayed.

#### `tables-changed` — re-fetch the floor

Broadcast to every waiter when a table's occupancy or balance changes, from anyone. Bursts are coalesced (~1 s).

```
event: tables-changed
data: {"eventId":"…","tableIds":[5,7],"at":"…"}

```

Kitchen replays skip anything the waiter already marked read in the inbox (`POST /waiters/notifications/read`), so a dismissed alert does not come back after an app restart.

## 5b. Notification history (inbox)

The POS keeps every notification it pushed — kitchen events **and** waiter calls — in **memory** (no database). A waiter can open their history any time; it survives app restarts, phone reboots and reconnects, and is emptied only when the **POS restarts**. Entries older than 24 h drop out, and at most 1000 are kept across the whole floor.

**`GET /waiters/notifications?waiterId=12&limit=100`** (`limit` 1–500, default 100)

```json
{ "unreadCount": 2,
  "notifications": [
    { "id": "…", "type": "kitchen-ready", "at": "2026-09-24T13:02:11.000", "read": false,
      "data": { /* exactly the SSE payload of that event */ } },
    { "id": "…", "type": "waiter-call", "at": "…", "read": true, "data": { "callId": "…", … } }
  ] }
```

- Newest first. `type` is the SSE event name (`kitchen-ready`, `kitchen-canceled`, `product-availability`, `waiter-call`).
- `id` is the same id the live frame carried: `eventId` for kitchen events, `callId` for calls. Use it to merge the history with what already arrived over SSE.
- A waiter sees their own entries plus broadcasts (`product-availability`). Read state is per waiter, even for broadcasts.
- Acknowledging a call (`/waiters/calls/<id>/ack`) marks it read automatically.

**`POST /waiters/notifications/read`** — body `{"waiterId": 12, "ids": ["…", "…"]}`; omit `ids` to mark all read. Returns `{"unreadCount": 0}`. `400` if `waiterId` is missing.

---

## 6. Making the phone actually ring

This is the part that is not about protocol, and it is where the feature will live or die.

### The hard constraint

The stream lives in your Dart isolate. When Android or iOS suspends the app, the socket dies and calls stop arriving — the OS will not wake you, because nothing here goes through FCM/APNs.

**Recommended approach (Android):** run the connection inside a **foreground service** with a persistent low-priority notification ("Connected to the till"). This is the only thing that reliably keeps a LAN socket alive in a phone that is in an apron pocket with the screen off. `flutter_foreground_task` is the usual choice. Also ask the user to exempt the app from battery optimisation — aggressive OEM killers (Xiaomi, Oppo, Huawei) will otherwise reap the service within minutes.

**iOS:** there is no equivalent. A backgrounded iOS app will lose the socket within seconds, and no entitlement legitimately keeps a plain TCP stream alive indefinitely. Practical options: keep the app foreground with the screen awake (`WakelockPlus.enable()` while on shift — defensible for a device that lives in a waiter's hand during service), or accept that iOS only receives calls while the app is open. **Flag this to the product owner rather than quietly shipping an iOS build that misses calls.** If iOS-in-background is a hard requirement, it needs a real push provider and a backend change, which is a different piece of work from this one.

### Ringing until dismissed

When `ringUntilDismissed == true`:

- **Sound:** `audioplayers` with `ReleaseMode.loop`, on a ringtone-class audio session so it is audible over silent mode where the platform allows. Keep looping until the waiter dismisses or a `waiter-call-cancelled` arrives for that `callId`.
- **Vibration:** repeating pattern alongside the sound.
- **Notification:** `flutter_local_notifications`, high-importance channel, `ongoing: true` + `autoCancel: false` so it cannot be swiped away without a deliberate action. On Android, a **full-screen intent** shows the call over the lock screen the way an incoming phone call does — which is exactly the mental model here. Give it one explicit action button, **Dismiss** (or "On my way"), whose handler:
  1. stops the sound and vibration,
  2. cancels the notification,
  3. `POST /waiters/calls/<callId>/ack`.
- **In-app:** if the app is foreground, show a blocking full-screen dialog with the caller, the table, the message, and one big dismiss button. Same ack on dismiss.
- **Safety valve:** stop ringing on your own after ~2 minutes even if nobody touched it, and leave the notification in place (silent) so the call is not lost. A phone that rings forever on a table in the back office is how a feature gets switched off for good.

When `ringUntilDismissed == false`: one chime, one ordinary dismissible notification, ack on tap.

---

## 7. Checklist

- [ ] `WaiterEventsService` with backoff, liveness watchdog, and `stop()` on logout
- [ ] Start on login success, stop on logout / server switch
- [ ] `403` → log out, do **not** reconnect
- [ ] Heartbeat comment lines (`: hb`) ignored, and counted as liveness
- [ ] Dedupe `waiter-call` by `callId`
- [ ] Ring loop honours `ringUntilDismissed`, with a ~2-minute safety stop
- [ ] Dismiss → stop sound → cancel notification → `POST /ack`
- [ ] `waiter-call-cancelled` stops an in-flight ring for that `callId`
- [ ] Android foreground service + battery-optimisation prompt
- [ ] iOS background limitation raised with the product owner
- [ ] Hide call UI when `/health` reports `waiterCallsEnabled: false`

---

## 8. Testing without a phone

The whole channel is curl-able against a running POS:

```bash
# Terminal 1 — watch the stream (waiter 1)
curl -N -H 'Accept: text/event-stream' \
     'http://<pos-ip>:8080/waiters/events?waiterId=1'

# Terminal 2 — acknowledge whatever came through
curl -X POST -H 'Content-Type: application/json' -d '{"by":"Amina"}' \
     'http://<pos-ip>:8080/waiters/calls/<callId>/ack'
```

Add `-H 'X-Server-Password: …'` to both if the POS has one set. Place the call from the POS UI (long-press a waiter → **Call waiter**), with **Settings → Server → Call waiters from the POS** switched on.

POS-side tests to mirror, if you want the same coverage on your side:
`posecrea/test/waiter_call_test.dart` (fan-out, queueing, ack) and
`posecrea/test/waiter_events_live_test.dart` (the real HTTP stream, over a real socket).

---

## 9. POS-side reference

| Concern | File |
|---|---|
| SSE fan-out, channels, heartbeat | `lib/services/lan_notification_hub.dart` |
| Call lifecycle, pending queue, ack | `lib/services/waiter_call_service.dart` |
| HTTP routes | `lib/services/server_service.dart` (`_waiterEvents`, `_waiterAckCall`) |
| Cashier UI | `lib/presentation/widgets/call_waiter_dialog.dart` |
| Settings | `AppSettings.waiterCallEnabled`, `AppSettings.waiterCallRingUntilDismissed` |
| Reference SSE *client* | `lib/services/sse_service.dart` |
