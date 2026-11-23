/// Defines the severity levels for logging.
enum LogLevel {
  /// Verbose: Detailed information for debugging.
  verbose(0, 'VERBOSE'),

  /// Debug: Debug information.
  debug(1, 'DEBUG'),

  /// Info: General informational messages.
  info(2, 'INFO'),

  /// Warning: Warning messages.
  warning(3, 'WARNING'),

  /// Error: Error messages.
  error(4, 'ERROR'),

  /// Fatal: Critical errors that may cause app termination.
  fatal(5, 'FATAL');

  const LogLevel(this.value, this.name);

  /// Numeric value representing the severity.
  final int value;

  /// String name of the log level.
  final String name;

  /// Check if this level is equal or higher than another level.
  bool operator >=(LogLevel other) => value >= other.value;

  /// Check if this level is higher than another level.
  bool operator >(LogLevel other) => value > other.value;

  /// Check if this level is lower than another level.
  bool operator <(LogLevel other) => value < other.value;

  /// Check if this level is equal or lower than another level.
  bool operator <=(LogLevel other) => value <= other.value;
}

