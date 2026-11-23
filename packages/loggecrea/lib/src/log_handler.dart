import 'log_entry.dart';
import 'log_level.dart';

/// Abstract class for handling log entries.
abstract class LogHandler {
  /// Creates a new log handler.
  const LogHandler({
    this.minLevel = LogLevel.verbose,
  });

  /// Minimum log level this handler will process.
  final LogLevel minLevel;

  /// Handle a log entry.
  /// Returns true if the log was handled successfully.
  Future<bool> handle(LogEntry entry);

  /// Check if this handler should process the given log entry.
  bool shouldHandle(LogEntry entry) => entry.level >= minLevel;

  /// Close or cleanup resources used by this handler.
  Future<void> close() async {}
}

