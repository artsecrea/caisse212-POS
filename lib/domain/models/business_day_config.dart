/// The tenant's business-day definition, from `GET /api/pos/identity`.
///
/// `zDay = date(local time − businessDayStartHour)` is the ONLY rule for which
/// day a Z, session, order or ticket belongs to — never the device calendar.
/// The server links money to a Z by (terminal, zDay), so a till that disagreed
/// would file payments on the wrong day.
///
/// [timezone] is kept for display and diagnostics. The day itself is computed
/// on the device clock: a till sits in its tenant's timezone, and when online
/// the server's `currentZDay` (from `/pos/z/current`) is preferred anyway.
class BusinessDayConfig {
  final String? timezone;
  final int startHour;

  const BusinessDayConfig({this.timezone, this.startHour = 0});

  static const BusinessDayConfig empty = BusinessDayConfig();

  factory BusinessDayConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['businessDayStartHour'];
    final hour = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    return BusinessDayConfig(
      timezone: json['timezone']?.toString(),
      startHour: (hour ?? 0).clamp(0, 23),
    );
  }

  Map<String, dynamic> toJson() => {
        'timezone': timezone,
        'businessDayStartHour': startHour,
      };
}
