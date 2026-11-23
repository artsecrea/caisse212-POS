# Loggecrea

A powerful, flexible, and production-ready logging package for Flutter applications with built-in Riverpod integration support.

## Features

✨ **Singleton by default** - One logger instance throughout your app
🎯 **Log Levels** - Verbose, Debug, Info, Warning, Error, Fatal
🔌 **Pluggable Handlers** - Console, File, or create your own (Database, Remote, etc.)
⚡ **Before/After Actions** - Execute custom actions before or after logging
🎛️ **Environment-Aware** - Different behavior for debug and production
🎨 **Colored Console Output** - Beautiful, emoji-enhanced console logs
📝 **File Logging** - Automatic file rotation and size management
🏷️ **Tagged Logs** - Categorize logs with custom tags
📋 **Metadata Support** - Attach custom data to any log entry
🚫 **No External Dependencies** - Pure Dart/Flutter implementation
🌊 **Riverpod Ready** - Easy integration with Riverpod state management

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  loggecrea: ^0.0.1
```

## Quick Start

### Basic Usage

```dart
import 'package:loggecrea/loggecrea.dart';

void main() {
  // Configure logger
  final logger = Logger.instance;
  logger.registerHandler(const ConsoleLogHandler());
  
  // Start logging
  logger.info('App started');
  logger.debug('Debug information');
  logger.warning('Something might be wrong');
  logger.error('An error occurred', error: Exception('Oops!'));
}
```

### With Riverpod

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

// Define the logger provider
final loggerProvider = Provider<Logger>((ref) {
  return configureLogger(
    addConsoleHandler: true,
  );
});

// Use in your app
class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logger = ref.watch(loggerProvider);
    logger.info('App built');
    
    return MaterialApp(
      // ...
    );
  }
}
```

## Advanced Configuration

### Custom Handlers

```dart
import 'package:loggecrea/loggecrea.dart';
import 'dart:io';

void setupLogger() {
  final logger = Logger.instance;
  
  // Console handler for development
  logger.registerHandler(
    const ConsoleLogHandler(
      minLevel: LogLevel.debug,
      useColors: true,
      includeTimestamp: true,
    ),
  );
  
  // File handler for persistent logs
  logger.registerHandler(
    FileLogHandler(
      filePath: '/path/to/logs/app.log',
      minLevel: LogLevel.info,
      maxFileSizeBytes: 5 * 1024 * 1024, // 5 MB
      keepOldFiles: 3,
    ),
  );
}
```

### Custom Log Handler (Database Example)

```dart
class DatabaseLogHandler extends LogHandler {
  DatabaseLogHandler({required this.database, super.minLevel});
  
  final Database database;
  
  @override
  Future<bool> handle(LogEntry entry) async {
    if (!shouldHandle(entry)) return false;
    
    await database.insert('logs', {
      'level': entry.level.name,
      'message': entry.message,
      'timestamp': entry.timestamp.toIso8601String(),
      'tag': entry.tag,
    });
    
    return true;
  }
}

// Register it
logger.registerHandler(DatabaseLogHandler(database: myDb));
```

## Log Actions

Execute custom logic before or after logging - perfect for sending alerts, tracking analytics, or triggering events.

### Before/After Actions

```dart
// Send email alerts for critical errors
logger.registerAction(
  EmailNotificationAction(
    recipient: 'admin@example.com',
    timing: LogActionTiming.after,
    enabledInProduction: true,
    enabledInDebug: false,
  ),
);

// Track analytics events
logger.registerAction(
  AnalyticsAction(
    timing: LogActionTiming.after,
    enabledInProduction: true,
    enabledInDebug: false,
  ),
);
```

### Custom Actions

```dart
class SlackNotificationAction extends LogAction {
  const SlackNotificationAction({
    required this.webhookUrl,
    super.timing = LogActionTiming.after,
    super.enabledInProduction = true,
    super.enabledInDebug = false,
  });
  
  final String webhookUrl;
  
  @override
  Future<bool> execute(LogEntry entry) async {
    if (entry.level >= LogLevel.error) {
      // Send to Slack
      await http.post(
        Uri.parse(webhookUrl),
        body: jsonEncode({
          'text': '🚨 ${entry.level.name}: ${entry.message}',
        }),
      );
    }
    return true;
  }
}

// Register it
logger.registerAction(
  SlackNotificationAction(webhookUrl: 'YOUR_WEBHOOK_URL'),
);
```

### Function-Based Actions

```dart
logger.registerAction(
  FunctionLogAction(
    timing: LogActionTiming.before,
    enabledInProduction: false,
    enabledInDebug: true,
    action: (entry) async {
      // Custom logic here
      print('About to log: ${entry.message}');
      return true;
    },
  ),
);
```

## Environment-Specific Configuration

```dart
void configureLoggerForEnvironment() {
  final logger = Logger.instance;
  
  // Set production mode
  logger.setProduction(kReleaseMode);
  
  if (logger.isProduction) {
    // Production: Only log warnings and above, save to file
    logger.setMinLevel(LogLevel.warning);
    logger.registerHandler(
      FileLogHandler(filePath: '/path/to/production.log'),
    );
    
    // Enable error notifications
    logger.registerAction(
      EmailNotificationAction(
        recipient: 'team@example.com',
        enabledInProduction: true,
        enabledInDebug: false,
      ),
    );
  } else {
    // Development: Log everything to console
    logger.setMinLevel(LogLevel.verbose);
    logger.registerHandler(
      const ConsoleLogHandler(useColors: true),
    );
  }
}
```

## Log Levels

- **Verbose**: Detailed debugging information
- **Debug**: Debug information
- **Info**: General informational messages
- **Warning**: Warning messages
- **Error**: Error messages
- **Fatal**: Critical errors

## Tagged Logs

Organize logs by feature or module:

```dart
logger.info('User logged in', tag: 'AUTH');
logger.debug('Fetching data', tag: 'API');
logger.error('Payment failed', tag: 'PAYMENT');
```

## Metadata

Attach structured data to logs:

```dart
logger.info(
  'User action',
  tag: 'ANALYTICS',
  metadata: {
    'userId': '12345',
    'action': 'button_click',
    'screen': 'home',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  },
);
```

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:loggecrea/loggecrea.dart';

void main() {
  // Initialize logger
  setupLogger();
  
  // Run app
  runApp(MyApp());
}

void setupLogger() {
  final logger = Logger.instance;
  
  // Set environment
  logger.setProduction(kReleaseMode);
  
  // Configure based on environment
  if (kDebugMode) {
    logger.setMinLevel(LogLevel.verbose);
    logger.registerHandler(const ConsoleLogHandler());
  } else {
    logger.setMinLevel(LogLevel.info);
    logger.registerHandler(
      FileLogHandler(
        filePath: '/data/app.log',
        maxFileSizeBytes: 10 * 1024 * 1024,
      ),
    );
  }
  
  // Register error notification for production
  logger.registerAction(
    FunctionLogAction(
      timing: LogActionTiming.after,
      enabledInProduction: true,
      enabledInDebug: false,
      action: (entry) async {
        if (entry.level >= LogLevel.error) {
          // Send notification to your error tracking service
          print('📧 Notifying team about: ${entry.message}');
        }
        return true;
      },
    ),
  );
  
  logger.info('Logger initialized');
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  final logger = Logger.instance;
  
  @override
  Widget build(BuildContext context) {
    logger.info('HomeScreen built', tag: 'UI');
    
    return Scaffold(
      appBar: AppBar(title: Text('Loggecrea Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                logger.debug('Button clicked', tag: 'USER_ACTION');
              },
              child: Text('Log Debug'),
            ),
            ElevatedButton(
              onPressed: () {
                logger.warning('Warning triggered', tag: 'USER_ACTION');
              },
              child: Text('Log Warning'),
            ),
            ElevatedButton(
              onPressed: () {
                try {
                  throw Exception('Test exception');
                } catch (e, stackTrace) {
                  logger.error(
                    'Error occurred',
                    error: e,
                    stackTrace: stackTrace,
                    tag: 'ERROR_TEST',
                  );
                }
              },
              child: Text('Log Error'),
            ),
          ],
        ),
      ),
    );
  }
}
```

## API Reference

### Logger

- `Logger.instance` / `Logger()` - Get singleton instance
- `setMinLevel(LogLevel)` - Set minimum log level
- `setProduction(bool)` - Set production mode
- `setEnabled(bool)` - Enable/disable logger
- `registerHandler(LogHandler)` - Add a log handler
- `registerAction(LogAction)` - Add a log action
- `verbose(message, ...)` - Log verbose message
- `debug(message, ...)` - Log debug message
- `info(message, ...)` - Log info message
- `warning(message, ...)` - Log warning message
- `error(message, ...)` - Log error message
- `fatal(message, ...)` - Log fatal message

### LogHandler

Create custom handlers by extending `LogHandler`:

```dart
class MyCustomHandler extends LogHandler {
  @override
  Future<bool> handle(LogEntry entry) async {
    // Your implementation
    return true;
  }
}
```

### LogAction

Create custom actions by extending `LogAction`:

```dart
class MyCustomAction extends LogAction {
  @override
  Future<bool> execute(LogEntry entry) async {
    // Your implementation
    return true;
  }
}
```

## Testing

The package includes comprehensive tests. Run them with:

```bash
flutter test
```

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

