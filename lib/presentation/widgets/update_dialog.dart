import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/update_provider.dart';

/// Update dialog that shows when an update is available
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

    if (updateInfo == null) return const SizedBox.shrink();

    return WillPopScope(
      onWillPop: () async => !isMandatory,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              isMandatory ? Icons.warning : Icons.info_outline,
              color: isMandatory ? Colors.orange : Colors.blue,
            ),
            const SizedBox(width: 8),
            Text(isMandatory ? 'Update Required' : 'Update Available'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Version ${updateInfo.version} is available',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (updateInfo.releaseNotes.isNotEmpty) ...[
                const Text(
                  'What\'s New:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    updateInfo.releaseNotes,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (isMandatory)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange[800], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This is a mandatory update. You must update to continue using the app.',
                          style: TextStyle(
                            color: Colors.orange[900],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (updateState.isDownloading) ...[
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Downloading... ${(updateState.downloadProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: updateState.downloadProgress,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
              if (updateState.error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red[800], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          updateState.error!,
                          style: TextStyle(
                            color: Colors.red[900],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!isMandatory && !updateState.isDownloading)
            TextButton(
              onPressed: () {
                ref.read(updateProvider.notifier).dismissUpdate();
                Navigator.of(context).pop();
              },
              child: const Text('Later'),
            ),
          ElevatedButton(
            onPressed: updateState.isDownloading
                ? null
                : () async {
                    final success = await ref.read(updateProvider.notifier).downloadAndInstall();

                    if (success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Update started. Please follow the installation instructions.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      Navigator.of(context).pop();
                    }
                  },
            child: updateState.isDownloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Update Now'),
          ),
        ],
      ),
    );
  }
}

/// Show update dialog
void showUpdateDialog(BuildContext context, {required bool isMandatory}) {
  showDialog(
    context: context,
    barrierDismissible: !isMandatory,
    builder: (context) => UpdateDialog(isMandatory: isMandatory),
  );
}
