import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../providers/notes_provider.dart';
import '../../services/permission_service.dart';
import '../../utils/app_localizations.dart';
import 'note_edit_dialog.dart';

Color _hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

enum _NotesViewMode { board, table }
enum _NoteFilter { all, linked, unlinked }

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  _NotesViewMode _viewMode = _NotesViewMode.board;
  _NoteFilter _filter = _NoteFilter.all;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final notesAsync = ref.watch(notesStreamProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.sticky_note_2_outlined,
                color: theme.colorScheme.onPrimary),
            const SizedBox(width: 8),
            Text(l10n.translate('notes')),
          ],
        ),
        actions: [
          // View toggle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SegmentedButton<_NotesViewMode>(
              segments: [
                ButtonSegment(
                  value: _NotesViewMode.board,
                  icon: const Icon(Icons.dashboard_outlined, size: 16),
                  label: Text(l10n.translate('board_view'),
                      style: const TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: _NotesViewMode.table,
                  icon: const Icon(Icons.table_rows_outlined, size: 16),
                  label: Text(l10n.translate('table_view'),
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (s) =>
                  setState(() => _viewMode = s.first),
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact),
            ),
          ),
          const SizedBox(width: 8),

          // Clear all
          notesAsync.when(
            data: (notes) => notes.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: l10n.translate('clear_all_notes'),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () => _confirmClearAll(context, l10n),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddNote(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.translate('add_note')),
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (notes) {
          final filtered = _applyFilter(notes);
          if (filtered.isEmpty) return _buildEmpty(context, l10n, theme);
          return _viewMode == _NotesViewMode.board
              ? _BoardView(
                  notes: filtered,
                  onEdit: (n) => _openEditNote(context, n),
                  onDelete: (n) => _deleteNote(context, n, l10n),
                  onMoved: (id, x, y) =>
                      ref.read(noteNotifierProvider.notifier).moveNote(id, x, y),
                )
              : _TableView(
                  notes: filtered,
                  filter: _filter,
                  searchQuery: _searchQuery,
                  onFilterChanged: (f) => setState(() => _filter = f),
                  onSearchChanged: (q) => setState(() => _searchQuery = q),
                  onEdit: (n) => _openEditNote(context, n),
                  onDelete: (n) => _deleteNote(context, n, l10n),
                );
        },
      ),
    );
  }

  List<Note> _applyFilter(List<Note> notes) {
    var list = notes;
    if (_filter == _NoteFilter.linked) {
      list = list.where((n) => n.orderId != null).toList();
    } else if (_filter == _NoteFilter.unlinked) {
      list = list.where((n) => n.orderId == null).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((n) =>
              n.content.toLowerCase().contains(q) ||
              (n.orderCode ?? '').toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  Widget _buildEmpty(
      BuildContext context, AppLocalizations l10n, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sticky_note_2_outlined,
              size: 72,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(l10n.translate('no_notes'),
              style: theme.textTheme.titleMedium?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 8),
          Text(l10n.translate('add_first_note'),
              style: TextStyle(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.4))),
        ],
      ),
    );
  }

  bool _requirePermission(BuildContext context, String permission, AppLocalizations l10n) {
    if (ref.read(permissionServiceProvider).hasPermission(permission)) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.translate('no_permission')),
        backgroundColor: Colors.red,
      ),
    );
    return false;
  }

  void _openAddNote(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!_requirePermission(context, Permissions.notesCreate, l10n)) return;
    showDialog(
        context: context, builder: (_) => const NoteEditDialog());
  }

  void _openEditNote(BuildContext context, Note note) {
    final l10n = AppLocalizations.of(context)!;
    if (!_requirePermission(context, Permissions.notesUpdate, l10n)) return;
    showDialog(
        context: context,
        builder: (_) => NoteEditDialog(existingNote: note));
  }

  Future<void> _deleteNote(
      BuildContext context, Note note, AppLocalizations l10n) async {
    if (!_requirePermission(context, Permissions.notesDelete, l10n)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.translate('delete_note')),
        content: Text(l10n.translate('confirm_delete_note')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.translate('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.translate('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(noteNotifierProvider.notifier).deleteNote(note.id);
    }
  }

  Future<void> _confirmClearAll(
      BuildContext context, AppLocalizations l10n) async {
    if (!_requirePermission(context, Permissions.notesDelete, l10n)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.translate('clear_all_notes')),
        content: Text(l10n.translate('confirm_clear_all_notes')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.translate('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.translate('clear_all_notes')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(noteNotifierProvider.notifier).clearAll();
    }
  }
}

// ─── Board View ──────────────────────────────────────────────────────────────

class _BoardView extends StatefulWidget {
  final List<Note> notes;
  final void Function(Note) onEdit;
  final void Function(Note) onDelete;
  final void Function(int id, double x, double y) onMoved;

  const _BoardView({
    required this.notes,
    required this.onEdit,
    required this.onDelete,
    required this.onMoved,
  });

  @override
  State<_BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<_BoardView> {
  final Map<int, Offset> _localPos = {};

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InteractiveViewer(
      boundaryMargin: const EdgeInsets.all(400),
      minScale: 0.3,
      maxScale: 3.0,
      child: SizedBox(
        width: 2000,
        height: 1400,
        child: Stack(
          children: [
            CustomPaint(painter: _GridPainter(isDark: isDark)),
            for (final note in widget.notes)
              _DraggableNote(
                key: ValueKey(note.id),
                note: note,
                localPos: _localPos[note.id],
                onDragEnd: (offset) {
                  setState(() => _localPos[note.id] = offset);
                  widget.onMoved(note.id, offset.dx, offset.dy);
                },
                onEdit: () => widget.onEdit(note),
                onDelete: () => widget.onDelete(note),
              ),
          ],
        ),
      ),
    );
  }
}

class _DraggableNote extends StatefulWidget {
  final Note note;
  final Offset? localPos;
  final void Function(Offset) onDragEnd;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DraggableNote({
    super.key,
    required this.note,
    required this.localPos,
    required this.onDragEnd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_DraggableNote> createState() => _DraggableNoteState();
}

class _DraggableNoteState extends State<_DraggableNote> {
  late double _x;
  late double _y;
  Offset _dragStart = Offset.zero;
  double _startX = 0, _startY = 0;

  @override
  void initState() {
    super.initState();
    _x = widget.localPos?.dx ?? widget.note.posX;
    _y = widget.localPos?.dy ?? widget.note.posY;
  }

  @override
  void didUpdateWidget(_DraggableNote old) {
    super.didUpdateWidget(old);
    if (widget.localPos == null) {
      _x = widget.note.posX;
      _y = widget.note.posY;
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final bgColor = _hexToColor(note.color);
    final isDark = bgColor.computeLuminance() < 0.5;
    final textColor = isDark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final headerColor = isDark
        ? Colors.black.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.08);

    return Positioned(
      left: _x,
      top: _y,
      child: GestureDetector(
        onPanStart: (d) {
          _dragStart = d.globalPosition;
          _startX = _x;
          _startY = _y;
        },
        onPanUpdate: (d) {
          final delta = d.globalPosition - _dragStart;
          setState(() {
            _x = (_startX + delta.dx).clamp(0.0, 1900.0);
            _y = (_startY + delta.dy).clamp(0.0, 1300.0);
          });
        },
        onPanEnd: (_) => widget.onDragEnd(Offset(_x, _y)),
        onDoubleTap: widget.onEdit,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: note.width,
            constraints: BoxConstraints(
              minWidth: note.width,
              maxWidth: note.width,
              minHeight: note.height,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(3, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header bar
                Container(
                  height: 30,
                  decoration: BoxDecoration(
                    color: headerColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      const Icon(Icons.drag_indicator,
                          size: 14, color: Colors.black38),
                      const SizedBox(width: 4),
                      if (note.orderCode != null)
                        Expanded(
                          child: Text(
                            '📋 ${note.orderCode}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: textColor.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      InkWell(
                        onTap: widget.onEdit,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(Icons.edit_outlined,
                              size: 14,
                              color: textColor.withValues(alpha: 0.7)),
                        ),
                      ),
                      InkWell(
                        onTap: widget.onDelete,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.red),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    note.content.isEmpty ? '…' : note.content,
                    style: TextStyle(
                        fontSize: 13, color: textColor, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final bool isDark;
  const _GridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.grey.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
    const gap = 40.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.isDark != isDark;
}

// ─── Table View ──────────────────────────────────────────────────────────────

class _TableView extends StatelessWidget {
  final List<Note> notes;
  final _NoteFilter filter;
  final String searchQuery;
  final void Function(_NoteFilter) onFilterChanged;
  final void Function(String) onSearchChanged;
  final void Function(Note) onEdit;
  final void Function(Note) onDelete;

  const _TableView({
    required this.notes,
    required this.filter,
    required this.searchQuery,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Filter bar
        Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Search field
              SizedBox(
                width: 240,
                height: 38,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: l10n.translate('search'),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: isDark
                        ? theme.colorScheme.surfaceContainerHigh
                        : Colors.white,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  onChanged: onSearchChanged,
                ),
              ),
              const SizedBox(width: 12),

              // Filter chips
              ChoiceChip(
                label: Text(l10n.translate('all')),
                selected: filter == _NoteFilter.all,
                onSelected: (_) => onFilterChanged(_NoteFilter.all),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: Text(l10n.translate('linked_order')),
                selected: filter == _NoteFilter.linked,
                onSelected: (_) => onFilterChanged(_NoteFilter.linked),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: Text(l10n.translate('unlinked')),
                selected: filter == _NoteFilter.unlinked,
                onSelected: (_) => onFilterChanged(_NoteFilter.unlinked),
              ),
              const Spacer(),
              Text('${notes.length} ${l10n.translate('notes')}',
                  style: TextStyle(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6))),
            ],
          ),
        ),

        // Table
        Expanded(
          child: DataTable2(
            columnSpacing: 12,
            horizontalMargin: 16,
            headingRowHeight: 42,
            dataRowHeight: 58,
            headingRowColor: WidgetStatePropertyAll(
                theme.colorScheme.surfaceContainerLow),
            columns: [
              DataColumn2(
                  label: Text(l10n.translate('note_color')),
                  fixedWidth: 64),
              DataColumn2(
                  label: Text(l10n.translate('note_content')),
                  size: ColumnSize.L),
              DataColumn2(
                  label: Text(l10n.translate('linked_order')),
                  fixedWidth: 160),
              DataColumn2(
                  label: Text(l10n.translate('date')), fixedWidth: 130),
              DataColumn2(
                  label: Text(l10n.translate('actions')),
                  fixedWidth: 90),
            ],
            rows: notes.map((note) {
              return DataRow2(
                onTap: () => onEdit(note),
                cells: [
                  // Color swatch
                  DataCell(
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _hexToColor(note.color),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: isDark
                                ? Colors.white24
                                : Colors.black26),
                      ),
                    ),
                  ),
                  // Content preview
                  DataCell(
                    Text(
                      note.content.isEmpty ? '—' : note.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: theme.colorScheme.onSurface),
                    ),
                  ),
                  // Linked order chip
                  DataCell(
                    note.orderCode != null
                        ? Chip(
                            label: Text(note.orderCode!,
                                style:
                                    const TextStyle(fontSize: 12)),
                            avatar: const Icon(
                                Icons.receipt_outlined,
                                size: 14),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          )
                        : Text('—',
                            style: TextStyle(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4))),
                  ),
                  // Date
                  DataCell(
                    Text(
                      _formatDate(note.createdAt),
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7)),
                    ),
                  ),
                  // Actions
                  DataCell(
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit_outlined,
                              size: 18,
                              color: theme.colorScheme.primary),
                          tooltip: l10n.translate('edit'),
                          onPressed: () => onEdit(note),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: Colors.red),
                          tooltip: l10n.translate('delete'),
                          onPressed: () => onDelete(note),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

