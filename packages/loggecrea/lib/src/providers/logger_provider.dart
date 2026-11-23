import '../logger.dart';
import '../log_level.dart';
import '../handlers/console_log_handler.dart';

/// Provider function for Riverpod integration.
///
/// Usage with Riverpod:
/// ```dart
/// final loggerProvider = Provider<Logger>((ref) {
///   return configureLogger();
/// });
/// ```
///
/// Or manually:
/// ```dart
/// import 'package:flutter/foundation.dart';
///
/// final logger = configureLogger(
///   isProduction: kReleaseMode,
/// );
/// ```
Logger configureLogger({
  bool? isProduction,
  LogLevel? minLevel,
  bool addConsoleHandler = true,
  bool clearExistingHandlers = false,
}) {
  final logger = Logger.instance;

  // Clear existing handlers if requested
  if (clearExistingHandlers) {
    logger.clearHandlers();
  }

  // Set production mode (defaults to checking assert statements)
  // In production builds, asserts are disabled, so assertsEnabled will be false
  bool assertsEnabled = false;
  assert(() {
    assertsEnabled = true;
    return true;
  }());

  logger.setProduction(isProduction ?? !assertsEnabled);

  // Set minimum log level
  if (minLevel != null) {
    logger.setMinLevel(minLevel);
  } else {
    // In production, default to info level; in debug, verbose
    logger.setMinLevel(
      logger.isProduction ? LogLevel.info : LogLevel.verbose,
    );
  }

  // Add default console handler if requested
  if (addConsoleHandler) {
    logger.registerHandler(const ConsoleLogHandler());
  }

  return logger;
}

