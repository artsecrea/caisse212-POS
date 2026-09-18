import 'package:flutter/foundation.dart';

/// Debug-only tracing.
///
/// `print` is NOT stripped from Flutter release builds — it runs, builds its
/// string and writes to the platform console. That matters on this app's hot
/// paths: the LAN server logs every KDS/waiter request, and the sync logs every
/// poll, so in release those were continuous string-building and console writes
/// on a till that stays open all day.
///
/// Genuine failures do NOT belong here — they go to `Logger.instance.error` /
/// `.warning`, which persists them via loggecrea's rotating file handler so a
/// technician can read them off a shop floor afterwards. Routing the *chatter*
/// into that logger instead would churn the 10 MB rotation and bury the real
/// diagnostics, which is why this exists alongside it rather than instead of it.
///
/// `kDebugMode` is a const, so the whole call is tree-shaken out of release.
void posLog(Object? message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(message);
  }
}

/// Lazy variant — the message is only built when it will actually be printed.
/// Use for anything expensive to format (a whole response body, a big list).
void posLogLazy(Object? Function() build) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(build());
  }
}
