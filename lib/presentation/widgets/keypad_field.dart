import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_localizations.dart';
import 'keypad_placement.dart';

/// A text field that opens a keypad **beside itself** instead of a keyboard
/// across the bottom of the screen.
///
/// The app's other on-screen keyboard is a full-width bar pinned to the bottom.
/// On a till that is the wrong shape twice over: it covers whatever is below
/// the field — routinely the button you are about to press — and it puts the
/// digits a screen-height away from what you are typing into. For numeric
/// entry, which is most entry on a POS, a small pad anchored to the field is
/// faster and hides nothing.
///
/// The pad opens when the field takes focus, with one exception: the focus a
/// window hands back to its last-focused widget when it is re-activated, which
/// would otherwise pop the keypad open every time someone alt-tabbed in.
///
/// The platform keyboard is suppressed ([readOnly] with a visible cursor), so a
/// tablet does not raise its own keyboard over this one. A hardware keyboard
/// still works — the field keeps focus and its own key handling.
class KeypadField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration? decoration;
  final TextStyle? style;
  final bool obscureText;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Adds a decimal key. Off for PINs and counts, on for money and weights.
  final bool allowDecimal;

  /// Adds a sign key, for a field that can go below zero.
  final bool allowNegative;

  /// Longest value the pad will produce. Null for no limit. Guards a PIN box
  /// against a leaned-on key.
  final int? maxLength;

  /// Fired by the pad's confirm key, and by Enter on a hardware keyboard.
  final ValueChanged<String>? onSubmitted;

  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  /// Fires true when the pad goes on screen and false when it comes off.
  ///
  /// For the debug lab, which needs to tell "the pad never opened" apart from
  /// "the pad opened and you cannot see it" — two faults that look identical
  /// from the outside and have nothing in common underneath.
  final ValueChanged<bool>? onPadVisibility;

  const KeypadField({
    super.key,
    required this.controller,
    this.decoration,
    this.style,
    this.obscureText = false,
    this.autofocus = false,
    this.focusNode,
    this.allowDecimal = false,
    this.allowNegative = false,
    this.maxLength,
    this.onSubmitted,
    this.onChanged,
    this.textInputAction,
    this.onPadVisibility,
  });

  @override
  State<KeypadField> createState() => _KeypadFieldState();
}

class _KeypadFieldState extends State<KeypadField>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Ties the field and its pad together for tap-outside purposes, so that
  /// pressing a key does not read as "the user tapped somewhere else".
  final Object _groupId = Object();

  late final FocusNode _focusNode;
  late final AnimationController _anim;
  bool _ownsFocusNode = false;
  OverlayEntry? _entry;

  /// The panel, without the pointer. Fixed, so the keys are always the same
  /// size as each other and the arrow always has a straight edge to sit on.

  static const double _arrowThickness = 9;
  static const double _arrowSpread = 20;
  static const double _arrowOverlap = 1;
  static const double _gap = 10;
  static const double _margin = 8;
  static const double _radius = 14;

  /// The two footprints the pad can have: the pointer grows it only along the
  /// axis it points down.
  static const double _panelWidth = 264;
  static const double _panelHeight = 336;
  static const double _arrowGrowth = _arrowThickness - _arrowOverlap;
  static const Size _sideways =
      Size(_panelWidth + _arrowGrowth, _panelHeight);
  static const Size _stacked =
      Size(_panelWidth, _panelHeight + _arrowGrowth);

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addObserver(this);
    // Short enough to feel instant — the pad answers a tap, and anything
    // slower reads as lag when a cashier is typing at speed.
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 100),
    );
  }

  /// The field has left the tree — a route pushed over it, a rebuild that
  /// dropped it, the app shutting down.
  ///
  /// The pad goes here rather than in [dispose], because between the two the
  /// element is *deactivated*: still `mounted`, but with no render object to
  /// answer geometry questions. An overlay laid out in that window would ask
  /// this field where it is and hit an assertion.
  @override
  void deactivate() {
    _entry?.remove();
    _entry = null;
    super.deactivate();
  }

  @override
  void dispose() {
    // Belt and braces: normally gone already in deactivate.
    _entry?.remove();
    _entry = null;
    _anim.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.removeListener(_onFocusChanged);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  /// When the app was last brought back to the foreground.
  ///
  /// The window handing focus back to its last-focused widget is the one focus
  /// gain that must NOT open the pad — otherwise alt-tabbing to the till pops
  /// the keypad open with nobody having touched it.
  DateTime? _resumedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resumedAt = DateTime.now();
  }

  /// The window changed shape — minimised, restored, resized, moved to another
  /// monitor. The overlay does not rebuild on its own for that, and everything
  /// the pad needs is read fresh at build time, so a nudge is all it takes.
  @override
  void didChangeMetrics() => _entry?.markNeedsBuild();

  bool get _justResumed {
    final at = _resumedAt;
    return at != null &&
        DateTime.now().difference(at) < const Duration(milliseconds: 700);
  }

  /// Focus opens the pad, and losing focus closes it.
  ///
  /// Focus rather than tap: `onTap` does not fire on every platform for a
  /// read-only field, and when it did not, the pad never opened and the field
  /// was simply dead.
  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      if (!_justResumed) _openPad();
    } else {
      _hidePad();
    }
  }

  void _openPad() {
    if (_entry != null) return;
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
    if (overlay == null) {
      // Nowhere to put a pad. Give the field back to the platform rather than
      // leaving the cashier with an input they cannot type into.
      if (!_padUnavailable) setState(() => _padUnavailable = true);
      return;
    }

    // The Overlay's own context, captured now. The entry's build context has
    // no render object during its first build, so asking *it* for geometry
    // returns nothing and the pad renders as an empty box that never retries.
    _overlayContext = overlay.context;
    _entry = OverlayEntry(builder: (_) => _buildPad());
    overlay.insert(_entry!);
    _anim.forward();
    widget.onPadVisibility?.call(true);
  }

  BuildContext? _overlayContext;

  /// Set when there was no overlay to host the pad. The field then behaves like
  /// an ordinary one — a degraded keyboard beats a dead field.
  bool _padUnavailable = false;

  /// The pad, positioned from whatever the geometry is *now*.
  ///
  /// This is the point of the rewrite. The previous version worked out a
  /// position once when the pad opened and cached an offset for as long as it
  /// stayed up. Minimise the window and restore it and that offset described a
  /// screen that no longer existed, so the pad came back off the edge.
  ///
  /// `LayoutBuilder` hands over the overlay's current size on every layout, and
  /// the field's rectangle is read in the same breath, so the two can never
  /// describe different frames and nothing survives long enough to go stale.
  Widget _buildPad() {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final space = constraints.biggest;
          final field = _fieldRect();

          // Nothing sensible to place against — a minimised window reports no
          // size at all. Draw nothing rather than a pad hanging off an edge;
          // the layout that follows the restore puts it back properly.
          if (field == null ||
              space.isEmpty ||
              !space.width.isFinite ||
              !space.height.isFinite) {
            // Try again next frame. A field mid-layout, or a window with no
            // size because it is minimised, both land here — and both resolve
            // themselves, so long as something asks again.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _entry?.markNeedsBuild();
            });
            return const SizedBox.shrink();
          }

          final layout = _layoutFor(field, space);
          final padSize =
              layout.side == PadSide.left || layout.side == PadSide.right
                  ? _sideways
                  : _stacked;

          return Stack(
            children: [
              Positioned(
                left: layout.position.dx,
                top: layout.position.dy,
                width: padSize.width,
                height: padSize.height,
                child: TapRegion(
                  groupId: _groupId,
                  child: _AnimatedPad(
                    animation: _anim,
                    origin: _growFrom(layout.side),
                    child: _PointedPad(
                      side: layout.side,
                      pointerShift: layout.pointerShift,
                      child: _KeypadPanel(
                        controller: widget.controller,
                        obscure: widget.obscureText,
                        onKey: _onKey,
                        onSubmit: _submit,
                        allowDecimal: widget.allowDecimal,
                        allowNegative: widget.allowNegative,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The pad's footprint depends on which side it lands on, and the side
  /// depends on the footprint. Settled by asking with the sideways footprint
  /// first — the only one that can change the answer — and asking again with
  /// the taller one if that lands above or below.
  PadLayout _layoutFor(Rect field, Size space) {
    PadLayout run(Size padSize) => layoutPad(
          fieldRect: field,
          space: space,
          padSize: padSize,
          gap: _gap,
          margin: _margin,
          cornerRadius: _radius,
          pointerSpread: _arrowSpread,
        );

    final first = run(_sideways);
    if (first.side == PadSide.left || first.side == PadSide.right) return first;
    return run(_stacked);
  }

  /// The field's rectangle in the overlay's coordinate space — the space the
  /// pad is positioned in. Null when either box is not laid out yet.
  Rect? _fieldRect() {
    // The overlay can be laid out once more while this field is being torn
    // down; a defunct element has no render object to ask.
    if (!mounted) return null;
    // The overlay can outlive or predecease this field during a route swap;
    // either way an unmounted context has no render object to ask.
    final overlayContext = _overlayContext;
    if (overlayContext == null || !overlayContext.mounted) return null;

    // Guarded rather than asserted: the overlay can be laid out in the window
    // between this field being deactivated and disposed, when it is still
    // `mounted` but has no render object. Failing to null is exactly right —
    // the caller draws nothing and asks again next frame.
    try {
      final box = context.findRenderObject() as RenderBox?;
      final overlayBox = overlayContext.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      if (overlayBox == null || !overlayBox.hasSize) return null;
      if (!box.attached || !overlayBox.attached) return null;
      return MatrixUtils.transformRect(
          box.getTransformTo(overlayBox), Offset.zero & box.size);
    } catch (_) {
      return null;
    }
  }

  /// The edge the pad scales out of — the one facing the field.
  static Alignment _growFrom(PadSide side) => switch (side) {
        PadSide.right => Alignment.centerLeft,
        PadSide.left => Alignment.centerRight,
        PadSide.below => Alignment.topCenter,
        PadSide.above => Alignment.bottomCenter,
      };

  /// Play the pad out, then take it down.
  ///
  /// The entry is cleared immediately so a re-open during the closing
  /// animation builds a fresh one rather than adopting a pad on its way out.
  void _hidePad() {
    final closing = _entry;
    if (closing == null) return;
    _entry = null;
    _anim.reverse().whenComplete(closing.remove);
    widget.onPadVisibility?.call(false);
  }

  // ── Editing ───────────────────────────────────────────────────────────────

  void _onKey(String key) {
    switch (key) {
      case _KeypadPanel.backspace:
        _backspace();
      case _KeypadPanel.clear:
        _replaceAll('');
      default:
        _insert(key);
    }
  }

  /// Where the caret is, falling back to the end of the text.
  ///
  /// A controller that has never been focused reports an invalid selection
  /// (offset -1); treating that as "the end" is what a cashier expects when
  /// they tap a field that already has a value in it.
  TextSelection get _selection {
    final value = widget.controller.value;
    if (value.selection.isValid) return value.selection;
    return TextSelection.collapsed(offset: value.text.length);
  }

  void _insert(String key) {
    final text = widget.controller.text;
    final selection = _selection;

    // One decimal point, and only where it can mean something — "1.2.3" and a
    // bare "." are both things the parse on the other side would reject.
    if (key == '.') {
      if (!widget.allowDecimal || text.contains('.')) return;
    }
    // A sign belongs at the front or nowhere.
    if (key == '-') {
      if (!widget.allowNegative) return;
      _replaceAll(text.startsWith('-') ? text.substring(1) : '-$text');
      return;
    }

    final next = text.replaceRange(selection.start, selection.end, key);
    if (widget.maxLength != null && next.length > widget.maxLength!) return;

    _setValue(next, selection.start + key.length);
  }

  void _backspace() {
    final text = widget.controller.text;
    final selection = _selection;

    if (selection.start != selection.end) {
      _setValue(text.replaceRange(selection.start, selection.end, ''),
          selection.start);
      return;
    }
    if (selection.start == 0) return;
    _setValue(text.replaceRange(selection.start - 1, selection.start, ''),
        selection.start - 1);
  }

  void _replaceAll(String text) => _setValue(text, text.length);

  void _setValue(String text, int caret) {
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret.clamp(0, text.length)),
    );
    widget.onChanged?.call(text);
  }

  void _submit() {
    _focusNode.unfocus();
    widget.onSubmitted?.call(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _groupId,
      onTapOutside: (_) {
        if (_entry != null) _focusNode.unfocus();
      },
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        obscureText: widget.obscureText,
        decoration: widget.decoration,
        style: widget.style,
        textInputAction: widget.textInputAction,
        keyboardType: TextInputType.number,
        // Read-only with a visible cursor: the field still takes focus, shows a
        // caret and accepts a hardware keyboard, but the platform will not put
        // its own keyboard over this one.
        readOnly: !_padUnavailable,
        showCursor: true,
        enableInteractiveSelection: true,
        // Tapping a field that already holds focus brings the pad back after a
        // dismissal — focus alone would not fire again.
        onTap: _openPad,
        // TextField's own default unfocuses on any tap outside *the field*, and
        // the pad is outside the field — so pressing a key closed the pad and
        // typing was limited to a single digit. Dismissal is handled by the
        // TapRegion above, which knows the pad is ours.
        onTapOutside: _padUnavailable ? null : (_) {},
        onSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// What the pad would do for a field occupying [fieldRect] in [space].
///
/// Exists so the debug lab can show the real decision rather than a copy of the
/// rule that could drift from it.
@visibleForTesting
String debugPlacementReport(Rect fieldRect, Size space) {
  final layout = layoutPad(
    fieldRect: fieldRect,
    space: space,
    padSize: _KeypadFieldState._sideways,
    gap: _KeypadFieldState._gap,
    margin: _KeypadFieldState._margin,
    cornerRadius: _KeypadFieldState._radius,
    pointerSpread: _KeypadFieldState._arrowSpread,
  );
  final size = layout.side == PadSide.left || layout.side == PadSide.right
      ? _KeypadFieldState._sideways
      : _KeypadFieldState._stacked;
  final rect = layout.position & size;

  final onScreen = rect.left >= 0 &&
      rect.top >= 0 &&
      rect.right <= space.width &&
      rect.bottom <= space.height;

  return 'side=${layout.side.name}'
      '  pad=${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)}'
      ' ${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}'
      '  pointer=${layout.pointerShift.toStringAsFixed(0)}'
      '  ${onScreen ? "on-screen" : "OFF-SCREEN"}';
}

/// Fade, scale and a short travel toward the field.
///
/// Scaling from 0.94 rather than 0: a pad that inflates from nothing draws the
/// eye to the animation instead of to the keys, and the cashier is already
/// looking where it will be.
class _AnimatedPad extends StatelessWidget {
  final Animation<double> animation;
  final Alignment origin;
  final Widget child;

  const _AnimatedPad({
    required this.animation,
    required this.origin,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: eased,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(eased),
        alignment: origin,
        // Keys must never take focus: the field's focus is what holds the pad
        // open, so a focusable key would close the pad by being pressed.
        child: ExcludeFocus(child: child),
      ),
    );
  }
}

/// The pad with a little triangle joining it to the field.
class _PointedPad extends StatelessWidget {
  final PadSide side;
  final double pointerShift;
  final Widget child;

  const _PointedPad({
    required this.side,
    required this.pointerShift,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final horizontal = side == PadSide.left || side == PadSide.right;

    final arrow = Transform.translate(
      offset: horizontal ? Offset(0, pointerShift) : Offset(pointerShift, 0),
      child: CustomPaint(
        key: const Key('keypad-pointer'),
        size: horizontal
            ? const Size(_KeypadFieldState._arrowThickness,
                _KeypadFieldState._arrowSpread)
            : const Size(_KeypadFieldState._arrowSpread,
                _KeypadFieldState._arrowThickness),
        painter:
            _PointerPainter(side: side, color: _KeypadPanel.shellOf(context)),
      ),
    );

    // The arrow tucks under the panel by a hair so the seam does not show.
    const overlap = _KeypadFieldState._arrowOverlap;

    return switch (side) {
      PadSide.right => Row(
          children: [
            arrow,
            Expanded(
              child: Transform.translate(
                  offset: const Offset(-overlap, 0), child: child),
            ),
          ],
        ),
      PadSide.left => Row(
          children: [
            Expanded(
              child: Transform.translate(
                  offset: const Offset(overlap, 0), child: child),
            ),
            arrow,
          ],
        ),
      PadSide.below => Column(
          children: [
            arrow,
            Expanded(
              child: Transform.translate(
                  offset: const Offset(0, -overlap), child: child),
            ),
          ],
        ),
      PadSide.above => Column(
          children: [
            Expanded(
              child: Transform.translate(
                  offset: const Offset(0, overlap), child: child),
            ),
            arrow,
          ],
        ),
    };
  }
}

/// A triangle pointing at the field, in the panel's shell colour.
class _PointerPainter extends CustomPainter {
  final PadSide side;
  final Color color;

  const _PointerPainter({required this.side, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // The tip points away from the pad, toward the field.
    final path = switch (side) {
      PadSide.right => Path()
        ..moveTo(w, 0)
        ..lineTo(0, h / 2)
        ..lineTo(w, h),
      PadSide.left => Path()
        ..moveTo(0, 0)
        ..lineTo(w, h / 2)
        ..lineTo(0, h),
      PadSide.below => Path()
        ..moveTo(0, h)
        ..lineTo(w / 2, 0)
        ..lineTo(w, h),
      PadSide.above => Path()
        ..moveTo(0, 0)
        ..lineTo(w / 2, h)
        ..lineTo(w, 0),
    };

    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PointerPainter old) =>
      old.side != side || old.color != color;
}

/// The floating pad itself.
///
/// It carries its own palette rather than the app's surface tones. An earlier
/// version drew near-white keys on a near-white panel inside a near-white login
/// screen, and the whole thing dissolved into the page. A keypad is an
/// instrument: it should read as a physical object sitting on top of the
/// screen, which means a dark shell with light keys on it, at any theme
/// brightness.
class _KeypadPanel extends StatelessWidget {
  static const String backspace = '⌫';
  static const String clear = 'C';

  static const Color keyFace = Color(0xFFF7F8FA);
  static const Color keyText = Color(0xFF20242C);
  static const Color editKey = Color(0xFF57617A);
  static const Color accent = Color(0xFFF4703A);

  /// The shell colour for the current theme — the pointer borrows it so the
  /// arrow and the panel are visibly one object.
  static Color shellOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF171B22)
          : const Color(0xFF2E3440);

  /// Watched so the pad can show the value it is producing. Reading it here
  /// means the eye never has to travel back to the field between keystrokes —
  /// which is the whole reason the pad sits beside it.
  final TextEditingController controller;
  final bool obscure;

  final ValueChanged<String> onKey;
  final VoidCallback onSubmit;
  final bool allowDecimal;
  final bool allowNegative;

  const _KeypadPanel({
    required this.controller,
    required this.obscure,
    required this.onKey,
    required this.onSubmit,
    required this.allowDecimal,
    required this.allowNegative,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    // Phone order (1 at the top left), not calculator order. A PIN is read off
    // a card or remembered like a phone number, and every card terminal a
    // cashier has ever used is laid out this way.
    final rows = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      [
        if (allowNegative) '-' else if (allowDecimal) '.' else clear,
        '0',
        backspace,
      ],
    ];

    return Container(
      key: const Key('keypad-panel'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_KeypadFieldState._radius),
        // A shallow gradient rather than a flat fill: it gives the shell a
        // top-lit look, so the pad reads as a moulded object instead of a
        // rectangle of colour.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF232833), Color(0xFF13161C)]
              : const [Color(0xFF3A424F), Color(0xFF262C36)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        // Two shadows: a tight one to seat it and a wide soft one for depth.
        // One shadow alone either floats or looks pasted on.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 28,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            _buildReadout(),
            // Expanded, so the keys divide whatever the readout and the confirm
            // button leave. The panel's height is fixed, so the keys are what
            // flexes — and they stay identical to each other.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  children: [
                    for (final row in rows)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              for (final key in row)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 3),
                                    child: _PadKey(
                                      label: key,
                                      isEdit: key == backspace || key == clear,
                                      onTap: () => onKey(key),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: onSubmit,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          l10n?.translate('done') ?? 'Done',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The value so far, across the head of the pad.
  ///
  /// Sunk into the shell rather than laid on top of it — an inset well with a
  /// recessed gradient, so it reads as the display of an instrument instead of
  /// a coloured stripe.
  Widget _buildReadout() {
    return Container(
      width: double.infinity,
      height: 52,
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        // Darker at the top, so the well looks recessed. A two-tone Border
        // would say the same thing but cannot carry a corner radius, so the lip
        // is done with the gradient instead.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.38),
            Colors.black.withValues(alpha: 0.22),
          ],
        ),
        border: Border.all(color: Colors.black.withValues(alpha: 0.35)),
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          // Dots for a PIN: the pad must not become the thing that shows a
          // password to the room the field was careful to hide it from.
          final shown = obscure ? '•' * value.text.length : value.text;
          final empty = shown.isEmpty;
          return Text(
            empty ? '–' : shown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: obscure ? 4 : 1,
              color: empty ? Colors.white24 : Colors.white,
              // Digits that do not shuffle sideways as the value grows.
              fontFeatures: const [FontFeature.tabularFigures()],
              shadows: empty
                  ? null
                  : [
                      Shadow(
                        color: accent.withValues(alpha: 0.55),
                        blurRadius: 12,
                      ),
                    ],
            ),
          );
        },
      ),
    );
  }
}

/// One key.
///
/// Its own widget so it can carry a pressed state: on a touch screen with no
/// travel, the key visibly sinking is the difference between "I pressed that"
/// and "did that register?". The ripple alone reads as too slow at the speed a
/// cashier types.
class _PadKey extends StatefulWidget {
  final String label;
  final bool isEdit;
  final VoidCallback onTap;

  const _PadKey({
    required this.label,
    required this.isEdit,
    required this.onTap,
  });

  @override
  State<_PadKey> createState() => _PadKeyState();
}

class _PadKeyState extends State<_PadKey> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    // Digits are the bright keys — the thing pressed hundreds of times a day
    // should be the clearest target. Edit keys recede into the shell so they
    // are not competing for the eye. Nothing is red: on a till red means
    // something went wrong, and clearing a PIN is not that.
    final face = widget.isEdit ? _KeypadPanel.editKey : _KeypadPanel.keyFace;
    final foreground = widget.isEdit ? Colors.white : _KeypadPanel.keyText;

    return AnimatedScale(
      scale: _down ? 0.94 : 1,
      duration: const Duration(milliseconds: 70),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          // Top-lit: a lighter edge along the top and a shadow beneath, so the
          // key looks raised off the shell rather than printed on it. Both go
          // flat while it is held down.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _down
                ? [face, face]
                : [
                    Color.alphaBlend(Colors.white.withValues(alpha: 0.10), face),
                    face,
                  ],
          ),
          boxShadow: _down
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // Never focusable: the field's focus is what holds the pad open.
            canRequestFocus: false,
            onTap: () {
              // Pressed hard and often on a till; the tick is the only feedback
              // there is when the screen has no travel.
              HapticFeedback.selectionClick();
              widget.onTap();
            },
            onTapDown: (_) => _set(true),
            onTapUp: (_) => _set(false),
            onTapCancel: () => _set(false),
            child: Center(
              child: widget.label == _KeypadPanel.backspace
                  ? Icon(Icons.backspace_outlined, size: 21, color: foreground)
                  : Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: foreground,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
