import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value, OrderingTerm;
import '../../data/database/app_database.dart';
import '../../providers/notes_provider.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../utils/app_localizations.dart';
import './adaptive_text_field.dart';

const _kNoteColors = [
  '#FFFF88', // yellow
  '#FFB3BA', // pink
  '#BAFFC9', // green
  '#BAE1FF', // blue
  '#E8BAFF', // purple
  '#FFD9BA', // orange
  '#FFFFFF', // white
  '#E0E0E0', // grey
];

Color _hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

class NoteEditDialog extends ConsumerStatefulWidget {
  final Note? existingNote;
  const NoteEditDialog({super.key, this.existingNote});

  @override
  ConsumerState<NoteEditDialog> createState() => _NoteEditDialogState();
}

class _NoteEditDialogState extends ConsumerState<NoteEditDialog> {
  final _contentController = TextEditingController();
  final _contentFocus = FocusNode();
  late String _selectedColor;
  int? _linkedOrderId;
  String? _linkedOrderCode;

  @override
  void initState() {
    super.initState();
    final note = widget.existingNote;
    _selectedColor = note?.color ?? '#FFFF88';
    _contentController.text = note?.content ?? '';

    if (note != null) {
      _linkedOrderId = note.orderId;
      _linkedOrderCode = note.orderCode;
    } else {
      // Pre-select the active POS order if one is loaded
      final current = ref.read(orderProvider);
      if (current.orderId != null && current.orderCode != null) {
        _linkedOrderId = current.orderId;
        _linkedOrderCode = current.orderCode;
      }
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEditing = widget.existingNote != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final dialogBg = isDark
        ? theme.colorScheme.surface
        : _hexToColor(_selectedColor);

    final inputFill = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : Colors.black.withValues(alpha: 0.06);

    final labelStyle = TextStyle(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 660),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Icon(Icons.sticky_note_2_outlined,
                      size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    isEditing
                        ? l10n.translate('edit_note')
                        : l10n.translate('add_note'),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    tooltip: l10n.translate('close'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Color palette
              Text(l10n.translate('note_color'), style: labelStyle),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _kNoteColors.map((hex) {
                    final isSelected = _selectedColor == hex;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedColor = hex),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _hexToColor(hex),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : (isDark ? Colors.white30 : Colors.black26),
                              width: isSelected ? 3 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.4),
                                      blurRadius: 6,
                                    )
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? Icon(Icons.check,
                                  size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant)
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Content textarea with onscreen keyboard
              Text(l10n.translate('note_content'), style: labelStyle),
              const SizedBox(height: 8),
              AdaptiveKeyboardTextField(
                controller: _contentController,
                focusNode: _contentFocus,
                maxLines: 6,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.translate('note_content_hint'),
                  filled: true,
                  fillColor: inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: theme.colorScheme.outline
                            .withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: theme.colorScheme.outline
                            .withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: theme.colorScheme.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Order link picker
              _OrderLinkPicker(
                selectedOrderId: _linkedOrderId,
                onSelected: (id, code) => setState(() {
                  _linkedOrderId = id;
                  _linkedOrderCode = code;
                }),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.translate('cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: Icon(isEditing ? Icons.save_outlined : Icons.add),
                    label: Text(isEditing
                        ? l10n.translate('save')
                        : l10n.translate('add_note')),
                    onPressed: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    final notifier = ref.read(noteNotifierProvider.notifier);

    if (widget.existingNote == null) {
      await notifier.addNote(
        content: content,
        color: _selectedColor,
        orderId: _linkedOrderId,
        orderCode: _linkedOrderCode,
      );
    } else {
      await notifier.updateNote(widget.existingNote!.copyWith(
        content: content,
        color: _selectedColor,
        orderId: Value(_linkedOrderId),
        orderCode: Value(_linkedOrderCode),
        updatedAt: DateTime.now(),
      ));
    }
    if (mounted) Navigator.pop(context);
  }
}

// ─── Order link picker ────────────────────────────────────────────────────────

class _OrderLinkPicker extends ConsumerWidget {
  final int? selectedOrderId;
  final void Function(int? id, String? code) onSelected;

  const _OrderLinkPicker({
    required this.selectedOrderId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final db = ref.watch(databaseProvider);

    return FutureBuilder<List<Order>>(
      future: (db.select(db.orders)
            ..where((o) => o.status.isNotIn(['CANCELLED']))
            ..orderBy([(o) => OrderingTerm.desc(o.createdAt)])
            ..limit(100))
          .get(),
      builder: (context, snap) {
        final orders = snap.data ?? [];
        final dropdownItems = <DropdownMenuItem<int?>>[
          DropdownMenuItem<int?>(
            value: null,
            child: Row(
              children: [
                Icon(Icons.link_off,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 8),
                Text(l10n.translate('no_linked_order'),
                    style: TextStyle(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6))),
              ],
            ),
          ),
          ...orders.map((o) => DropdownMenuItem<int?>(
                value: o.id,
                child: Row(
                  children: [
                    Icon(Icons.receipt_outlined,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${o.code}  •  ${o.status}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('linked_order'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: selectedOrderId,
              isExpanded: true,
              dropdownColor: isDark
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark
                    ? theme.colorScheme.surfaceContainerHighest
                    : Colors.black.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: theme.colorScheme.primary, width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: dropdownItems,
              onChanged: (id) {
                final code = id == null
                    ? null
                    : orders.firstWhere((o) => o.id == id).code;
                onSelected(id, code);
              },
            ),
          ],
        );
      },
    );
  }
}
