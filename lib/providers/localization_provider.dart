// In a separate file, e.g., lib/providers/localization_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/app_localizations.dart';

final localizationProvider = StateProvider<AppLocalizations?>((ref) => null);
