// Model for coupon applied to order
class Coupon {
  final String id;
  final String code;
  final double percentage;
  final DateTime createdAt;

  Coupon({
    required this.id,
    required this.code,
    required this.percentage,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'percentage': percentage,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Coupon.fromJson(Map<String, dynamic> json) {
    return Coupon(
      id: json['id'] as String,
      code: json['code'] as String,
      percentage: (json['percentage'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Coupon copyWith({
    String? id,
    String? code,
    double? percentage,
    DateTime? createdAt,
  }) {
    return Coupon(
      id: id ?? this.id,
      code: code ?? this.code,
      percentage: percentage ?? this.percentage,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
