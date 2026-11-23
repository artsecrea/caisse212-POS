import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/app_localizations.dart';
import '../../utils/super_admin_auth.dart';
import '../widgets/adaptive_text_field.dart';
import 'super_admin_screen.dart';

/// Wraps the caisse logo: [kSuperAdminTapCount] quick taps ask for the super
/// admin code and open [SuperAdminScreen]. Inert on platforms other than
/// Windows and Linux, where it returns [child] untouched.
class SuperAdminTapTarget extends StatefulWidget {
  final Widget child;

  const SuperAdminTapTarget({super.key, required this.child});

  @override
  State<SuperAdminTapTarget> createState() => _SuperAdminTapTargetState();
}

class _SuperAdminTapTargetState extends State<SuperAdminTapTarget> {
  int _taps = 0;
  DateTime? _lastTap;
  bool _open = false;

  Future<void> _onTap() async {
    if (_open) return;
    final now = DateTime.now();
    final last = _lastTap;
    _taps = (last != null && now.difference(last) <= kSuperAdminTapWindow)
        ? _taps + 1
        : 1;
    _lastTap = now;
    if (_taps < kSuperAdminTapCount) return;

    _taps = 0;
    _lastTap = null;
    _open = true;
    try {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const SuperAdminUnlockDialog(),
      );
      if (ok != true || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SuperAdminScreen()),
      );
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!superAdminPlatformSupported) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: widget.child,
    );
  }
}

class SuperAdminUnlockDialog extends ConsumerStatefulWidget {
  const SuperAdminUnlockDialog({super.key});

  @override
  ConsumerState<SuperAdminUnlockDialog> createState() =>
      _SuperAdminUnlockDialogState();
}

class _SuperAdminUnlockDialogState
    extends ConsumerState<SuperAdminUnlockDialog> {
  final _controller = TextEditingController();
  bool _wrong = false;
  bool _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    setState(() => _wrong = false);
  }

  Future<void> _submit() async {
    if (_checking) return;
    setState(() => _checking = true);
    // Let the spinner paint before bcrypt blocks the isolate.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final ok = superAdminCodeAccepted(_controller.text, now: DateTime.now());
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _checking = false;
        _wrong = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.admin_panel_settings, color: scheme.error, size: 36),
      title: Text(l10n.translate('super_admin_mode')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // No autofocus: the on-screen keyboard would open over the paste
            // button, and nobody types a 60-character hash by hand.
            AdaptiveKeyboardTextField(
              controller: _controller,
              obscureText: true,
              enabled: !_checking,
              decoration: InputDecoration(
                labelText: l10n.translate('super_admin_code'),
                border: const OutlineInputBorder(),
                errorText:
                    _wrong ? l10n.translate('super_admin_code_wrong') : null,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste),
                  tooltip: l10n.translate('paste'),
                  onPressed: _checking ? null : _paste,
                ),
              ),
              onChanged: (_) {
                if (_wrong) setState(() => _wrong = false);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.translate('cancel')),
        ),
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.translate('unlock')),
        ),
      ],
    );
  }
}
