// Category display mode enum
enum CategoryDisplayMode {
  topBar,    // Categories in top bar, products below (default)
  fullPage,  // Categories shown as full page grid, then products after selection
}

// App Settings Model
class AppSettings {
  final bool isDarkMode;
  final String defaultOrderType; // 'DINE_IN' or 'TAKE_AWAY'
  final bool showProductImages;
  final String defaultOrderStatus; // 'PENDING', 'ONHOLD', etc.
  final CategoryDisplayMode categoryDisplayMode; // How to display categories

  const AppSettings({
    this.isDarkMode = false,
    this.defaultOrderType = 'DINE_IN',
    this.showProductImages = true,
    this.defaultOrderStatus = 'PENDING',
    this.categoryDisplayMode = CategoryDisplayMode.topBar,
  });

  AppSettings copyWith({
    bool? isDarkMode,
    String? defaultOrderType,
    bool? showProductImages,
    String? defaultOrderStatus,
    CategoryDisplayMode? categoryDisplayMode,
  }) {
    return AppSettings(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      defaultOrderType: defaultOrderType ?? this.defaultOrderType,
      showProductImages: showProductImages ?? this.showProductImages,
      defaultOrderStatus: defaultOrderStatus ?? this.defaultOrderStatus,
      categoryDisplayMode: categoryDisplayMode ?? this.categoryDisplayMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isDarkMode': isDarkMode,
      'defaultOrderType': defaultOrderType,
      'showProductImages': showProductImages,
      'defaultOrderStatus': defaultOrderStatus,
      'categoryDisplayMode': categoryDisplayMode.name,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      isDarkMode: json['isDarkMode'] as bool? ?? false,
      defaultOrderType: json['defaultOrderType'] as String? ?? 'DINE_IN',
      showProductImages: json['showProductImages'] as bool? ?? true,
      defaultOrderStatus: json['defaultOrderStatus'] as String? ?? 'PENDING',
      categoryDisplayMode: CategoryDisplayMode.values.firstWhere(
        (e) => e.name == json['categoryDisplayMode'],
        orElse: () => CategoryDisplayMode.topBar,
      ),
    );
  }

  @override
  String toString() {
    return 'AppSettings(isDarkMode: $isDarkMode, defaultOrderType: $defaultOrderType, showProductImages: $showProductImages, defaultOrderStatus: $defaultOrderStatus, categoryDisplayMode: $categoryDisplayMode)';
  }
}

