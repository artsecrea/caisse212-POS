import 'package:flutter/material.dart';

import 'keypad_field.dart';

/// A bench for [KeypadField], reachable only from a debug or profile build.
///
/// The keypad is not wired into any real screen yet: it was tried on the login
/// password and taken back off, because a half-working keyboard on the one
/// screen every shift starts with is worse than the plain field. It lives here
/// until it behaves, where it can be poked at without a cashier depending on it.
///
/// The fields below are the shapes the app actually needs — a PIN, a money
/// amount, a plain count — plus deliberately awkward placements (hard against
/// each edge) because the pad's positioning is where the bugs have been.
class KeypadLabScreen extends StatefulWidget {
  const KeypadLabScreen({super.key});

  @override
  State<KeypadLabScreen> createState() => _KeypadLabScreenState();
}

class _KeypadLabScreenState extends State<KeypadLabScreen> {
  final _pin = TextEditingController();
  final _amount = TextEditingController();
  final _count = TextEditingController();
  final _adjust = TextEditingController();
  final _edgeLeft = TextEditingController();
  final _edgeRight = TextEditingController();
  final _edgeTop = TextEditingController();
  final _edgeBottom = TextEditingController();

  /// Measured on demand, so the lab can report what the pad actually decided
  /// for each awkward placement rather than what it looked like it did.
  final _keys = <String, GlobalKey>{
    'far left': GlobalKey(),
    'far right': GlobalKey(),
    'top edge': GlobalKey(),
    'bottom edge': GlobalKey(),
  };
  String _report = '';

  /// How many times each awkward field has actually put a pad on screen, and
  /// whether one is up right now. Tapping a field and seeing "opened 1, now
  /// closed" means it opened and shut itself; "opened 0" means it never
  /// opened at all. The two faults look the same on screen.
  final _opens = <String, int>{};
  final _visible = <String, bool>{};

  void _padVisibility(String name, bool shown) {
    setState(() {
      _visible[name] = shown;
      if (shown) _opens[name] = (_opens[name] ?? 0) + 1;
    });
  }

  Widget _padStatus(String name) {
    final opens = _opens[name] ?? 0;
    final up = _visible[name] ?? false;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$name — opened $opens, now ${up ? "OPEN" : "closed"}',
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: opens == 0
              ? theme.colorScheme.error
              : theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  void _measure() {
    final lines = <String>[];

    // The overlay's box, because that is the space the pad is positioned in —
    // the same measurement the widget itself makes.
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) {
      setState(() => _report = 'no overlay to measure against');
      return;
    }
    final space = overlayBox.size;
    final view = View.of(context);
    final win = view.physicalSize / view.devicePixelRatio;

    lines.add('overlay ${space.width.toStringAsFixed(0)}'
        'x${space.height.toStringAsFixed(0)}'
        '   window ${win.width.toStringAsFixed(0)}'
        'x${win.height.toStringAsFixed(0)}'
        '   dpr ${view.devicePixelRatio}');

    for (final entry in _keys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        lines.add('${entry.key}: not laid out');
        continue;
      }
      final rect = MatrixUtils.transformRect(
          box.getTransformTo(overlayBox), Offset.zero & box.size);
      lines.add('${entry.key}: field '
          '${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)} '
          '${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)}'
          '\n   ${debugPlacementReport(rect, space)}');
    }
    setState(() => _report = lines.join('\n'));
  }

  @override
  void dispose() {
    for (final c in [
      _pin,
      _amount,
      _count,
      _adjust,
      _edgeLeft,
      _edgeRight,
      _edgeTop,
      _edgeBottom,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Keypad lab'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Debug build only — not reachable in release',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
            children: [
              _section('The shapes the app needs'),
              _labelled(
                'PIN — obscured, 4 digits max',
                KeypadField(
                  controller: _pin,
                  obscureText: true,
                  maxLength: 4,
                  decoration: _dec('PIN', Icons.lock_outline),
                ),
                _pin,
              ),
              _labelled(
                'Amount — decimal point',
                KeypadField(
                  controller: _amount,
                  allowDecimal: true,
                  decoration: _dec('Amount', Icons.payments_outlined),
                ),
                _amount,
              ),
              _labelled(
                'Count — digits only',
                KeypadField(
                  controller: _count,
                  decoration: _dec('Quantity', Icons.numbers),
                ),
                _count,
              ),
              _labelled(
                'Adjustment — can go negative',
                KeypadField(
                  controller: _adjust,
                  allowDecimal: true,
                  allowNegative: true,
                  decoration: _dec('Adjustment', Icons.swap_vert),
                ),
                _adjust,
              ),
              const SizedBox(height: 8),
              _section('Placement — where the bugs have been'),
              Text(
                'The pad picks the side with the most room and slides back on '
                'screen when there is none. These four sit hard against an '
                'edge on purpose.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: KeypadField(
                      key: _keys['far left'],
                      onPadVisibility: (v) => _padVisibility('far left', v),
                      controller: _edgeLeft,
                      decoration: _dec('Far left', Icons.west),
                    ),
                  ),
                  const SizedBox(width: 200),
                  Expanded(
                    child: KeypadField(
                      key: _keys['far right'],
                      onPadVisibility: (v) => _padVisibility('far right', v),
                      controller: _edgeRight,
                      decoration: _dec('Far right', Icons.east),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // A plain field, to compare focus behaviour against.
              TextField(
                decoration: _dec('Ordinary field', Icons.keyboard_alt_outlined),
              ),
              const SizedBox(height: 16),
              _padStatus('far left'),
              _padStatus('far right'),
              _padStatus('top edge'),
              _padStatus('bottom edge'),
              const SizedBox(height: 20),
              _section('What the pad decided'),
              FilledButton.tonalIcon(
                onPressed: _measure,
                icon: const Icon(Icons.straighten, size: 18),
                label: const Text('Measure the awkward fields'),
              ),
              if (_report.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _report,
                    style: const TextStyle(
                        fontSize: 11, fontFamily: 'monospace', height: 1.5),
                  ),
                ),
              ],
            ],
          ),
          // Pinned to the very top and bottom edges: the cases where centring
          // the pad on the field would hang half of it off the screen.
          Positioned(
            top: 0,
            left: 24,
            width: 260,
            child: KeypadField(
              key: _keys['top edge'],
                      onPadVisibility: (v) => _padVisibility('top edge', v),
              controller: _edgeTop,
              decoration: _dec('Top edge', Icons.north),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 24,
            width: 260,
            child: KeypadField(
              key: _keys['bottom edge'],
                      onPadVisibility: (v) => _padVisibility('bottom edge', v),
              controller: _edgeBottom,
              decoration: _dec('Bottom edge', Icons.south),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );

  /// Each field with a live readout of its controller, so it is obvious
  /// whether a key actually landed.
  Widget _labelled(String note, Widget field, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(note, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          field,
          const SizedBox(height: 4),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: c,
            builder: (context, value, _) => Text(
              'value: "${value.text}"   caret: ${value.selection.baseOffset}',
              style: TextStyle(
                  fontSize: 11, fontFamily: 'monospace', color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      );
}
