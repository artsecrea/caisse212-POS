import 'log_action.dart';
import 'log_entry.dart';
import 'log_handler.dart';
import 'log_level.dart';

/// A singleton logger class for the application.
class Logger {
  // Private constructor for singleton
  Logger._internal();

  /// The singleton instance of the logger.
  static final Logger instance = Logger._internal();

  /// Factory constructor that returns the singleton instance.
  factory Logger() => instance;

  /// List of log handlers.
  final List<LogHandler> _handlers = [];

  /// List of log actions that execute before logging.
  final List<LogAction> _beforeActions = [];

  /// List of log actions that execute after logging.
  final List<LogAction> _afterActions = [];

  /// Minimum log level to process.
  LogLevel _minLevel = LogLevel.verbose;

  /// Whether the app is running in production mode.
  bool _isProduction = false;

  /// Whether the logger is enabled.
  bool _enabled = true;

  /// Get the current minimum log level.
  LogLevel get minLevel => _minLevel;

  /// Get whether the app is in production mode.
  bool get isProduction => _isProduction;

  /// Get whether the logger is enabled.
  bool get isEnabled => _enabled;

  /// Set the minimum log level.
  void setMinLevel(LogLevel level) {
    _minLevel = level;
  }

  /// Set whether the app is in production mode.
  void setProduction(bool isProduction) {
    _isProduction = isProduction;
  }

  /// Enable or disable the logger.
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Register a log handler.
  void registerHandler(LogHandler handler) {
    _handlers.add(handler);
  }

  /// Remove a log handler.
  void removeHandler(LogHandler handler) {
    _handlers.remove(handler);
  }

  /// Clear all handlers.
  void clearHandlers() {
    _handlers.clear();
  }

  /// Register a log action.
  void registerAction(LogAction action) {
    if (action.timing == LogActionTiming.before) {
      _beforeActions.add(action);
    } else {
      _afterActions.add(action);
    }
  }

  /// Remove a log action.
  void removeAction(LogAction action) {
    _beforeActions.remove(action);
    _afterActions.remove(action);
  }

  /// Clear all actions.
  void clearActions() {
    _beforeActions.clear();
    _afterActions.clear();
  }

  /// Log a message with the specified level.
  Future<void> log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_enabled || level < _minLevel) {
      return;
    }

    final entry = LogEntry(
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      tag: tag,
      metadata: metadata,
    );

    await _processLog(entry);
  }

  Future<void> _processLog(LogEntry entry) async {
    // Execute before actions
    await _executeActions(_beforeActions, entry);

    // Execute handlers
    final futures = <Future>[];
    for (final handler in _handlers) {
      futures.add(handler.handle(entry));
    }
    await Future.wait(futures, eagerError: false);

    // Execute after actions
    await _executeActions(_afterActions, entry);
  }

  Future<void> _executeActions(List<LogAction> actions, LogEntry entry) async {
    final futures = <Future>[];
    for (final action in actions) {
      if (action.shouldExecute(_isProduction)) {
        futures.add(action.execute(entry).catchError((e) {
          // Silently catch action errors to prevent logging from failing
          return false;
        }));
      }
    }
    await Future.wait(futures, eagerError: false);
  }

  /// Log a verbose message.
  Future<void> verbose(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
    Map<String, dynamic>? metadata,
  }) async {
    await log(
      LogLevel.verbose,
      message,
      error: error,
      stackTrace: stackTrace,
      tag: tag,
      metadata: metadata,
    );
  }

  /// Log a debug message.
  Future<void> debug(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
    Map<String, dynamic>? metadata,
  }) async {
    await log(
      LogLevel.debug,
      message,
      error: error,
      stackTrace: stackTrace,
      tag: tag,
      metadata: metadata,
    );
  }

  /// Log an info message.
  Future<void> info(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
    Map<String, dynamic>? metadata,
  }) async {
    await log(
      LogLevel.info,
      message,
      error: error,
      stackTrace: stackTrace,
      tag: tag,
      metadata: metadata,
    );
  }

  /// Log a warning message.
  Future<void> warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
    Map<String, dynamic>? metadata,
  }) async {
    await log(
      LogLevel.warning,
      message,
      error: error,
      stackTrace: stackTrace,
      tag: tag,
      metadata: metadata,
    );
  }

  /// Log an error message.
  Future<void> error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
    Map<String, dynamic>? metadata,
  }) async {
    await log(
      LogLevel.error,
      message,
      error: error,
      stackTrace: stackTrace,
      tag: tag,
      metadata: metadata,
    );
  }

  /// Log a fatal error message.
  Future<void> fatal(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
    Map<String, dynamic>? metadata,
  }) async {
    await log(
      LogLevel.fatal,
      message,
      error: error,
      stackTrace: stackTrace,
      tag: tag,
      metadata: metadata,
    );
  }

  /// Close all handlers and clean up resources.
  Future<void> close() async {
    final futures = _handlers.map((handler) => handler.close());
    await Future.wait(futures, eagerError: false);
  }
}

