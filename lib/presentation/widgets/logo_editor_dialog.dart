import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';

import '../../services/printing_service.dart';
import '../../utils/app_localizations.dart';

/// The logo settings this dialog returns. Null means the operator cancelled.
class LogoEditResult {
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final int widthPercent;
  final LogoAlign align;

  const LogoEditResult({
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    required this.widthPercent,
    required this.align,
  });
}

/// Crop, size and position the printed business logo.
///
/// Nothing here touches the picked image: the crop is a box in fractions of
/// the source, so it stays adjustable and reopening the dialog shows the whole
/// logo again with the current box on it. [PrintingService] applies the same
/// box at print time.
class LogoEditorDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final PrinterConfig config;

  const LogoEditorDialog({
    super.key,
    required this.imageBytes,
    required this.config,
  });

  @override
  State<LogoEditorDialog> createState() => _LogoEditorDialogState();
}

class _LogoEditorDialogState extends State<LogoEditorDialog> {
  late Rect _crop; // normalised 0..1 against the source image
  late int _widthPercent;
  late LogoAlign _align;

  /// How close to a corner a touch has to land to grab it, in logical pixels.
  /// Generous, because this runs on a POS touch screen and the handles are
  /// small.
  static const double _grabRadius = 36;

  /// The smallest crop the handles may produce, as a fraction of the source.
  /// Small enough to be a genuine detail crop, large enough that the box can
  /// always be grabbed again.
  static const double _minSide = 0.05;

  _Handle? _dragging;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _crop = Rect.fromLTRB(
      c.logoCropLeft,
      c.logoCropTop,
      c.logoCropRight,
      c.logoCropBottom,
    );
    _widthPercent = c.logoWidthPercent;
    _align = c.logoAlign;
  }

  void _reset() {
    setState(() {
      _crop = const Rect.fromLTRB(0, 0, 1, 1);
      _widthPercent = 100;
      _align = LogoAlign.center;
    });
  }

  /// Which part of the box a touch at [p] (normalised) has taken hold of.
  _Handle _handleAt(Offset p, Size box) {
    final r = _grabRadius / box.width;
    final rv = _grabRadius / box.height;
    final nearL = (p.dx - _crop.left).abs() < r;
    final nearR = (p.dx - _crop.right).abs() < r;
    final nearT = (p.dy - _crop.top).abs() < rv;
    final nearB = (p.dy - _crop.bottom).abs() < rv;
    if (nearL && nearT) return _Handle.topLeft;
    if (nearR && nearT) return _Handle.topRight;
    if (nearL && nearB) return _Handle.bottomLeft;
    if (nearR && nearB) return _Handle.bottomRight;
    return _Handle.move;
  }

  void _applyDrag(Offset delta, Size box) {
    final dx = delta.dx / box.width;
    final dy = delta.dy / box.height;
    setState(() {
      switch (_dragging!) {
        case _Handle.move:
          // Slide the whole box, stopping at the edges rather than shrinking.
          final nx = (_crop.left + dx).clamp(0.0, 1.0 - _crop.width);
          final ny = (_crop.top + dy).clamp(0.0, 1.0 - _crop.height);
          _crop = Rect.fromLTWH(nx, ny, _crop.width, _crop.height);
        case _Handle.topLeft:
          _crop = Rect.fromLTRB(
            (_crop.left + dx).clamp(0.0, _crop.right - _minSide),
            (_crop.top + dy).clamp(0.0, _crop.bottom - _minSide),
            _crop.right,
            _crop.bottom,
          );
        case _Handle.topRight:
          _crop = Rect.fromLTRB(
            _crop.left,
            (_crop.top + dy).clamp(0.0, _crop.bottom - _minSide),
            (_crop.right + dx).clamp(_crop.left + _minSide, 1.0),
            _crop.bottom,
          );
        case _Handle.bottomLeft:
          _crop = Rect.fromLTRB(
            (_crop.left + dx).clamp(0.0, _crop.right - _minSide),
            _crop.top,
            _crop.right,
            (_crop.bottom + dy).clamp(_crop.top + _minSide, 1.0),
          );
        case _Handle.bottomRight:
          _crop = Rect.fromLTRB(
            _crop.left,
            _crop.top,
            (_crop.right + dx).clamp(_crop.left + _minSide, 1.0),
            (_crop.bottom + dy).clamp(_crop.top + _minSide, 1.0),
          );
      }
    });
  }

  /// Printable width in dots for the configured paper, matching what
  /// [PrintingService] uses when it rasterises the logo.
  int get _paperDots => widget.config.paperSize == PaperSize.mm58 ? 384 : 576;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.translate('logo_editor')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate('logo_crop_hint'),
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              _buildCropArea(theme),
              const SizedBox(height: 20),

              // ---- width ----
              Row(
                children: [
                  const Icon(Icons.photo_size_select_large, size: 20),
                  const SizedBox(width: 8),
                  Text(l10n.translate('logo_width'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Text(
                    '$_widthPercent%  '
                    '(${(_paperDots * _widthPercent / 100).round()} px)',
                    style: TextStyle(
                        fontSize: 14, color: theme.colorScheme.primary),
                  ),
                ],
              ),
              Slider(
                value: _widthPercent.toDouble(),
                min: 10,
                max: 100,
                divisions: 18,
                label: '$_widthPercent%',
                onChanged: (v) => setState(() => _widthPercent = v.round()),
              ),

              // ---- alignment ----
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.align_horizontal_center, size: 20),
                  const SizedBox(width: 8),
                  Text(l10n.translate('logo_alignment'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 8),
              SegmentedButton<LogoAlign>(
                segments: [
                  ButtonSegment(
                    value: LogoAlign.left,
                    icon: const Icon(Icons.format_align_left),
                    label: Text(l10n.translate('align_left')),
                  ),
                  ButtonSegment(
                    value: LogoAlign.center,
                    icon: const Icon(Icons.format_align_center),
                    label: Text(l10n.translate('align_center')),
                  ),
                  ButtonSegment(
                    value: LogoAlign.right,
                    icon: const Icon(Icons.format_align_right),
                    label: Text(l10n.translate('align_right')),
                  ),
                ],
                selected: {_align},
                onSelectionChanged: (s) => setState(() => _align = s.first),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt),
          label: Text(l10n.translate('reset')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('cancel')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(
            LogoEditResult(
              cropLeft: _crop.left,
              cropTop: _crop.top,
              cropRight: _crop.right,
              cropBottom: _crop.bottom,
              widthPercent: _widthPercent,
              align: _align,
            ),
          ),
          child: Text(l10n.translate('save')),
        ),
      ],
    );
  }

  /// The image with the crop box over it.
  ///
  /// The box is drawn against the widget's own rectangle rather than against
  /// the image's painted bounds, so the preview shows the image stretched to
  /// fill it. That keeps the fractions the box reports exactly the fractions
  /// the printer will crop by, with no letterboxing to compensate for.
  Widget _buildCropArea(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        const h = 240.0;
        final box = Size(w, h);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            final p = Offset(
                d.localPosition.dx / w, d.localPosition.dy / h);
            _dragging = _handleAt(p, box);
          },
          onPanUpdate: (d) {
            if (_dragging != null) _applyDrag(d.delta, box);
          },
          onPanEnd: (_) => _dragging = null,
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    widget.imageBytes,
                    fit: BoxFit.fill,
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(Icons.broken_image,
                          size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  CustomPaint(
                    painter: _CropPainter(_crop, theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _Handle { move, topLeft, topRight, bottomLeft, bottomRight }

/// Dims everything outside the crop box and marks its corners.
class _CropPainter extends CustomPainter {
  final Rect crop;
  final Color color;

  _CropPainter(this.crop, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );

    // Everything outside the box, dimmed, drawn as one even-odd path so the
    // kept area stays untouched.
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: 0.45));

    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );

    final handle = Paint()..color = color;
    const s = 7.0;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      canvas.drawCircle(c, s, handle);
      canvas.drawCircle(c, s - 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.crop != crop || old.color != color;
}
