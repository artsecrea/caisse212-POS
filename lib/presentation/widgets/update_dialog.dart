import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/update_provider.dart';
import '../../utils/app_localizations.dart';

class UpdateDialog extends ConsumerWidget {
  final bool isMandatory;

  const UpdateDialog({
    Key? key,
    required this.isMandatory,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateProvider);
    final updateInfo = updateState.availableUpdate;
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final screenH = MediaQuery.sizeOf(context).height;

    if (updateInfo == null) return const SizedBox.shrink();

    // The download finished while this dialog is still open — which only
    // happens for a foreground "Update Now" (or a mandatory forced download).
    // Apply immediately: close the app and relaunch into the new version.
    // The "Later" path closes the dialog first, so this never fires there and
    // the update just waits for the next manual launch.
    ref.listen<UpdateState>(updateProvider, (prev, next) {
      if (prev?.updateReady == false && next.updateReady) {
        ref.read(updateProvider.notifier).applyNow();
      }
    });

    return PopScope(
      canPop: !isMandatory,
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
              // ── Header ──────────────────────────────────────────────────────
              _Header(isMandatory: isMandatory, version: updateInfo.version),

              // ── Scrollable body ──────────────────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mandatory notice
                      if (isMandatory) ...[
                        _MandatoryBanner(l10n: l10n),
                        const SizedBox(height: 16),
                      ],

                      // Release notes
                      if ((updateInfo.releaseNotes ?? '').isNotEmpty) ...[
                        Text(
                          l10n.translate('update_whats_new'),
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: cs.primary,
                                letterSpacing: 0.5,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _ReleaseNotes(notes: updateInfo.releaseNotes!),
                        const SizedBox(height: 16),
                      ],

                      // Download progress
                      if (updateState.isDownloading) ...[
                        _DownloadProgress(
                          progress: updateState.downloadProgress,
                          l10n: l10n,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Error
                      if (updateState.error != null) ...[
                        _ErrorBanner(message: updateState.error!),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Actions ──────────────────────────────────────────────────────
              _Actions(
                isMandatory: isMandatory,
                isDownloading: updateState.isDownloading,
                isApplying: updateState.updateReady,
                l10n: l10n,
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

  const _Header({required this.isMandatory, required this.version});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgColor =
        isMandatory ? const Color(0xFFFFF3E0) : cs.primaryContainer;
    final iconColor =
        isMandatory ? Colors.orange[700]! : cs.onPrimaryContainer;
    final textColor =
        isMandatory ? Colors.orange[900]! : cs.onPrimaryContainer;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isMandatory
                  ? Icons.system_update_alt_rounded
                  : Icons.new_releases_rounded,
              color: iconColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMandatory ? 'Update required' : 'Update available',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                // Version badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'v$version',
                    style: TextStyle(
                      color: iconColor,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.translate('update_mandatory_notice'),
              style: const TextStyle(
                color: Colors.orange,
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
      // Text itself is flexible — no fixed height, scrolls via parent scroll view.
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
              l10n.translate('update_downloading_pct').replaceAll('{0}', '').trimRight(),
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

class _Actions extends ConsumerWidget {
  final bool isMandatory;
  final bool isDownloading;
  final bool isApplying;
  final AppLocalizations l10n;

  const _Actions({
    required this.isMandatory,
    required this.isDownloading,
    required this.isApplying,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    // Busy = download in flight OR the app is about to close & relaunch.
    final busy = isDownloading || isApplying;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!isMandatory && !busy) ...[
            TextButton(
              onPressed: () {
                // dismissUpdate() starts background download then clears dialog
                // state — the download continues silently and applies on the
                // next launch (no auto-restart).
                ref.read(updateProvider.notifier).dismissUpdate();
                Navigator.of(context).pop();
              },
              child: Text(l10n.translate('update_later')),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.icon(
            onPressed: busy
                ? null
                : () {
                    // Download in the foreground; when it completes the dialog's
                    // listener applies it immediately (close + relaunch).
                    ref.read(updateProvider.notifier).startDownload();
                  },
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(
              isApplying
                  ? l10n.translate('update_restarting')
                  : isDownloading
                      ? l10n
                          .translate('update_downloading_pct')
                          .replaceAll('{0}', '')
                          .trimRight()
                      : l10n.translate('update_now'),
            ),
          ),
        ],
      ),
    );
  }
}

void showUpdateDialog(BuildContext context, {required bool isMandatory}) {
  showDialog(
    context: context,
    barrierDismissible: !isMandatory,
    builder: (context) => UpdateDialog(isMandatory: isMandatory),
  );
}
