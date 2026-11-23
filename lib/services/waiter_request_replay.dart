import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Answers a repeated waiter write with the first answer instead of running it
/// again.
///
/// The waiter app keeps a round "unsent" whenever a request fails, so a reply
/// lost on the way back (a 12s timeout, a Wi-Fi drop) or a double tap sent the
/// same round twice, and the order got every line twice. Nothing in the order
/// rows can tell a repeat from a genuine second round of the same food, so the
/// client says which it is: an `Idempotency-Key` header, or a `requestId` in
/// the JSON body, names the attempt, and the same key within [keyedTtl] gets
/// the stored answer.
///
/// A request with no key runs as before. Matching identical bodies instead was
/// tried and dropped: two waiters' worth of the same drink seconds apart is a
/// real order, and the app's own send button already blocks a double tap.
///
/// Only a 2xx is remembered: after a refusal (no open session, unknown order)
/// the retry must run for real. A repeat arriving while the first attempt is
/// still running waits for it rather than racing it.
class WaiterRequestReplay {
  WaiterRequestReplay({
    this.keyedTtl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration keyedTtl;
  final DateTime Function() _clock;
  final Map<String, _Attempt> _attempts = {};

  /// Header that marks a response served from a stored attempt.
  static const replayHeader = 'idempotent-replay';

  Future<Response> run(
    Request request,
    String scope,
    Future<Response> Function(Request request) handler,
  ) async {
    final body = await request.readAsString();
    final fresh = request.change(body: body);

    final clientKey = _clientKey(request, body);
    if (clientKey == null) return handler(fresh);
    final key = '$scope|$clientKey';

    _prune();
    final earlier = _attempts[key];
    if (earlier != null) {
      final answer = await earlier.answer.future;
      if (answer != null) return answer.toResponse(replayed: true);
      // The earlier attempt was refused or failed: run this one for real.
    }

    final attempt = _Attempt(_clock(), keyedTtl);
    _attempts[key] = attempt;
    final Response response;
    try {
      response = await handler(fresh);
    } catch (_) {
      _forget(key, attempt);
      rethrow;
    }
    final text = await response.readAsString();
    final saved = _Answer(response.statusCode, text, response.headers);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      attempt.answer.complete(saved);
    } else {
      _forget(key, attempt);
    }
    return saved.toResponse();
  }

  void _forget(String key, _Attempt attempt) {
    if (identical(_attempts[key], attempt)) _attempts.remove(key);
    if (!attempt.answer.isCompleted) attempt.answer.complete(null);
  }

  void _prune() {
    final now = _clock();
    _attempts.removeWhere((_, a) =>
        a.answer.isCompleted && now.difference(a.startedAt) > a.ttl);
  }

  static String? _clientKey(Request request, String body) {
    final header = request.headers['idempotency-key']?.trim();
    if (header != null && header.isNotEmpty) return header;
    if (body.isEmpty) return null;
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final id = json['requestId'];
        if (id is String && id.trim().isNotEmpty) return id.trim();
      }
    } catch (_) {}
    return null;
  }
}

class _Attempt {
  _Attempt(this.startedAt, this.ttl);
  final DateTime startedAt;
  final Duration ttl;
  final Completer<_Answer?> answer = Completer<_Answer?>();
}

class _Answer {
  _Answer(this.status, this.body, Map<String, String> headers)
      : headers = Map.of(headers)
          ..remove('content-length')
          ..remove('transfer-encoding');
  final int status;
  final String body;
  final Map<String, String> headers;

  Response toResponse({bool replayed = false}) => Response(
        status,
        body: body,
        headers: {
          ...headers,
          if (replayed) WaiterRequestReplay.replayHeader: 'true',
        },
      );
}
