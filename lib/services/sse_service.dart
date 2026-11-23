import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:loggecrea/loggecrea.dart';

import 'api_service.dart';
import 'remote_command_service.dart';

enum SseEventType {
  connected,
  newOrder,
  orderStateChanged,
  /// The platform (or an admin) cancelled a queued order. Consequential: if the
  /// cashier already confirmed it, the kitchen may be cooking food nobody will
  /// collect, so this is surfaced loudly rather than folded into a refresh.
  orderCancelled,
  orderReady,
  orderDeliveryStatusChanged,
  /// The server changed one of this till's orders (admin cancel, discount,
  /// note). `{orderCode}` — the POS refetches that order.
  orderUpdated,
  /// A reservation, block or the opening hours changed on any terminal or the
  /// web: `{reservationId, code, reason}`. The agenda re-reads its window.
  reservationUpdated,
  posCommand,
  heartbeat,
  unknown,
}

class SseEvent {
  final SseEventType type;
  final Map<String, dynamic> data;
  const SseEvent(this.type, this.data);
}

/// What the SSE pipe is doing right now.
///
/// Exists because "is the backend push working?" was previously answerable
/// only by reading the log file: the service reconnects silently, so a till
/// that had not received an order in hours looked identical to a quiet one.
enum SseConnectionState {
  /// Not running — no user, or the admin switch is off.
  stopped,

  /// A connect attempt is in flight.
  connecting,

  /// Connected and the stream is open.
  live,

  /// Dropped, waiting on the backoff timer to try again.
  retrying,

  /// The server answered, but not with a usable stream (non-200, or a
  /// content-type that is not `text/event-stream`). Distinct from [retrying]
  /// because this one will not fix itself — it is a config or auth fault.
  rejected,
}

/// A snapshot of the SSE connection for display.
///
/// [lastFrameAt] is any frame including heartbeats, which is the honest
/// liveness signal: the server sends one every 25s, so a `live` status whose
/// last frame is minutes old means the pipe is dead but not yet timed out.
@immutable
class SseStatus {
  final SseConnectionState state;
  final DateTime? connectedAt;
  final DateTime? lastFrameAt;

  /// Business events delivered this run — heartbeats excluded, because a
  /// count that ticks up on its own tells the operator nothing.
  final int eventCount;

  /// Connect attempts this run. Climbing while never reaching [live] is the
  /// signature of the connect→reconnect loop.
  final int attempts;

  /// Why it is not live, when it is not. Shown verbatim.
  final String? detail;

  const SseStatus({
    this.state = SseConnectionState.stopped,
    this.connectedAt,
    this.lastFrameAt,
    this.eventCount = 0,
    this.attempts = 0,
    this.detail,
  });

  SseStatus copyWith({
    SseConnectionState? state,
    DateTime? connectedAt,
    DateTime? lastFrameAt,
    int? eventCount,
    int? attempts,
    String? detail,
    bool clearDetail = false,
  }) =>
      SseStatus(
        state: state ?? this.state,
        connectedAt: connectedAt ?? this.connectedAt,
        lastFrameAt: lastFrameAt ?? this.lastFrameAt,
        eventCount: eventCount ?? this.eventCount,
        attempts: attempts ?? this.attempts,
        detail: clearDetail ? null : (detail ?? this.detail),
      );
}

/// SSE client for /api/pos/queue/subscribe.
/// Call [start] after login, [stop] on logout.
/// Emits typed events via [events] stream.
/// Auto-reconnects with exponential backoff (3s → 60s).
class SseService {
  final ApiService _api;

  final StreamController<SseEvent> _controller =
      StreamController<SseEvent>.broadcast();

  HttpClient? _client;
  Timer? _reconnectTimer;
  int _reconnectDelaySeconds = 3;
  bool _shouldRun = false;
  static String? _version;
  bool _connecting = false;

  /// Liveness watchdog. The server sends a heartbeat every 25s and never times
  /// the stream out itself, so a connection can go silently dead — a proxy or a
  /// sleeping NIC drops it without closing the socket, and the read simply never
  /// completes. Without this, the POS looks connected forever and every order
  /// lands in the queue unseen. Two missed heartbeats is the trigger.
  Timer? _livenessTimer;
  final Duration _livenessTimeout;
  int _connectCount = 0; // total connect attempts this run (for correlating logs)

  /// The connection that is current. A stream that ended because a newer one
  /// replaced it (or the watchdog gave up on it) must not schedule a
  /// reconnect: it would tear the newer connection down — `_connect` closes
  /// the client — and start the loop again.
  int _generation = 0;

  /// Live connection status, for the diagnostic in Settings. A plain
  /// [ValueNotifier] rather than a stream: the UI wants the CURRENT value the
  /// moment it builds, and a broadcast stream has no current value to give it.
  final ValueNotifier<SseStatus> status =
      ValueNotifier<SseStatus>(const SseStatus());

  void _setState(SseConnectionState s, {String? detail, bool clearDetail = false}) {
    status.value = status.value
        .copyWith(state: s, detail: detail, clearDetail: clearDetail);
  }

  SseService(this._api,
      {Duration livenessTimeout = const Duration(seconds: 60)})
      : _livenessTimeout = livenessTimeout;

  Stream<SseEvent> get events => _controller.stream;

  void start() {
    if (_shouldRun) return;
    _shouldRun = true;
    _setState(SseConnectionState.connecting, clearDetail: true);
    _connect();
  }

  /// Restart the silence countdown. Called on every byte received —
  /// heartbeats included: they are the whole point of the watchdog. (It used
  /// to run only on business events, so a quiet till killed a healthy stream
  /// every 60s.)
  void _markAlive(int generation) {
    if (generation != _generation) return;
    status.value = status.value.copyWith(lastFrameAt: DateTime.now());
    _livenessTimer?.cancel();
    if (!_shouldRun) return;
    _livenessTimer = Timer(_livenessTimeout, () {
      if (!_shouldRun || generation != _generation) return;
      Logger.instance.warning(
          'SseService: no frame for ${_livenessTimeout.inSeconds}s — the stream '
          'is silently dead, forcing a reconnect');
      _abandonCurrent();
      _setState(SseConnectionState.retrying,
          detail: 'No frame for ${_livenessTimeout.inSeconds}s');
      _scheduleReconnect();
    });
  }

  /// Drop the current connection without letting its read loop react.
  void _abandonCurrent() {
    _generation++;
    _livenessTimer?.cancel();
    _client?.close(force: true);
    _client = null;
    _connecting = false;
  }

  /// Reconnect now instead of waiting out the backoff — the network just came
  /// back. No-op while a healthy stream is up.
  void reconnectNow() {
    if (!_shouldRun || status.value.state == SseConnectionState.live) return;
    Logger.instance.info('SseService: network back — reconnecting now');
    _reconnectTimer?.cancel();
    _reconnectDelaySeconds = 3;
    _abandonCurrent();
    _connect();
  }

  void stop() {
    _generation++;
    _shouldRun = false;
    _livenessTimer?.cancel();
    _livenessTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _client?.close(force: true);
    _client = null;
    _connecting = false;
    _setState(SseConnectionState.stopped, clearDetail: true);
    Logger.instance.info('SseService: stopped');
  }

  void dispose() {
    stop();
    status.dispose();
    _controller.close();
  }

  Future<void> _connect() async {
    if (_connecting || !_shouldRun) return;
    _connecting = true;
    final generation = ++_generation;

    // The stream is authenticated once, at connect: an expired token here is
    // a 401 on every reconnect until something else happens to refresh it.
    await _api.ensureFreshToken();
    if (!_shouldRun || generation != _generation) return;

    final token = _api.getAccessToken();
    final baseUrl = _api.getBaseUrl();
    if (token == null || baseUrl == null) {
      Logger.instance.info('SseService: no token/baseUrl, skipping connect');
      _connecting = false;
      _setState(SseConnectionState.rejected,
          detail: token == null ? 'Not signed in' : 'No server URL');
      return;
    }

    final attempt = ++_connectCount;
    status.value = status.value.copyWith(
        state: SseConnectionState.connecting, attempts: attempt);

    try {
      // Double `/api` is intentional: stored base ends in `/api` and the backend
      // is context-path `/api` + controller `@RequestMapping("/api/pos/queue")`,
      // so the real path is `/api/api/pos/queue/subscribe`. Mirrors the Dio
      // interceptor. See ApiService._setupInterceptors note.
      final uri = Uri.parse('$baseUrl/api/pos/queue/subscribe');
      final posName = _api.getPosName() ?? 'POS-TERMINAL';
      // The /subscribe endpoint REQUIRES X-Business-Id to resolve the SSE
      // business context. Without it the server throws internally and masks the
      // failure as an empty 200 that closes instantly (the connect→reconnect
      // loop). We send the REAL business id (getBusinessId), never the tenant
      // id — the old 403 "Business does not belong to the current tenant" was
      // caused by sending tenant-id-as-business-id, which is why a prior fix
      // wrongly dropped the header entirely.
      final businessId = _api.getBusinessId();
      final maskedToken = token.length > 12
          ? '${token.substring(0, 8)}…${token.substring(token.length - 4)} (len ${token.length})'
          : '*** (len ${token.length})';
      Logger.instance.info(
          'SseService: connecting (attempt #$attempt) → $uri  '
          'X-POS-Name="$posName"  X-Business-Id=${businessId ?? '(MISSING!)'}  '
          'token=$maskedToken');
      if (businessId == null) {
        _setState(SseConnectionState.rejected,
            detail: 'No business id stored - the server will reject this');
        Logger.instance.warning(
            'SseService: no businessId stored — the server will reject the '
            'subscription (empty 200). Ensure login persisted business_id.');
      }

      _client?.close(force: true);
      _client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);

      final request = await _client!.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set('X-POS-Name', posName);
      // Required by /subscribe (see note above). Send the real business id.
      if (businessId != null) {
        request.headers.set('X-Business-Id', businessId.toString());
      }
      // What this build answers, so the back office only offers those.
      _version ??= await RemoteCommandService.appVersion();
      if (_version != null) request.headers.set('X-POS-Version', _version!);
      request.headers.set(
          'X-POS-Capabilities', RemoteCommandService.capabilities.join(','));
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.headers.set('Cache-Control', 'no-cache');

      final response = await request.close();
      if (generation != _generation) return; // replaced while connecting
      _connecting = false;

      // Dump the key response headers. A proper SSE endpoint answers with
      // `content-type: text/event-stream` and keeps the connection open
      // (chunked / no content-length). If we instead see JSON/HTML, a
      // content-length, or `connection: close`, the body will end immediately
      // and we'll loop connect→reconnect — exactly the symptom being debugged.
      final ct = response.headers.contentType?.toString() ?? '(none)';
      final connHdr = response.headers.value(HttpHeaders.connectionHeader) ?? '(none)';
      final te = response.headers.value(HttpHeaders.transferEncodingHeader) ?? '(none)';
      Logger.instance.info(
          'SseService: connected (attempt #$attempt, status ${response.statusCode})  '
          'content-type=$ct  connection=$connHdr  transfer-encoding=$te  '
          'content-length=${response.contentLength}');

      if (response.statusCode == 401) {
        // Expired or rotated token — not a config fault. Refresh, retry soon.
        await response.drain<void>().catchError((_) {});
        if (generation != _generation) return;
        final refreshed = _api.getAccessToken() != token ||
            await _api.ensureFreshToken(force: true);
        Logger.instance.warning('SseService: 401 — token '
            '${refreshed ? 'refreshed, retrying' : 'refresh failed'}');
        _setState(SseConnectionState.retrying, detail: 'HTTP 401');
        if (refreshed) _reconnectDelaySeconds = 3;
        _scheduleReconnect();
        return;
      }

      if (response.statusCode == 423 || response.statusCode == 403) {
        final raw = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 5), onTimeout: () => '')
            .catchError((_) => '');
        dynamic body;
        try {
          body = jsonDecode(raw);
        } catch (_) {}
        if (await _api.noteAccountRefusal(response.statusCode,
            response.headers.value('x-account-status'), body)) {
          // The account watcher signs the cashier out, which stops this
          // service. No reconnect loop against a disabled account.
          Logger.instance.warning('SseService: account disabled — not reconnecting');
          _setState(SseConnectionState.rejected, detail: 'Account disabled');
          return;
        }
        if (generation != _generation) return;
        _setState(SseConnectionState.rejected,
            detail: 'HTTP ${response.statusCode} from the server');
        _scheduleReconnect();
        return;
      }

      if (response.statusCode != 200) {
        _setState(SseConnectionState.rejected,
            detail: 'HTTP ${response.statusCode} from the server');
        Logger.instance.error(
            'SseService: non-200 status ${response.statusCode} — server rejected the subscription. '
            'Check auth token / X-POS-Name / route.');
      } else if (!ct.contains('event-stream')) {
        _setState(SseConnectionState.rejected,
            detail: 'Wrong content-type: $ct');
        Logger.instance.warning(
            'SseService: content-type is "$ct" (expected text/event-stream). '
            'A proxy or wrong route is likely buffering/closing the response — '
            'the stream will end right away and reconnect.');
      }

      if (response.statusCode == 200 && ct.contains('event-stream')) {
        // Arm the watchdog now, not on the first frame: a stream that opens
        // and then says nothing at all is exactly the failure it catches.
        // Not before this check — a rejected answer has its own retry, and a
        // watchdog left running would cancel it.
        _markAlive(generation);
        status.value = status.value.copyWith(
          state: SseConnectionState.live,
          connectedAt: DateTime.now(),
          clearDetail: true,
        );
      }

      await _readStream(response, attempt, generation);
    } catch (e, st) {
      if (generation != _generation) return;
      _connecting = false;
      _setState(SseConnectionState.retrying, detail: '$e');
      Logger.instance.error('SseService: connect error (attempt #$attempt): $e');
      Logger.instance.debug('SseService: connect stacktrace: $st');
      _scheduleReconnect();
    }
  }

  Future<void> _readStream(
      HttpClientResponse response, int attempt, int generation) async {
    final buffer = StringBuffer();
    String eventName = '';
    final eventData = <String>[];

    // Diagnostics: measure how long the stream stays open and what flows
    // through it. A near-zero duration with 0 chunks means the server closed
    // the body immediately (the connect→reconnect loop root cause).
    final sw = Stopwatch()..start();
    var chunkCount = 0;
    var byteCount = 0;
    var eventCount = 0;
    Object? endError;

    try {
      await for (final chunk in response.transform(utf8.decoder)) {
        if (generation != _generation) break; // replaced — stop reading
        chunkCount++;
        byteCount += chunk.length;
        _markAlive(generation);
        // Data is flowing: this connection works, so the next drop starts
        // the backoff from the bottom again. (Reset on headers alone, a
        // server answering 200 and closing would be retried every 3s.)
        _reconnectDelaySeconds = 3;
        // Verbose raw dump (truncated, newlines escaped) via debugPrint so it
        // never touches the log file. Shows exactly what the server sends —
        // heartbeats, events, or an unexpected HTML/JSON error body.
        final preview =
            (chunk.length > 300 ? '${chunk.substring(0, 300)}…' : chunk)
                .replaceAll('\n', '\\n');
        debugPrint(
            'SseService[#$attempt]: chunk $chunkCount (${chunk.length}b) @${sw.elapsedMilliseconds}ms: $preview');

        buffer.write(chunk);
        final raw = buffer.toString();
        buffer.clear();

        final lines = raw.split('\n');
        // Last element may be incomplete — put back in buffer
        if (!raw.endsWith('\n')) {
          buffer.write(lines.removeLast());
        }

        for (final line in lines) {
          final trimmed = line.trimRight();

          if (trimmed.isEmpty) {
            // Blank line = end of event block
            if (eventData.isNotEmpty) {
              eventCount++;
              _dispatch(eventName, eventData.join('\n'));
            }
            eventName = '';
            eventData.clear();
          } else if (trimmed.startsWith('event:')) {
            eventName = trimmed.substring(6).trim();
          } else if (trimmed.startsWith('data:')) {
            // A payload may span several `data:` lines; the spec joins them.
            eventData.add(trimmed.substring(5).trim());
          }
          // Ignore `id:`, `retry:` and `:` comment lines
        }
      }
    } catch (e) {
      endError = e;
      if (!(_client == null && !_shouldRun)) {
        // Only log if not intentionally stopped
        Logger.instance.error(
            'SseService[#$attempt]: stream error after ${sw.elapsedMilliseconds}ms: $e');
      }
    }

    sw.stop();
    // Summary line — the key diagnostic. If elapsed is tiny and chunks/events
    // are 0, the server accepted the request (200) but sent no stream and
    // closed it, so we reconnect on a loop.
    final endedBy = endError != null
        ? 'error'
        : (_shouldRun ? 'server-closed' : 'stopped');
    final logline =
        'SseService[#$attempt]: stream ended after ${sw.elapsedMilliseconds}ms '
        '— chunks=$chunkCount bytes=$byteCount events=$eventCount endedBy=$endedBy';
    if (endError == null && chunkCount == 0 && _shouldRun) {
      // Zero data + immediate close is abnormal for SSE — flag it loudly.
      Logger.instance.warning('$logline (no data received — abnormal for SSE)');
    } else {
      Logger.instance.info(logline);
    }

    // A replaced stream ends quietly: the connection that replaced it owns
    // the state and the reconnect timer.
    if (_shouldRun && generation == _generation) {
      _livenessTimer?.cancel();
      _setState(SseConnectionState.retrying,
          detail: endError != null
              ? '$endError'
              : (chunkCount == 0
                  ? 'Server closed the stream without sending anything'
                  : 'Server closed the stream'));
      _scheduleReconnect();
    }
  }

  void _dispatch(String name, String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final type = _toType(name);
      if (type == SseEventType.heartbeat) {
        debugPrint('SseService: heartbeat');
        return;
      }
      Logger.instance.info('SseService: event $name');
      status.value =
          status.value.copyWith(eventCount: status.value.eventCount + 1);
      _controller.add(SseEvent(type, data));
    } catch (e) {
      Logger.instance.error('SseService: parse error event=$name: $e');
    }
  }

  /// Exposed for tests: an event name the POS does not recognise degrades to
  /// [SseEventType.unknown] and is silently dropped, so a typo here is invisible
  /// at runtime — `order-cancelled` went unhandled exactly that way.
  @visibleForTesting
  static SseEventType toEventType(String name) => _toTypeStatic(name);

  SseEventType _toType(String name) => _toTypeStatic(name);

  static SseEventType _toTypeStatic(String name) {
    switch (name) {
      case 'connected':
        return SseEventType.connected;
      case 'new-order':
        return SseEventType.newOrder;
      case 'order-state-changed':
        return SseEventType.orderStateChanged;
      case 'order-cancelled':
        return SseEventType.orderCancelled;
      case 'order-ready':
        return SseEventType.orderReady;
      case 'order-delivery-status-changed':
        return SseEventType.orderDeliveryStatusChanged;
      case 'order-updated':
        return SseEventType.orderUpdated;
      case 'reservation-updated':
        return SseEventType.reservationUpdated;
      case 'pos-command':
        return SseEventType.posCommand;
      case 'heartbeat':
        return SseEventType.heartbeat;
      default:
        return SseEventType.unknown;
    }
  }

  void _scheduleReconnect() {
    if (!_shouldRun) return;
    Logger.instance.info(
        'SseService: reconnecting in ${_reconnectDelaySeconds}s');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: _reconnectDelaySeconds),
      _connect,
    );
    _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(3, 60);
  }
}
