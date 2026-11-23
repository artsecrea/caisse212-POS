# Project Structure

```
loggecrea/
├── lib/
│   ├── loggecrea.dart                    # Main export file
│   └── src/
│       ├── logger.dart                    # Singleton logger class
│       ├── log_level.dart                 # Log level enum
│       ├── log_entry.dart                 # Log entry model
│       ├── log_handler.dart               # Abstract handler base
│       ├── log_action.dart                # Abstract action base & examples
│       ├── handlers/
│       │   ├── console_log_handler.dart   # Console output handler
│       │   └── file_log_handler.dart      # File output handler
│       └── providers/
│           └── logger_provider.dart       # Riverpod integration helper
│
├── test/
│   └── loggecrea_test.dart               # Unit tests
│
├── example/
│   ├── lib/
│   │   ├── main.dart                      # Basic Flutter example
│   │   └── main_riverpod.dart             # Riverpod example
│   └── test_logger.dart                   # Standalone test script
│
├── README.md                              # Full documentation
├── QUICK_START.md                         # Quick start guide
├── CHANGELOG.md                           # Version history
├── LICENSE                                # MIT License
└── pubspec.yaml                           # Package configuration
```

## Core Components

### Logger (`logger.dart`)
- Singleton instance
- Manages handlers and actions
- Processes log entries
- Environment-aware (production/debug)
- Min level filtering
- Enable/disable functionality

### LogLevel (`log_level.dart`)
- Verbose, Debug, Info, Warning, Error, Fatal
- Comparison operators
- Numeric values for filtering

### LogEntry (`log_entry.dart`)
- Level, message, timestamp
- Optional: error, stackTrace, tag, metadata
- Immutable data class

### LogHandler (`log_handler.dart`)
- Abstract base class
- Implement `handle()` method
- Min level filtering
- Cleanup with `close()`

### LogAction (`log_action.dart`)
- Abstract base class
- Before/After timing
- Production/Debug filtering
- Example implementations included

## Built-in Handlers

### ConsoleLogHandler
- Colored ANSI output
- Emoji icons
- Configurable format
- Timestamp & tag support

### FileLogHandler
- Writes to file
- Automatic rotation
- Size management
- Keeps old files

## Integration

### Riverpod
Use `logger_provider.dart` for easy Riverpod integration:
```dart
import 'package:loggecrea/src/providers/logger_provider.dart';

final loggerProvider = Provider<Logger>((ref) {
  return configureLogger();
});
```

### Direct Usage
```dart
import 'package:loggecrea/loggecrea.dart';

final logger = Logger.instance;
```

## Extending

### Custom Handler
```dart
class MyHandler extends LogHandler {
  @override
  Future<bool> handle(LogEntry entry) async {
    // Your logic
    return true;
  }
}
```

### Custom Action
```dart
class MyAction extends LogAction {
  @override
  Future<bool> execute(LogEntry entry) async {
    // Your logic
    return true;
  }
}
```

## Features Checklist

- ✅ Singleton pattern
- ✅ Multiple log levels
- ✅ Pluggable handlers
- ✅ Before/After actions
- ✅ Environment-aware
- ✅ Colored console output
- ✅ File logging with rotation
- ✅ Tagged logs
- ✅ Metadata support
- ✅ No external dependencies
- ✅ Riverpod integration
- ✅ Fully tested
- ✅ Well documented
- ✅ Production-ready

## Design Principles

1. **Simple** - Easy to use out of the box
2. **Flexible** - Highly customizable
3. **Safe** - Async operations, error handling
4. **Efficient** - Minimal overhead
5. **Production-Ready** - Environment-aware configuration
6. **Framework-Agnostic** - Works with any Flutter app
7. **Test-Friendly** - Comprehensive test coverage

