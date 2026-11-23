import 'log_entry.dart';

/// Defines when a log action should be executed.
enum LogActionTiming {
  /// Execute before the log is handled.
  before,

  /// Execute after the log is handled.
  after,
}

/// Represents an action that can be executed before or after logging.
abstract class LogAction {
  /// Creates a new log action.
  const LogAction({
    this.timing = LogActionTiming.after,
    this.enabledInProduction = true,
    this.enabledInDebug = true,
  });

  /// When this action should be executed.
  final LogActionTiming timing;

  /// Whether this action is enabled in production mode.
  final bool enabledInProduction;

  /// Whether this action is enabled in debug mode.
  final bool enabledInDebug;

  /// Execute the action.
  /// Returns true if the action was executed successfully.
  Future<bool> execute(LogEntry entry);

  /// Check if this action should be executed based on the current mode.
  bool shouldExecute(bool isProduction) {
    if (isProduction) {
      return enabledInProduction;
    } else {
      return enabledInDebug;
    }
  }
}

/// A simple function-based log action.
class FunctionLogAction extends LogAction {
  /// Creates a function-based log action.
  const FunctionLogAction({
    required this.action,
    super.timing,
    super.enabledInProduction,
    super.enabledInDebug,
  });

  /// The function to execute.
  final Future<bool> Function(LogEntry entry) action;

  @override
  Future<bool> execute(LogEntry entry) => action(entry);
}

/// Example: Email notification action (you would implement the actual email logic).
class EmailNotificationAction extends LogAction {
  /// Creates an email notification action.
  const EmailNotificationAction({
    required this.recipient,
    this.subject = 'Log Alert',
    super.timing = LogActionTiming.after,
    super.enabledInProduction = true,
    super.enabledInDebug = false,
  });

  /// Email recipient.
  final String recipient;

  /// Email subject.
  final String subject;

  @override
  Future<bool> execute(LogEntry entry) async {
    // TODO: Implement actual email sending logic
    // This is a placeholder that you can replace with your email service
    print('📧 Sending email to $recipient: ${entry.message}');
    return true;
  }
}

/// Example: Analytics tracking action.
class AnalyticsAction extends LogAction {
  /// Creates an analytics tracking action.
  const AnalyticsAction({
    super.timing = LogActionTiming.after,
    super.enabledInProduction = true,
    super.enabledInDebug = false,
  });

  @override
  Future<bool> execute(LogEntry entry) async {
    // TODO: Implement actual analytics tracking
    // This is a placeholder for your analytics service
    print('📊 Tracking event: ${entry.level.name} - ${entry.message}');
    return true;
  }
}

