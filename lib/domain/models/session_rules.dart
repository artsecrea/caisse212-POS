class SessionRules {
  final int? minStartHour;
  final int? cantOpenAfterHour;
  final int? maxSessionDurationMinutes;
  final int? maxEndHour;
  final int? maxSessionsPerUserPerDay;

  /// Sessions that may be open (active or paused) on this terminal at once.
  /// The server resolves it from the terminal, falling back to the tenant.
  final int? maxOpenSessionsPerTerminal;

  /// A session may not open with a zero float.
  final bool requireOpeningFloat;

  // Z rules (terminal settings, set in the back office). Times are strict
  // "HH:mm", relative to the business day's start; null = no limit.
  /// `AUTO` (null) opens a Z with the first session; `MANUAL` needs a
  /// `pos:z:open` holder to open it before any session.
  final String? zOpenMode;

  /// No new Z at or after this time without `pos:z:override`.
  final String? zCantOpenAfter;

  /// `MANUAL` (null) | `AUTO_AFTER_HOUR`.
  final String? zCloseMode;

  /// With AUTO_AFTER_HOUR: from this time, a session close asks to close the Z.
  final String? zAutoCloseAfter;

  /// No Z close before this time without `pos:z:override`.
  final String? zEarliestCloseTime;

  const SessionRules({
    this.minStartHour,
    this.cantOpenAfterHour,
    this.maxSessionDurationMinutes,
    this.maxEndHour,
    this.maxSessionsPerUserPerDay,
    this.maxOpenSessionsPerTerminal,
    this.requireOpeningFloat = false,
    this.zOpenMode,
    this.zCantOpenAfter,
    this.zCloseMode,
    this.zAutoCloseAfter,
    this.zEarliestCloseTime,
  });

  static const SessionRules empty = SessionRules();

  bool get hasAnyRule =>
      minStartHour != null ||
      cantOpenAfterHour != null ||
      maxSessionDurationMinutes != null ||
      maxEndHour != null ||
      maxSessionsPerUserPerDay != null ||
      maxOpenSessionsPerTerminal != null ||
      requireOpeningFloat;

  factory SessionRules.fromJson(Map<String, dynamic> json) {
    return SessionRules(
      minStartHour: json['minStartHour'] as int?,
      cantOpenAfterHour: json['cantOpenAfterHour'] as int?,
      maxSessionDurationMinutes: json['maxSessionDurationMinutes'] as int?,
      maxEndHour: json['maxEndHour'] as int?,
      maxSessionsPerUserPerDay: json['maxSessionsPerUserPerDay'] as int?,
      maxOpenSessionsPerTerminal: json['maxOpenSessionsPerTerminal'] as int?,
      requireOpeningFloat: json['requireOpeningFloat'] as bool? ?? false,
      zOpenMode: json['zOpenMode'] as String?,
      zCantOpenAfter: json['zCantOpenAfter'] as String?,
      zCloseMode: json['zCloseMode'] as String?,
      zAutoCloseAfter: json['zAutoCloseAfter'] as String?,
      zEarliestCloseTime: json['zEarliestCloseTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'minStartHour': minStartHour,
        'cantOpenAfterHour': cantOpenAfterHour,
        'maxSessionDurationMinutes': maxSessionDurationMinutes,
        'maxEndHour': maxEndHour,
        'maxSessionsPerUserPerDay': maxSessionsPerUserPerDay,
        'maxOpenSessionsPerTerminal': maxOpenSessionsPerTerminal,
        'requireOpeningFloat': requireOpeningFloat,
        'zOpenMode': zOpenMode,
        'zCantOpenAfter': zCantOpenAfter,
        'zCloseMode': zCloseMode,
        'zAutoCloseAfter': zAutoCloseAfter,
        'zEarliestCloseTime': zEarliestCloseTime,
      };

  SessionRules copyWith({
    int? minStartHour,
    int? cantOpenAfterHour,
    int? maxSessionDurationMinutes,
    int? maxEndHour,
    int? maxSessionsPerUserPerDay,
  }) {
    return SessionRules(
      minStartHour: minStartHour ?? this.minStartHour,
      cantOpenAfterHour: cantOpenAfterHour ?? this.cantOpenAfterHour,
      maxSessionDurationMinutes:
          maxSessionDurationMinutes ?? this.maxSessionDurationMinutes,
      maxEndHour: maxEndHour ?? this.maxEndHour,
      maxSessionsPerUserPerDay:
          maxSessionsPerUserPerDay ?? this.maxSessionsPerUserPerDay,
      maxOpenSessionsPerTerminal: maxOpenSessionsPerTerminal,
      requireOpeningFloat: requireOpeningFloat,
      zOpenMode: zOpenMode,
      zCantOpenAfter: zCantOpenAfter,
      zCloseMode: zCloseMode,
      zAutoCloseAfter: zAutoCloseAfter,
      zEarliestCloseTime: zEarliestCloseTime,
    );
  }
}

/// Thrown by [SessionService.checkOpenRules] when a rule blocks session opening.
class SessionRuleViolation implements Exception {
  final String message;
  SessionRuleViolation(this.message);

  @override
  String toString() => message;
}
