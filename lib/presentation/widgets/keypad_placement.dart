import 'dart:ui';

/// Which side of the field the pad sits on. The pointer points the other way.
enum PadSide { left, right, above, below }

/// Where the pad goes, and where its pointer goes on it.
class PadLayout {
  final PadSide side;

  /// Top-left of the pad, in the same space [fieldRect] was given in.
  final Offset position;

  /// How far the pointer slides from the centre of the pad's edge, so it keeps
  /// aiming at the field after the pad has been pushed back on screen.
  final double pointerShift;

  const PadLayout({
    required this.side,
    required this.position,
    required this.pointerShift,
  });

  @override
  String toString() => 'PadLayout(${side.name}, '
      '${position.dx.toStringAsFixed(0)},${position.dy.toStringAsFixed(0)}, '
      'pointer ${pointerShift.toStringAsFixed(0)})';
}

/// Decides where a keypad of [padSize] goes beside a field at [fieldRect],
/// inside a space of [space].
///
/// A pure function on purpose. The previous version computed a position once
/// when the pad opened and cached an offset for the whole time it was up —
/// which went wrong the moment anything moved. Minimising the window and
/// restoring it left the cached offset describing a screen that no longer
/// existed, and the pad came back somewhere off the edge.
///
/// Being pure means the caller can simply run it again on every layout, and
/// nothing can go stale. It also means the awkward cases are testable directly,
/// without a widget tree.
///
/// [panelExtent] is the pad's size *excluding* the pointer along the axis the
/// pointer sticks out on — the straight edge the arrow can slide along.
PadLayout layoutPad({
  required Rect fieldRect,
  required Size space,
  required Size padSize,
  required double gap,
  required double margin,
  required double cornerRadius,
  required double pointerSpread,
}) {
  final side = _chooseSide(fieldRect, space, padSize, gap);
  final horizontal = side == PadSide.left || side == PadSide.right;

  // Centred on the field, so the pad reads as belonging to it rather than
  // hanging off a corner.
  var position = switch (side) {
    PadSide.right => Offset(
        fieldRect.right + gap, fieldRect.center.dy - padSize.height / 2),
    PadSide.left => Offset(fieldRect.left - gap - padSize.width,
        fieldRect.center.dy - padSize.height / 2),
    PadSide.below => Offset(
        fieldRect.center.dx - padSize.width / 2, fieldRect.bottom + gap),
    PadSide.above => Offset(fieldRect.center.dx - padSize.width / 2,
        fieldRect.top - gap - padSize.height),
  };

  // Push it back inside. Centring means the pad hangs equally either side of
  // the field, so a field near an edge would put half the keys off screen.
  // Overlapping the field is bad; unreachable keys are worse.
  final maxX = space.width - padSize.width - margin;
  final maxY = space.height - padSize.height - margin;
  final clamped = Offset(
    maxX < margin ? margin : position.dx.clamp(margin, maxX),
    maxY < margin ? margin : position.dy.clamp(margin, maxY),
  );
  final shift = clamped - position;
  position = clamped;

  // The pointer undoes the shift, so it keeps aiming at the field — but only
  // as far as the pad's straight edge goes, or it would float off a corner.
  final limit = ((horizontal ? padSize.height : padSize.width) / 2) -
      cornerRadius -
      (pointerSpread / 2);
  final wanted = horizontal ? -shift.dy : -shift.dx;
  final pointerShift = limit <= 0 ? 0.0 : wanted.clamp(-limit, limit);

  return PadLayout(side: side, position: position, pointerShift: pointerShift);
}

/// Sides first and widest-first: a POS screen is wide and short, so the room is
/// at the sides, and a pad there covers nothing the cashier is reading. Below
/// and above are the fallbacks; the last resort still picks the roomier side
/// rather than refusing to open.
PadSide _chooseSide(Rect field, Size space, Size pad, double gap) {
  final right = space.width - field.right - gap;
  final left = field.left - gap;
  final below = space.height - field.bottom - gap;
  final above = field.top - gap;

  if (right >= pad.width && right >= left) return PadSide.right;
  if (left >= pad.width) return PadSide.left;
  if (below >= pad.height) return PadSide.below;
  if (above >= pad.height) return PadSide.above;
  return right >= left ? PadSide.right : PadSide.left;
}
