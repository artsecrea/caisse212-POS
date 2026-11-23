import 'log_level.dart';

/// Represents a single log entry.
class LogEntry {
  /// Creates a new log entry.
  LogEntry({
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    DateTime? timestamp,
    this.tag,
    Map<String, dynamic>? metadata,
  })  : timestamp = timestamp ?? DateTime.now(),
        metadata = metadata ?? {};

  /// The severity level of this log entry.
  final LogLevel level;

  /// The log message.
  final String message;

  /// Optional error object associated with this log.
  final Object? error;

  /// Optional stack trace associated with an error.
  final StackTrace? stackTrace;

  /// When this log entry was created.
  final DateTime timestamp;

  /// Optional tag to categorize logs.
  final String? tag;

  /// Additional metadata for this log entry.
  final Map<String, dynamic> metadata;

  /// Creates a copy of this log entry with optional field updates.
  LogEntry copyWith({
    LogLevel? level,
    String? message,
    Object? error,
    StackTrace? stackTrace,
    DateTime? timestamp,
    String? tag,
    Map<String, dynamic>? metadata,
  }) {
    return LogEntry(
      level: level ?? this.level,
      message: message ?? this.message,
      error: error ?? this.error,
      stackTrace: stackTrace ?? this.stackTrace,
      timestamp: timestamp ?? this.timestamp,
      tag: tag ?? this.tag,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('[${level.name}]');
    if (tag != null) {
      buffer.write(' [$tag]');
    }
    buffer.write(' ${timestamp.toIso8601String()}: $message');
    if (error != null) {
      buffer.write('\nError: $error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    if (metadata.isNotEmpty) {
      buffer.write('\nMetadata: $metadata');
    }
    return buffer.toString();
  }
}

