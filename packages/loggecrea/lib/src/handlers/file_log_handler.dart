import 'dart:async';
import 'dart:io';

import '../log_entry.dart';
import '../log_handler.dart';

/// A log handler that writes logs to a file.
class FileLogHandler extends LogHandler {
  /// Creates a file log handler.
  FileLogHandler({
    required String filePath,
    super.minLevel,
    this.maxFileSizeBytes = 10 * 1024 * 1024, // 10 MB default
    this.keepOldFiles = 5,
  }) : _filePath = filePath;

  final String _filePath;

  /// Maximum file size before rotation (in bytes).
  final int maxFileSizeBytes;

  /// Number of old log files to keep after rotation.
  final int keepOldFiles;

  IOSink? _sink;
  File? _file;

  /// Serializes writes to [_sink]. The [Logger] dispatches handlers
  /// concurrently, so without this two `handle()` calls could write/flush the
  /// same IOSink at once — the second one starting while the first `flush()`
  /// still has the sink bound throws "Bad state: StreamSink is bound to a
  /// stream" and the line is lost. Each write is chained after the previous.
  Future<void> _writeChain = Future.value();

  Future<void> _ensureFileOpen() async {
    if (_sink != null) return;

    _file = File(_filePath);

    // Create parent directories if they don't exist
    final directory = _file!.parent;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    // Check if rotation is needed
    if (await _file!.exists()) {
      final fileSize = await _file!.length();
      if (fileSize >= maxFileSizeBytes) {
        await _rotateLogFile();
      }
    }

    _sink = _file!.openWrite(mode: FileMode.append);
  }

  Future<void> _rotateLogFile() async {
    if (_file == null) return;

    // Close current sink
    await _sink?.close();
    _sink = null;

    // Rotate existing files
    for (var i = keepOldFiles - 1; i >= 1; i--) {
      final oldFile = File('$_filePath.$i');
      final newFile = File('$_filePath.${i + 1}');

      if (await oldFile.exists()) {
        if (await newFile.exists()) {
          await newFile.delete();
        }
        await oldFile.rename(newFile.path);
      }
    }

    // Rename current file to .1
    final backupFile = File('$_filePath.1');
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    await _file!.rename(backupFile.path);

    // Create new file
    _file = File(_filePath);
  }

  @override
  Future<bool> handle(LogEntry entry) {
    if (!shouldHandle(entry)) {
      return Future.value(false);
    }
    // Queue this write behind any in-flight one so the shared IOSink is never
    // written/flushed concurrently. `_doWrite` swallows its own errors, so the
    // chain can't be broken by a single failed write.
    final result = _writeChain.then((_) => _doWrite(entry));
    _writeChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<bool> _doWrite(LogEntry entry) async {
    try {
      await _ensureFileOpen();

      final buffer = StringBuffer();

      // Write timestamp
      buffer.write('[${entry.timestamp.toIso8601String()}]');

      // Write level
      buffer.write(' [${entry.level.name}]');

      // Write tag
      if (entry.tag != null) {
        buffer.write(' [${entry.tag}]');
      }

      // Write message
      buffer.write(': ${entry.message}');

      _sink!.writeln(buffer.toString());

      // Write error if present
      if (entry.error != null) {
        _sink!.writeln('  Error: ${entry.error}');
      }

      // Write stack trace if present
      if (entry.stackTrace != null) {
        _sink!.writeln('  Stack trace:');
        final stackLines = entry.stackTrace.toString().split('\n');
        for (var line in stackLines) {
          if (line.isNotEmpty) {
            _sink!.writeln('    $line');
          }
        }
      }

      // Write metadata if present
      if (entry.metadata.isNotEmpty) {
        _sink!.writeln('  Metadata: ${entry.metadata}');
      }

      // Flush to ensure it's written
      await _sink!.flush();

      return true;
    } catch (e) {
      // If file logging fails, print to console as fallback
      print('Failed to write log to file: $e');
      return false;
    }
  }

  @override
  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _file = null;
  }
}

