import 'package:flutter/material.dart';

/// A modal "working…" overlay for long, non-interactive steps — closing a
/// session or a Z reads the day, prints and syncs, and a till that shows
/// nothing meanwhile gets the button pressed again.
///
/// It takes no input and cannot be dismissed. Close it before showing any
/// prompt: [close] removes this overlay's own route, so it is safe even when
/// another dialog has been pushed above it.
class BlockingProgress {
  BlockingProgress._(this._navigator, this._route, this._message);

  final NavigatorState _navigator;
  final Route<void> _route;
  final ValueNotifier<String> _message;
  bool _open = true;

  static BlockingProgress show(BuildContext context, String message) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final text = ValueNotifier(message);
    final route = RawDialogRoute<void>(
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, _, __) => PopScope(
        canPop: false,
        child: Center(
          child: Material(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            elevation: 6,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 260, maxWidth: 380),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(width: 20),
                    Flexible(
                      child: ValueListenableBuilder<String>(
                        valueListenable: text,
                        builder: (ctx, value, _) => Text(
                          value,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    navigator.push(route);
    return BlockingProgress._(navigator, route, text);
  }

  /// Runs [work] behind the overlay, closing it whatever the outcome.
  static Future<T> run<T>(
    BuildContext context,
    String message,
    Future<T> Function(BlockingProgress progress) work,
  ) async {
    final progress = show(context, message);
    try {
      return await work(progress);
    } finally {
      progress.close();
    }
  }

  bool get isOpen => _open;

  set message(String value) {
    if (_open) _message.value = value;
  }

  void close() {
    if (!_open) return;
    _open = false;
    if (_route.isActive) _navigator.removeRoute(_route);
    // Disposed after the route is gone; the builder may still read it once
    // during the removal frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _message.dispose());
  }
}
