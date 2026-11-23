import '../log_entry.dart';
import '../log_handler.dart';
import '../log_level.dart';

/// A log handler that prints logs to the console.
class ConsoleLogHandler extends LogHandler {
  /// Creates a console log handler.
  const ConsoleLogHandler({
    super.minLevel,
    this.useColors = true,
    this.includeTimestamp = true,
    this.includeTag = true,
  });

  /// Whether to use ANSI color codes for colored output.
  final bool useColors;

  /// Whether to include timestamps in the output.
  final bool includeTimestamp;

  /// Whether to include tags in the output.
  final bool includeTag;

  @override
  Future<bool> handle(LogEntry entry) async {
    if (!shouldHandle(entry)) {
      return false;
    }

    final buffer = StringBuffer();


    // Add log level
    if (useColors) {
      buffer.write(_colorize('[${entry.level.name}]', entry.level));
    } else {
      buffer.write('[${entry.level.name}]');
    }

    // Add tag
    if (includeTag && entry.tag != null) {
      buffer.write(' [${entry.tag}]');
    }

    // Add timestamp
    if (includeTimestamp) {
      buffer.write(' ${_formatTimestamp(entry.timestamp)}');
    }

    // Add message
    buffer.write(': ${entry.message}');

    // Print main message
    print(buffer.toString());

    // Print error if present
    if (entry.error != null) {
      print('Error: ${entry.error}');
    }

    // Print stack trace if present
    if (entry.stackTrace != null) {
      final stackLines = entry.stackTrace.toString().split('\n');
      for (var line in stackLines.take(5)) {
        // Limit stack trace lines
        if (line.isNotEmpty) {
          print('  $line');
        }
      }
    }

    // Print metadata if present
    if (entry.metadata.isNotEmpty) {
      print('   Metadata: ${entry.metadata}');
    }

    return true;
  }


  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  String _colorize(String text, LogLevel level) {
    const reset = '\x1B[0m';
    String color;

    switch (level) {
      case LogLevel.verbose:
        color = '\x1B[37m'; // White
      case LogLevel.debug:
        color = '\x1B[36m'; // Cyan
      case LogLevel.info:
        color = '\x1B[32m'; // Green
      case LogLevel.warning:
        color = '\x1B[33m'; // Yellow
      case LogLevel.error:
        color = '\x1B[31m'; // Red
      case LogLevel.fatal:
        color = '\x1B[35m'; // Magenta
    }

    return '$color$text$reset';
  }
}

