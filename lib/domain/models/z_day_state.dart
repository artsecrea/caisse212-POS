/// Terminal-local record of which *business day* this POS is on, which Z number
/// it is at, and whether the day has been closed.
///
/// Lives in SharedPreferences rather than the DB because the login gate has to
/// answer "is the day closed?" *before* any user, session or Z row exists — and
/// on a day where no Z was ever opened there would be no row to read. Z
/// numbering is per-terminal, which is also how fiscal Z counters work.
///
/// The number is mirrored into `Zs.details` at open so the backend sees it too.
class ZDayState {
  /// Business day this state describes, as `yyyy-MM-dd`. Empty on first run.
  final String businessDay;

  /// Z counter for [businessDay]. Increments on day rollover, not on Z close,
  /// so an admin reopening the same day keeps the same number.
  final int zNumber;

  /// True once the day has been closed; blocks login until the next business
  /// day (or until a manager reopens).
  final bool closed;

  final DateTime? closedAt;
  final int? closedBy;
  final String? closedByName;

  /// Code of the Z that was closed together with the day (for the audit trail).
  final String? lastZCode;

  final DateTime? reopenedAt;
  final int? reopenedBy;

  const ZDayState({
    required this.businessDay,
    required this.zNumber,
    required this.closed,
    this.closedAt,
    this.closedBy,
    this.closedByName,
    this.lastZCode,
    this.reopenedAt,
    this.reopenedBy,
  });

  static const empty =
      ZDayState(businessDay: '', zNumber: 0, closed: false);

  /// Whether login should be blocked right now. Only locks the *same* business
  /// day — once [today] rolls over the lock lifts on its own.
  bool isLockedFor(String today) => closed && businessDay == today;

  ZDayState copyWith({
    String? businessDay,
    int? zNumber,
    bool? closed,
    DateTime? closedAt,
    int? closedBy,
    String? closedByName,
    String? lastZCode,
    DateTime? reopenedAt,
    int? reopenedBy,
  }) {
    return ZDayState(
      businessDay: businessDay ?? this.businessDay,
      zNumber: zNumber ?? this.zNumber,
      closed: closed ?? this.closed,
      closedAt: closedAt ?? this.closedAt,
      closedBy: closedBy ?? this.closedBy,
      closedByName: closedByName ?? this.closedByName,
      lastZCode: lastZCode ?? this.lastZCode,
      reopenedAt: reopenedAt ?? this.reopenedAt,
      reopenedBy: reopenedBy ?? this.reopenedBy,
    );
  }

  Map<String, dynamic> toJson() => {
        'businessDay': businessDay,
        'zNumber': zNumber,
        'closed': closed,
        'closedAt': closedAt?.toIso8601String(),
        'closedBy': closedBy,
        'closedByName': closedByName,
        'lastZCode': lastZCode,
        'reopenedAt': reopenedAt?.toIso8601String(),
        'reopenedBy': reopenedBy,
      };

  factory ZDayState.fromJson(Map<String, dynamic> json) => ZDayState(
        businessDay: json['businessDay']?.toString() ?? '',
        zNumber: (json['zNumber'] as num?)?.toInt() ?? 0,
        closed: json['closed'] as bool? ?? false,
        closedAt: DateTime.tryParse('${json['closedAt'] ?? ''}'),
        closedBy: (json['closedBy'] as num?)?.toInt(),
        closedByName: json['closedByName']?.toString(),
        lastZCode: json['lastZCode']?.toString(),
        reopenedAt: DateTime.tryParse('${json['reopenedAt'] ?? ''}'),
        reopenedBy: (json['reopenedBy'] as num?)?.toInt(),
      );
}
