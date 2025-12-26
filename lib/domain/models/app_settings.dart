// App Settings Model
class AppSettings {
  final bool isDarkMode;
  final String defaultOrderType; // 'DINE_IN' or 'TAKE_AWAY'
  final bool showProductImages;

  const AppSettings({
    this.isDarkMode = false,
    this.defaultOrderType = 'DINE_IN',
    this.showProductImages = true,
  });

  AppSettings copyWith({
    bool? isDarkMode,
    String? defaultOrderType,
    bool? showProductImages,
  }) {
    return AppSettings(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      defaultOrderType: defaultOrderType ?? this.defaultOrderType,
      showProductImages: showProductImages ?? this.showProductImages,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isDarkMode': isDarkMode,
      'defaultOrderType': defaultOrderType,
      'showProductImages': showProductImages,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      isDarkMode: json['isDarkMode'] as bool? ?? false,
      defaultOrderType: json['defaultOrderType'] as String? ?? 'DINE_IN',
      showProductImages: json['showProductImages'] as bool? ?? true,
    );
  }

  @override
  String toString() {
    return 'AppSettings(isDarkMode: $isDarkMode, defaultOrderType: $defaultOrderType, showProductImages: $showProductImages)';
  }
}

