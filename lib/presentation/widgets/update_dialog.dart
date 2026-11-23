import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/update_provider.dart';
import '../../utils/app_localizations.dart';

/// Translates the notifier's error: either an l10n key it set itself, or a
/// raw exception from the download.
String updateErrorText(AppLocalizations l10n, String error) =>
    error.startsWith('update_')
        ? l10n.translate(error)
        : '${l10n.translate('update_download_failed')}\n$error';

class UpdateDialog extends ConsumerStatefulWidget {
  final bool isMandatory;

  const UpdateDialog({super.key, required this.isMandatory});

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  bool _closing = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _install() => ref.read(updateProvider.notifier).installNow();

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(updateProvider);
    final updateInfo = updateState.availableUpdate;
    final version = updateState.version;
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final screenH = MediaQuery.sizeOf(context).height;
    final isMandatory = widget.isMandatory;

    // The release was withdrawn while the dialog was open. Close it rather
    // than leave an empty, undismissable barrier over the till.
    if (version == null || (!updateState.hasUpdate && !updateState.updateReady)) {
      _close();
      return const SizedBox.shrink();
    }

    // A mandatory update can't be put off — unless installing it failed
    // (UAC refused, download host unreachable): the till must still sell.
    final canEscape = !isMandatory || updateState.error != null;

    return PopScope(
      canPop: canEscape,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: screenH * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                isMandatory: isMandatory,
                version: version,
                l10n: l10n,
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isMandatory) ...[
                        _MandatoryBanner(l10n: l10n),
                        const SizedBox(height: 16),
                      ],
                      if ((updateInfo?.releaseNotes ?? '').isNotEmpty) ...[
                        Text(
                          l10n.translate('update_whats_new'),
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: cs.primary,
                                letterSpacing: 0.5,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _ReleaseNotes(notes: updateInfo!.releaseNotes!),
                        const SizedBox(height: 16),
                      ],
                      if (updateState.isDownloading) ...[
                        _DownloadProgress(
                          progress: updateState.downloadProgress,
                          l10n: l10n,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (updateState.updateReady &&
                          !updateState.installRequested &&
                          !updateState.isApplying) ...[
                        Text(
                          l10n.translate('update_ready_restart_hint'),
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (updateState.error != null) ...[
                        _ErrorBanner(
                            message:
                                updateErrorText(l10n, updateState.error!)),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
              _Actions(
                canLater: canEscape,
                isMandatory: isMandatory,
                state: updateState,
                l10n: l10n,
                onInstall: _install,
                onLater: () {
                  ref.read(updateProvider.notifier).dismiss();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool isMandatory;
  final String version;
  final AppLocalizations l10n;

  const _Header({
    required this.isMandatory,
    required this.version,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = isMandatory ? cs.errorContainer : cs.primaryContainer;
    final fgColor = isMandatory ? cs.onErrorContainer : cs.onPrimaryContainer;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: fgColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isMandatory
                  ? Icons.system_update_alt_rounded
                  : Icons.new_releases_rounded,
              color: fgColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate(isMandatory
                      ? 'update_required_title'
                      : 'update_available_title'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: fgColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: fgColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'v$version',
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MandatoryBanner extends StatelessWidget {
  final AppLocalizations l10n;
  const _MandatoryBanner({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.translate('update_mandatory_notice'),
              style: TextStyle(
                color: cs.onErrorContainer,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseNotes extends StatelessWidget {
  final String notes;
  const _ReleaseNotes({required this.notes});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: SelectableText(
        notes,
        style: TextStyle(
          fontSize: 13,
          color: cs.onSurfaceVariant,
          height: 1.55,
        ),
      ),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  final double progress;
  final AppLocalizations l10n;

  const _DownloadProgress({required this.progress, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (progress * 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.translate('update_downloading_pct').replaceAll('{0}', '').replaceAll('%', '').trimRight(),
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: cs.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              message,
              style: TextStyle(
                color: cs.onErrorContainer,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final bool canLater;
  final bool isMandatory;
  final UpdateState state;
  final AppLocalizations l10n;
  final VoidCallback onInstall;
  final VoidCallback onLater;

  const _Actions({
    required this.canLater,
    required this.isMandatory,
    required this.state,
    required this.l10n,
    required this.onInstall,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Busy = download in flight, or install asked for and on its way.
    final busy = state.isApplying ||
        state.isDownloading && state.installRequested;

    final String label;
    if (state.isApplying) {
      label = l10n.translate('update_restarting');
    } else if (state.isDownloading) {
      label = l10n
          .translate('update_downloading_pct')
          .replaceAll('{0}', (state.downloadProgress * 100).toStringAsFixed(0));
    } else if (state.updateReady) {
      label = l10n.translate('update_restart_now');
    } else if (state.error != null) {
      label = l10n.translate('update_retry');
    } else {
      label = l10n.translate('update_now');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (canLater && !state.isApplying) ...[
            TextButton(
              onPressed: onLater,
              child: Text(l10n.translate('update_later')),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.icon(
            onPressed: busy ? null : onInstall,
            icon: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cs.onPrimary),
                  )
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(label),
          ),
        ],
      ),
    );
  }
}

/// Shows the dialog unless one is already up; returns when it closes — also
/// when it was already up, so a caller waits for the one on screen (the
/// UpdateWatcher may open it a moment earlier for the same update).
Future<void>? _openDialog;

Future<void> showUpdateDialog(BuildContext context,
    {required bool isMandatory}) {
  final open = _openDialog;
  if (open != null) return open;
  final shown = showDialog<void>(
    context: context,
    barrierDismissible: !isMandatory,
    builder: (context) => UpdateDialog(isMandatory: isMandatory),
  ).whenComplete(() => _openDialog = null);
  _openDialog = shown;
  return shown;
}
