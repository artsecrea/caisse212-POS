import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/sse_provider.dart';
import '../../services/api_service.dart';
import '../../services/sse_service.dart';

/// Live view of the terminal's tokens for Test mode: what they are, when they
/// die (ticking every second), and whether they just rotated.
///
/// Built for checking the backend's `refresh_token` SSE command: leave this
/// open while signed in, send the command from BMS, and watch the rotation
/// counter tick and the expiry jump. Debug builds only (see TestModeScreen).
class TokenDebugPanel extends ConsumerStatefulWidget {
  const TokenDebugPanel({super.key});

  @override
  ConsumerState<TokenDebugPanel> createState() => _TokenDebugPanelState();
}

class _TokenDebugPanelState extends ConsumerState<TokenDebugPanel> {
  Timer? _ticker;
  bool _reveal = false;

  // Rotation tracking — compared each tick, so a rotation from ANY path (SSE
  // command, 401 retry, pre-emptive refresh, re-login) shows up here.
  String? _lastAccess;
  String? _lastRefresh;
  int _rotations = 0;
  DateTime? _rotatedAt;

  @override
  void initState() {
    super.initState();
    final api = ref.read(apiServiceProvider);
    _lastAccess = api.getAccessToken();
    _lastRefresh = api.getRefreshToken();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final api = ref.read(apiServiceProvider);
    final a = api.getAccessToken();
    final r = api.getRefreshToken();
    if (a != _lastAccess || r != _lastRefresh) {
      _rotations++;
      _rotatedAt = DateTime.now();
      _lastAccess = a;
      _lastRefresh = r;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(apiServiceProvider);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final sse = ref.read(sseServiceProvider);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Tokens', style: theme.textTheme.titleMedium),
                const SizedBox(width: 16),
                ValueListenableBuilder<SseStatus>(
                  valueListenable: sse.status,
                  builder: (_, s, __) => _Chip(
                    label: 'SSE: ${s.state.name}'
                        '${s.lastFrameAt == null ? '' : ' · last frame ${_ago(now.difference(s.lastFrameAt!))} ago'}',
                    color: s.state == SseConnectionState.live
                        ? Colors.green
                        : theme.colorScheme.error,
                  ),
                ),
                const Spacer(),
                Text(
                  'Rotations seen: $_rotations'
                  '${_rotatedAt == null ? '' : ' · last ${_ago(now.difference(_rotatedAt!))} ago'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _rotatedAt != null &&
                            now.difference(_rotatedAt!) < const Duration(seconds: 10)
                        ? Colors.green
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _reveal = !_reveal),
                  child: Text(_reveal ? 'Hide' : 'Show full'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The backend refresh_token command only arrives while a cashier is '
              'signed in and SSE is connected — open this page from the user menu.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _tokenRow(
              context,
              label: 'Access token',
              token: api.getAccessToken(),
              clientExpiry: api.getAccessExpiresAt(),
              now: now,
            ),
            const Divider(height: 24),
            _tokenRow(
              context,
              label: 'Refresh token (sign-in)',
              token: api.getRefreshToken(),
              clientExpiry: api.getRefreshExpiresAt(),
              now: now,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tokenRow(
    BuildContext context, {
    required String label,
    required String? token,
    required DateTime? clientExpiry,
    required DateTime now,
  }) {
    final theme = Theme.of(context);
    final claims = ApiService.jwtPayload(token);
    DateTime? claimTime(String k) {
      final v = claims?[k];
      final secs = v is int ? v : int.tryParse('${v ?? ''}');
      return secs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    }

    final iat = claimTime('iat');
    final jwtExp = claimTime('exp');
    // What the till acts on. Differs from the JWT when Test mode simulated an
    // expiry, or (access token) when it was computed from `expiresIn`.
    final exp = clientExpiry ?? jwtExp;
    final simulated = clientExpiry != null &&
        jwtExp != null &&
        // The access expiry is computed from `expiresIn` on arrival, so it sits a
        // few seconds off the JWT naturally; only a real gap is a simulation.
        clientExpiry.difference(jwtExp).abs() > const Duration(minutes: 1);

    final left = exp?.difference(now);
    final expired = left != null && left.isNegative;
    final countdown = left == null
        ? 'unknown'
        : expired
            ? 'EXPIRED ${_fmt(-left)} ago'
            : 'expires in ${_fmt(left)}';

    String shown;
    if (token == null) {
      shown = '(none)';
    } else if (_reveal || token.length <= 24) {
      shown = token;
    } else {
      shown = '${token.substring(0, 16)}…${token.substring(token.length - 10)}'
          '  (${token.length} chars)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            Text(
              countdown,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: expired
                    ? theme.colorScheme.error
                    : (left != null && left < const Duration(days: 1))
                        ? const Color(0xFFB26A00)
                        : Colors.green,
              ),
            ),
            if (simulated) ...[
              const SizedBox(width: 8),
              const _Chip(label: 'simulated', color: Color(0xFFB26A00)),
            ],
            const Spacer(),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: token == null
                  ? null
                  : () => Clipboard.setData(ClipboardData(text: token)),
            ),
          ],
        ),
        SelectableText(shown,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          'issued ${iat ?? '?'}   ·   JWT exp ${jwtExp ?? '?'}'
          '${simulated ? '   ·   till acts on $clientExpiry' : ''}'
          '${claims?['jti'] != null ? '   ·   jti ${claims!['jti']}' : ''}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  static String _fmt(Duration d) {
    final days = d.inDays;
    final h = d.inHours.remainder(24).toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return days > 0 ? '${days}d $h:$m:$s' : '$h:$m:$s';
  }

  static String _ago(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    return '${d.inHours}h';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      );
}
