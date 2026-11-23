# Loggecrea - Quick Start Guide

## Installation

```yaml
dependencies:
  loggecrea: ^0.0.1
```

## Basic Usage

```dart
import 'package:loggecrea/loggecrea.dart';

void main() {
  // Initialize logger
  final logger = Logger.instance;
  logger.registerHandler(const ConsoleLogHandler());
  
  // Log messages
  logger.info('App started');
  logger.debug('Debug info');
  logger.warning('Warning message');
  logger.error('Error occurred');
}
```

## With Riverpod

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/src/providers/logger_provider.dart';

final loggerProvider = Provider<Logger>((ref) {
  return configureLogger();
});

class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logger = ref.watch(loggerProvider);
    logger.info('Widget built');
    return Container();
  }
}
```

## Key Features

### 1. Singleton Pattern
```dart
final logger1 = Logger();
final logger2 = Logger.instance;
// logger1 and logger2 are the same instance
```

### 2. Custom Handlers
```dart
// Console handler
logger.registerHandler(const ConsoleLogHandler(
  useColors: true,
  minLevel: LogLevel.debug,
));

// File handler
logger.registerHandler(FileLogHandler(
  filePath: '/path/to/app.log',
  maxFileSizeBytes: 10 * 1024 * 1024,
));
```

### 3. Actions (Before/After Logging)
```dart
// Execute after critical errors
logger.registerAction(
  FunctionLogAction(
    timing: LogActionTiming.after,
    enabledInProduction: true,
    enabledInDebug: false,
    action: (entry) async {
      if (entry.level >= LogLevel.error) {
        // Send notification, email, etc.
      }
      return true;
    },
  ),
);
```

### 4. Environment-Specific Behavior
```dart
logger.setProduction(kReleaseMode);

if (logger.isProduction) {
  logger.setMinLevel(LogLevel.warning);
} else {
  logger.setMinLevel(LogLevel.verbose);
}
```

### 5. Tagged Logs
```dart
logger.info('User logged in', tag: 'AUTH');
logger.error('Payment failed', tag: 'PAYMENT');
```

### 6. Metadata
```dart
logger.info(
  'User action',
  metadata: {
    'userId': '12345',
    'action': 'button_click',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  },
);
```

## Log Levels

From lowest to highest severity:

1. **Verbose** - Detailed debug information
2. **Debug** - Debug messages
3. **Info** - General information
4. **Warning** - Warning messages
5. **Error** - Error messages
6. **Fatal** - Critical errors

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:loggecrea/loggecrea.dart';

void main() {
  setupLogger();
  runApp(MyApp());
}

void setupLogger() {
  final logger = Logger.instance;
  
  logger.setProduction(kReleaseMode);
  logger.setMinLevel(
    kReleaseMode ? LogLevel.info : LogLevel.verbose,
  );
  
  logger.registerHandler(const ConsoleLogHandler());
  
  if (kReleaseMode) {
    logger.registerHandler(
      FileLogHandler(filePath: '/data/app.log'),
    );
    
    logger.registerAction(
      FunctionLogAction(
        timing: LogActionTiming.after,
        enabledInProduction: true,
        action: (entry) async {
          if (entry.level >= LogLevel.error) {
            // Send error to tracking service
          }
          return true;
        },
      ),
    );
  }
  
  logger.info('Logger initialized');
}
```

## Custom Handler Example

```dart
class MyCustomHandler extends LogHandler {
  @override
  Future<bool> handle(LogEntry entry) async {
    if (!shouldHandle(entry)) return false;
    
    // Your custom logic here
    print('Custom: ${entry.message}');
    
    return true;
  }
}

// Register it
logger.registerHandler(MyCustomHandler(minLevel: LogLevel.info));
```

## Tips

1. **Set up once** - Configure logger in `main()` before running your app
2. **Use tags** - Organize logs by feature/module
3. **Environment-aware** - Different configs for debug vs production
4. **File rotation** - FileLogHandler automatically manages log file sizes
5. **Async-safe** - All logging operations are async
6. **Error handling** - Actions silently fail to prevent logging from crashing your app

## Need Help?

Check the [full README](README.md) for more detailed documentation and examples.

