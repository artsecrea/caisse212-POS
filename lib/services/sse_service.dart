import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:loggecrea/loggecrea.dart';

import 'api_service.dart';

enum SseEventType {
  connected,
  newOrder,
  orderStateChanged,
  posCommand,
  heartbeat,
  unknown,
}

class SseEvent {
  final SseEventType type;
  final Map<String, dynamic> data;
  const SseEvent(this.type, this.data);
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
  bool _connecting = false;

  SseService(this._api);

  Stream<SseEvent> get events => _controller.stream;

  void start() {
    if (_shouldRun) return;
    _shouldRun = true;
    _connect();
  }

  void stop() {
    _shouldRun = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _client?.close(force: true);
    _client = null;
    _connecting = false;
    Logger.instance.info('SseService: stopped');
  }

  void dispose() {
    stop();
    _controller.close();
  }

  Future<void> _connect() async {
    if (_connecting || !_shouldRun) return;

    final token = _api.getAccessToken();
    final baseUrl = _api.getBaseUrl();
    if (token == null || baseUrl == null) {
      Logger.instance.info('SseService: no token/baseUrl, skipping connect');
      return;
    }

    _connecting = true;

    try {
      final uri = Uri.parse('$baseUrl/api/pos/queue/subscribe');
      _client?.close(force: true);
      _client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);

      final request = await _client!.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      // Do NOT send X-Business-Id: the server derives the business from
      // X-POS-Name, and sending the tenant id here (the old "tenantId doubles
      // as businessId" shortcut) is rejected with 403 "Business does not belong
      // to the current tenant" per the POS API contract.
      request.headers.set('X-POS-Name',
          _api.getPosName() ?? 'POS-TERMINAL');
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.headers.set('Cache-Control', 'no-cache');

      final response = await request.close();
      _connecting = false;
      _reconnectDelaySeconds = 3; // reset backoff on successful connect

      Logger.instance.info(
          'SseService: connected (status ${response.statusCode})');

      await _readStream(response);
    } catch (e) {
      _connecting = false;
      Logger.instance.error('SseService: connect error: $e');
      _scheduleReconnect();
    }
  }

  Future<void> _readStream(HttpClientResponse response) async {
    final buffer = StringBuffer();
    String eventName = '';
    String eventData = '';

    try {
      await for (final chunk in response.transform(utf8.decoder)) {
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
              _dispatch(eventName, eventData);
            }
            eventName = '';
            eventData = '';
          } else if (trimmed.startsWith('event:')) {
            eventName = trimmed.substring(6).trim();
          } else if (trimmed.startsWith('data:')) {
            eventData = trimmed.substring(5).trim();
          }
          // Ignore `id:` and `retry:` fields
        }
      }
    } catch (e) {
      if (!(_client == null && !_shouldRun)) {
        // Only log if not intentionally stopped
        Logger.instance.error('SseService: stream error: $e');
      }
    }

    if (_shouldRun) _scheduleReconnect();
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
      _controller.add(SseEvent(type, data));
    } catch (e) {
      Logger.instance.error('SseService: parse error event=$name: $e');
    }
  }

  SseEventType _toType(String name) {
    switch (name) {
      case 'connected':
        return SseEventType.connected;
      case 'new-order':
        return SseEventType.newOrder;
      case 'order-state-changed':
        return SseEventType.orderStateChanged;
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
