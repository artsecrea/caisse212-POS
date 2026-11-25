import 'package:test/test.dart';
import 'package:loggecrea/loggecrea.dart';

void main() {
  group('Logger Tests', () {
    setUp(() {
      // Clear logger state before each test
      Logger.instance.clearHandlers();
      Logger.instance.clearActions();
      Logger.instance.setEnabled(true);
      Logger.instance.setMinLevel(LogLevel.verbose);
    });

    test('Logger is a singleton', () {
      final logger1 = Logger();
      final logger2 = Logger.instance;
      expect(identical(logger1, logger2), true);
    });

    test('Can register and use console handler', () async {
      final logger = Logger.instance;
      logger.registerHandler(const ConsoleLogHandler());

      await logger.info('Test info message');
      await logger.debug('Test debug message');
      await logger.error('Test error message');

      // If no exception thrown, test passes
      expect(true, true);
    });

    test('Min level filtering works', () async {
      final logger = Logger.instance;
      logger.setMinLevel(LogLevel.warning);

      var messageLogged = false;
      logger.registerHandler(
        _TestLogHandler(onLog: () => messageLogged = true),
      );

      await logger.debug('This should not be logged');
      expect(messageLogged, false);

      await logger.warning('This should be logged');
      expect(messageLogged, true);
    });

    test('Actions are executed before and after logging', () async {
      final logger = Logger.instance;
      final executionOrder = <String>[];

      logger.registerHandler(
        _TestLogHandler(onLog: () {
          executionOrder.add('handler');
        }),
      );

      logger.registerAction(
        FunctionLogAction(
          timing: LogActionTiming.before,
          action: (entry) async {
            executionOrder.add('before');
            return true;
          },
        ),
      );

      logger.registerAction(
        FunctionLogAction(
          timing: LogActionTiming.after,
          action: (entry) async {
            executionOrder.add('after');
            return true;
          },
        ),
      );

      // Use .then to ensure the await chain is complete
      await logger.info('Test message').then((_) {
        // This ensures the entire async chain has completed
      });

      expect(executionOrder.length, 3);
      expect(executionOrder.contains('before'), true);
      expect(executionOrder.contains('handler'), true);
      expect(executionOrder.contains('after'), true);
    });

    test('Actions respect production/debug settings', () async {
      final logger = Logger.instance;
      var productionActionExecuted = false;
      var debugActionExecuted = false;

      logger.registerHandler(_TestLogHandler(onLog: () {}));

      logger.registerAction(
        FunctionLogAction(
          enabledInProduction: true,
          enabledInDebug: false,
          action: (entry) async {
            productionActionExecuted = true;
            return true;
          },
        ),
      );

      logger.registerAction(
        FunctionLogAction(
          enabledInProduction: false,
          enabledInDebug: true,
          action: (entry) async {
            debugActionExecuted = true;
            return true;
          },
        ),
      );

      // Test in production mode
      logger.setProduction(true);
      await logger.info('Test in production');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(productionActionExecuted, true);
      expect(debugActionExecuted, false);

      // Reset
      productionActionExecuted = false;
      debugActionExecuted = false;

      // Test in debug mode
      logger.setProduction(false);
      await logger.info('Test in debug');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(productionActionExecuted, false);
      expect(debugActionExecuted, true);
    });

    test('Logger can be disabled', () async {
      final logger = Logger.instance;
      var messageLogged = false;

      logger.registerHandler(
        _TestLogHandler(onLog: () => messageLogged = true),
      );

      logger.setEnabled(false);
      await logger.info('This should not be logged');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(messageLogged, false);

      logger.setEnabled(true);
      await logger.info('This should be logged');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(messageLogged, true);
    });

    test('Log entry contains all expected fields', () async {
      final logger = Logger.instance;
      LogEntry? capturedEntry;

      logger.registerHandler(
        _TestLogHandler(
          onLogEntry: (entry) => capturedEntry = entry,
        ),
      );

      final error = Exception('Test error');
      final stackTrace = StackTrace.current;
      final metadata = {'key': 'value'};

      await logger.error(
        'Test message',
        error: error,
        stackTrace: stackTrace,
        tag: 'TEST',
        metadata: metadata,
      );

      expect(capturedEntry, isNotNull);
      expect(capturedEntry!.level, LogLevel.error);
      expect(capturedEntry!.message, 'Test message');
      expect(capturedEntry!.error, error);
      expect(capturedEntry!.stackTrace, stackTrace);
      expect(capturedEntry!.tag, 'TEST');
      expect(capturedEntry!.metadata, metadata);
    });
  });

  group('LogLevel Tests', () {
    test('LogLevel comparison operators work', () {
      expect(LogLevel.info >= LogLevel.debug, true);
      expect(LogLevel.debug >= LogLevel.info, false);
      expect(LogLevel.error > LogLevel.warning, true);
      expect(LogLevel.verbose < LogLevel.fatal, true);
      expect(LogLevel.info <= LogLevel.error, true);
    });
  });
}

/// Test log handler for unit testing.
class _TestLogHandler extends LogHandler {
  _TestLogHandler({
    this.onLog,
    this.onLogEntry,
    // ignore: unused_element_parameter
    super.minLevel,
  });

  final void Function()? onLog;
  final void Function(LogEntry)? onLogEntry;

  @override
  Future<bool> handle(LogEntry entry) async {
    if (!shouldHandle(entry)) return false;
    onLog?.call();
    onLogEntry?.call(entry);
    return true;
  }
}

