class SessionRules {
  final int? minStartHour;
  final int? cantOpenAfterHour;
  final int? maxSessionDurationMinutes;
  final int? maxEndHour;
  final int? maxSessionsPerUserPerDay;

  const SessionRules({
    this.minStartHour,
    this.cantOpenAfterHour,
    this.maxSessionDurationMinutes,
    this.maxEndHour,
    this.maxSessionsPerUserPerDay,
  });

  static const SessionRules empty = SessionRules();

  bool get hasAnyRule =>
      minStartHour != null ||
      cantOpenAfterHour != null ||
      maxSessionDurationMinutes != null ||
      maxEndHour != null ||
      maxSessionsPerUserPerDay != null;

  factory SessionRules.fromJson(Map<String, dynamic> json) {
    return SessionRules(
      minStartHour: json['minStartHour'] as int?,
      cantOpenAfterHour: json['cantOpenAfterHour'] as int?,
      maxSessionDurationMinutes: json['maxSessionDurationMinutes'] as int?,
      maxEndHour: json['maxEndHour'] as int?,
      maxSessionsPerUserPerDay: json['maxSessionsPerUserPerDay'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'minStartHour': minStartHour,
        'cantOpenAfterHour': cantOpenAfterHour,
        'maxSessionDurationMinutes': maxSessionDurationMinutes,
        'maxEndHour': maxEndHour,
        'maxSessionsPerUserPerDay': maxSessionsPerUserPerDay,
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
