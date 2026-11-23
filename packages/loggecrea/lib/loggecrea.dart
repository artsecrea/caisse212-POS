/// Loggecrea - A powerful logging package for Flutter applications.
///
/// This library provides a flexible logging system with support for:
/// - Singleton logger instance
/// - Multiple log levels (Verbose, Debug, Info, Warning, Error, Fatal)
/// - Pluggable handlers (Console, File, or custom)
/// - Before/After actions for custom logic
/// - Environment-aware configuration (production/debug)
/// - Riverpod integration support
library;

export 'src/logger.dart';
export 'src/log_level.dart';
export 'src/log_entry.dart';
export 'src/log_handler.dart';
export 'src/log_action.dart';
export 'src/handlers/console_log_handler.dart';
export 'src/handlers/file_log_handler.dart';
// Note: logger_provider.dart is not exported here to avoid Flutter dependency
// Import it separately if needed: import 'package:loggecrea/src/providers/logger_provider.dart';

