import 'package:timeago/timeago.dart' as timeago;

/// How long a line has been with the kitchen, as a badge short enough to sit
/// on an order-panel row.
///
/// timeago's SHORT forms are what this uses — "5m", "2h" — not the default
/// "about 2 hours ago", which would not fit beside a product name and reads
/// like prose where the cashier wants a glanceable number.

/// Past this, the exact figure stops being information.
///
/// A table that has been waiting nine hours is a table somebody forgot to
/// close, not a table running late, and "+9h" says that better than a precise
/// count of hours nobody is going to act on. It also keeps the badge to a
/// fixed width, so a row never reflows because a number grew a digit.
const Duration kElapsedCap = Duration(hours: 9);

bool _registered = false;

/// Register the short-form messages for the languages this app ships.
///
/// timeago only pre-registers `en`, so every other locale — and every `_short`
/// variant including English's — has to be added or `format` silently falls
/// back to English long form. Idempotent: called from the widget layer, which
/// may build many times.
void registerElapsedLocales() {
  if (_registered) return;
  _registered = true;
  timeago.setLocaleMessages('en_short', timeago.EnShortMessages());
  timeago.setLocaleMessages('fr', timeago.FrMessages());
  timeago.setLocaleMessages('fr_short', timeago.FrShortMessages());
  timeago.setLocaleMessages('ar', timeago.ArMessages());
  timeago.setLocaleMessages('ar_short', timeago.ArShortMessages());
  timeago.setLocaleMessages('es', timeago.EsMessages());
  timeago.setLocaleMessages('es_short', timeago.EsShortMessages());
}

/// Elapsed time since [since], or '' when there is nothing to show.
///
/// [locale] is the app's language code; anything unknown falls back to
/// English rather than throwing, because a badge is not worth an exception.
///
/// A [since] in the future reads as "now": clocks drift between the till and
/// the LAN devices that write these timestamps, and a line that claims to have
/// been sent in three minutes' time should look fresh, not negative.
String elapsedLabel(
  DateTime? since, {
  DateTime? now,
  String locale = 'en',
  Duration cap = kElapsedCap,
}) {
  if (since == null) return '';
  registerElapsedLocales();

  final clock = now ?? DateTime.now();
  final elapsed = clock.difference(since);
  if (elapsed.isNegative) return elapsedNowLabel(locale: locale);
  if (elapsed >= cap) return '+${cap.inHours}h';

  return timeago.format(
    since,
    locale: _shortLocale(locale),
    clock: clock,
  );
}

/// What a just-sent line reads as, in the same vocabulary as [elapsedLabel].
String elapsedNowLabel({String locale = 'en'}) {
  registerElapsedLocales();
  final clock = DateTime.now();
  return timeago.format(clock, locale: _shortLocale(locale), clock: clock);
}

String _shortLocale(String locale) {
  const supported = {'en', 'fr', 'ar', 'es'};
  final base = locale.split(RegExp('[_-]')).first.toLowerCase();
  return supported.contains(base) ? '${base}_short' : 'en_short';
}
