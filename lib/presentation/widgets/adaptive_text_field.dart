import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import 'keypad_field.dart';

/// Drop-in replacement for [OnscreenKeyboardTextField] that degrades to a plain
/// [TextField] when the on-screen keyboard is not mounted.
///
/// Why this exists: `OnscreenKeyboardTextField` calls `OnscreenKeyboard.of()`
/// from its `initState`, and that method ends in `provider!.state` — guarded
/// only by an `assert`. So with no `OnscreenKeyboard` ancestor in the tree it
/// throws (an AssertionError in debug, a null-check TypeError in release) while
/// the widget is being inserted, which takes down the whole subtree — in
/// practice, the dialog the field lives in.
///
/// That ancestor is absent in more situations than it looks:
///   * the `showOnscreenKeyboard` setting is off — `main.dart` then skips
///     `OnscreenKeyboard.builder` entirely, so nothing is mounted;
///   * the builder threw and `main.dart`'s catch fell back to the bare child.
///
/// Either way every dialog carrying one of these fields becomes a crash. This
/// widget probes for the ancestor and picks the right field, so the keyboard
/// setting only changes how you type — never whether the screen opens.
class AdaptiveKeyboardTextField extends ConsumerStatefulWidget {
  final TextEditingController? controller;

  /// Seed text for callers that have no controller of their own — the
  /// `TextFormField(initialValue:)` shape. Ignored when [controller] is given.
  ///
  /// Needed because the on-screen keyboard types into ONE globally-registered
  /// field, and only an [OnscreenKeyboardTextField] registers itself. A plain
  /// `TextFormField` never claims that slot, so the keyboard keeps typing into
  /// whichever field claimed it last — which is how typing in Settings ended up
  /// in the product search.
  final String? initialValue;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool autofocus;
  final bool obscureText;
  final bool? enabled;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final TapRegionCallback? onTapOutside;

  const AdaptiveKeyboardTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.obscureText = false,
    this.enabled,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTapOutside,
  });

  /// Probe rather than read the setting: this tests the actual precondition
  /// (is the provider in the tree?), so it stays correct even when the tree and
  /// the setting disagree — which is exactly the case `main.dart`'s fallback
  /// creates. `OnscreenKeyboard.of` throws when absent in both debug and
  /// release, so the try/catch covers both builds.
  static bool _keyboardAvailable(BuildContext context) {
    try {
      OnscreenKeyboard.of(context);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  ConsumerState<AdaptiveKeyboardTextField> createState() =>
      _AdaptiveKeyboardTextFieldState();
}

class _AdaptiveKeyboardTextFieldState
    extends ConsumerState<AdaptiveKeyboardTextField> {
  /// Created only when the caller supplied none, and disposed with this state.
  TextEditingController? _ownController;
  FocusNode? _ownFocusNode;

  /// Always a real node, even when the caller passed none: the selection
  /// repair below has to listen to the node the field actually uses.
  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());

  TextEditingController? get _controller {
    if (widget.controller != null) return widget.controller;
    if (widget.initialValue == null) return null;
    return _ownController ??=
        TextEditingController(text: widget.initialValue);
  }

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode.addListener(_repairSelectionOnFocus);
  }

  @override
  void didUpdateWidget(AdaptiveKeyboardTextField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocusNode)
          ?.removeListener(_repairSelectionOnFocus);
      _effectiveFocusNode.addListener(_repairSelectionOnFocus);
    }

    // Re-seed an owned controller when the caller's `initialValue` moved
    // underneath us — settings pages rebuild after every save — but never
    // while the field is focused, which would fight the person typing.
    final seed = widget.initialValue;
    if (widget.controller == null &&
        seed != null &&
        _ownController != null &&
        !_effectiveFocusNode.hasFocus &&
        _ownController!.text != seed) {
      _ownController!.value = TextEditingValue(
        text: seed,
        selection: TextSelection.collapsed(offset: seed.length),
      );
    }
  }

  /// The on-screen keyboard drops every keystroke when the target
  /// controller's selection is invalid (`offset == -1`) — see
  /// `_handleTexTextKeyDown` in flutter_onscreen_keyboard, which is gated on
  /// `controller.selection.isValid`. A controller built as
  /// `TextEditingController(text: …)` starts in exactly that state, which is
  /// how seeded fields ended up looking like the keyboard "does nothing".
  /// Park the caret at the end of the text once focus lands.
  void _repairSelectionOnFocus() {
    if (!_effectiveFocusNode.hasFocus) return;
    // Post-frame so this runs after the field's own focus handling and only
    // patches a selection nothing else has claimed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_effectiveFocusNode.hasFocus) return;
      final controller = _controller;
      if (controller == null || controller.selection.isValid) return;
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
    });
  }

  @override
  void dispose() {
    (widget.focusNode ?? _ownFocusNode)
        ?.removeListener(_repairSelectionOnFocus);
    _ownFocusNode?.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  /// The number keyboards the beta pad can stand in for.
  ///
  /// Only these: a phone field wants `+` and `#`, and a text field wants
  /// letters. Anything the pad cannot type is left exactly as it was.
  static bool _isNumberType(TextInputType? type) {
    if (type == null) return false;
    return type == TextInputType.number ||
        type == const TextInputType.numberWithOptions(decimal: true) ||
        type == const TextInputType.numberWithOptions(signed: true) ||
        type ==
            const TextInputType.numberWithOptions(decimal: true, signed: true);
  }

  /// Whether this particular field should get the beta keypad.
  ///
  /// Deliberately narrow. The switch is global, but it only reaches fields
  /// that ask for a number, are editable, hold a single line, and have a
  /// controller for the pad to type into. Everything else falls through to the
  /// behaviour that shipped, so the setting can be turned off and the app is
  /// exactly as it was.
  bool get _useKeypad {
    if (!ref.watch(numericKeypadBetaProvider)) return false;
    if (!_isNumberType(widget.keyboardType)) return false;
    if (widget.enabled == false) return false;
    if ((widget.maxLines ?? 1) != 1) return false;
    return _controller != null;
  }

  @override
  Widget build(BuildContext context) {
    if (_useKeypad) {
      final type = widget.keyboardType!;
      return KeypadField(
        controller: _controller!,
        focusNode: _effectiveFocusNode,
        decoration: widget.decoration,
        style: widget.style,
        obscureText: widget.obscureText,
        autofocus: widget.autofocus,
        // The keyboard type already says what the field accepts, so the pad
        // takes its keys from the same declaration rather than a second one.
        allowDecimal: type.decimal ?? false,
        allowNegative: type.signed ?? false,
        maxLength: widget.maxLength,
        textInputAction: widget.textInputAction,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      );
    }

    if (!AdaptiveKeyboardTextField._keyboardAvailable(context)) {
      return TextField(
        controller: _controller,
        focusNode: _effectiveFocusNode,
        decoration: widget.decoration,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        textCapitalization: widget.textCapitalization,
        style: widget.style,
        textAlign: widget.textAlign,
        autofocus: widget.autofocus,
        obscureText: widget.obscureText,
        enabled: widget.enabled,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        maxLength: widget.maxLength,
        inputFormatters: widget.inputFormatters,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onEditingComplete: widget.onEditingComplete,
        onTapOutside: widget.onTapOutside,
      );
    }

    return OnscreenKeyboardTextField(
      controller: _controller,
      focusNode: _effectiveFocusNode,
      decoration: widget.decoration,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      style: widget.style,
      textAlign: widget.textAlign,
      autofocus: widget.autofocus,
      obscureText: widget.obscureText,
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onEditingComplete: widget.onEditingComplete,
      onTapOutside: widget.onTapOutside,
    );
  }
}
