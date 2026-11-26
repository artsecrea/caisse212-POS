import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../utils/app_localizations.dart';
import '../../utils/phone_normalizer.dart';
import 'customer_selection_dialog.dart';
import 'name_conflict_dialog.dart';
import '../../utils/snackbar_helper.dart';

/// Shown right before the cashier confirms an external order (DealUp /
/// WhatsApp queue item). Lets them review the customer the source sent,
/// optionally edit it (or pick a different existing customer altogether),
/// then returns the resolved local customer id to the caller.
///
/// Returns via `Navigator.pop(int?)`:
///   - the resolved local customer id on Save/Pick,
///   - `null` if the cashier cancels — callers treat that as "abort the
///     whole confirm; queue item stays PENDING".
class ExternalCustomerReviewDialog extends ConsumerStatefulWidget {
  final String? suggestedName;
  final String? suggestedPhone;

  const ExternalCustomerReviewDialog({
    super.key,
    this.suggestedName,
    this.suggestedPhone,
  });

  @override
  ConsumerState<ExternalCustomerReviewDialog> createState() =>
      _ExternalCustomerReviewDialogState();
}

class _ExternalCustomerReviewDialogState
    extends ConsumerState<ExternalCustomerReviewDialog> {
  bool _isOpeningChild = false;

  /// Split the queue's free-form customer name into first / rest on
  /// whitespace. Matches the algorithm already used in
  /// `ExternalOrderQueueService.acknowledgeAndSave` so behavior stays
  /// consistent whether the cashier sees this dialog or it's bypassed.
  ({String firstName, String lastName}) _splitName() {
    final raw = (widget.suggestedName ?? '').trim();
    if (raw.isEmpty) return (firstName: '', lastName: '');
    final parts = raw.split(RegExp(r'\s+'));
    return (
      firstName: parts.first,
      lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
    );
  }

  Future<void> _onSaveOrModify() async {
    if (_isOpeningChild) return;
    setState(() => _isOpeningChild = true);
    // Any uncaught throw below used to leave `_isOpeningChild = true` forever,
    // disabling every button — a frozen-looking dialog. Guard the whole flow;
    // the finally clause guarantees the buttons come back.
    try {
      await _saveOrModifyFlow();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showToast('Error: $e', kind: ToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _isOpeningChild = false);
    }
  }

  Future<void> _saveOrModifyFlow() async {
    final customers = ref.read(customerRepositoryProvider);
    final split = _splitName();
    final queueFullName =
        '${split.firstName} ${split.lastName}'.trim();
    final phoneRaw = widget.suggestedPhone?.trim() ?? '';

    // Conflict detection — runs BEFORE the add form opens. If the queue
    // sent a phone that maps to a stored customer with a different name,
    // the cashier picks Keep / Use New in a focused dialog. This avoids
    // the awkward "edit a pre-filled form to reach the same outcome"
    // dance and surfaces the conflict explicitly so a misspelled
    // WhatsApp name doesn't silently clobber a stored "Ali" into a
    // typo.
    if (phoneRaw.isNotEmpty) {
      final phoneNorm = normalizePhone(phoneRaw);
      if (phoneNorm.isNotEmpty) {
        final existing = await customers.findByPhoneNormalized(phoneNorm);
        if (existing != null) {
          final existingFullName =
              '${existing.firstName} ${existing.lastName}'.trim();
          // Conflict only when the queue actually provided a name AND
          // it differs from what's stored. Case-insensitive comparison
          // — "Ali Bennani" vs "ali bennani" isn't a conflict.
          final namesDiffer = queueFullName.isNotEmpty &&
              existingFullName.toLowerCase() !=
                  queueFullName.toLowerCase();
          if (namesDiffer) {
            if (!mounted) return;
            final choice = await showDialog<NameConflictChoice>(
              context: context,
              barrierDismissible: false,
              builder: (_) => NameConflictDialog(
                existingName: existingFullName.isEmpty
                    ? phoneRaw
                    : existingFullName,
                newName: queueFullName,
                phone: phoneRaw,
              ),
            );
            if (!mounted) return;
            if (choice == null) {
              // Cashier cancelled the conflict prompt — back to review.
              // (_isOpeningChild is reset by the caller's finally.)
              return;
            }
            if (choice == NameConflictChoice.keepExisting) {
              // No upsert, no form. The existing row is the customer.
              Navigator.of(context).pop(existing.id);
              return;
            }
            // Use New → upsert directly without showing the add form.
            // The cashier already declared intent; no need to re-edit.
            final overriddenId = await customers.upsertByPhone(
              phoneRaw: phoneRaw,
              firstName: split.firstName,
              lastName: split.lastName,
              isSynced: false,
            );
            if (!mounted) return;
            if (overriddenId != null) {
              Navigator.of(context).pop(overriddenId);
            }
            return;
          }
        }
      }
    }

    // No conflict — show the standard add/edit form pre-filled with
    // the queue values. Same code path as before.
    final result = await showPrefilledAddCustomerDialog(
      context,
      customers: customers,
      initialFirstName: split.firstName,
      initialLastName: split.lastName,
      initialPhone: widget.suggestedPhone,
    );
    if (!mounted) return;
    final id = result?['id'];
    if (id is int) {
      Navigator.of(context).pop(id);
    }
    // If the cashier cancelled the inner dialog, stay on this one so they
    // can try another path (Pick different / Cancel) rather than aborting
    // the whole confirm. (_isOpeningChild is reset by the caller's finally.)
  }

  Future<void> _onPickDifferent() async {
    if (_isOpeningChild) return;
    setState(() => _isOpeningChild = true);
    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => const CustomerSelectionDialog(),
      );
      if (!mounted) return;
      final id = result?['id'];
      // CustomerSelectionDialog returns `{id: null}` for "Unselect" — treat
      // that as "stay on this dialog" rather than "no customer", since this
      // flow always wants a customer linked.
      if (id is int) {
        Navigator.of(context).pop(id);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showToast('Error: $e', kind: ToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _isOpeningChild = false);
    }
  }

  void _onCancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final suggestedName = (widget.suggestedName ?? '').trim();
    final suggestedPhone = (widget.suggestedPhone ?? '').trim();

    final media = MediaQuery.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        // Cap width on big screens, shrink on phones, and cap height to the
        // space left above the on-screen keyboard so the content scrolls
        // instead of overflowing.
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: media.size.height - media.viewInsets.bottom - 32,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.person_search, color: colors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.translate('review_external_customer'),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: _isOpeningChild ? null : _onCancel,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Suggested-info card (what the external source claimed).
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    colors.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(
                    icon: Icons.person_outline,
                    label: l10n.translate('customer'),
                    value: suggestedName.isEmpty ? '—' : suggestedName,
                  ),
                  const SizedBox(height: 8),
                  _row(
                    icon: Icons.phone_outlined,
                    label: l10n.translate('phone'),
                    value: suggestedPhone.isEmpty ? '—' : suggestedPhone,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Primary CTA — Save / Modify (opens the add-customer form,
            // pre-filled with the values above).
            ElevatedButton.icon(
              onPressed: _isOpeningChild ? null : _onSaveOrModify,
              icon: const Icon(Icons.edit),
              label: Text(l10n.translate('save_or_modify')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 12),

            // Secondary CTA — Pick a different existing customer.
            OutlinedButton.icon(
              onPressed: _isOpeningChild ? null : _onPickDifferent,
              icon: const Icon(Icons.people_alt_outlined),
              label: Text(l10n.translate('pick_different_customer')),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 12),

            // Cancel — aborts the whole confirm.
            TextButton(
              onPressed: _isOpeningChild ? null : _onCancel,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                l10n.translate('cancel'),
                style: const TextStyle(fontSize: 16),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
