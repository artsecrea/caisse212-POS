## 0.0.1

### Initial Release

**Features:**

- ✨ **Singleton Logger** - Single instance throughout the application
- 🎯 **Multiple Log Levels** - Verbose, Debug, Info, Warning, Error, Fatal
- 🔌 **Pluggable Handlers** - Console, File, or create custom handlers
- ⚡ **Before/After Actions** - Execute custom logic before or after logging
- 🎛️ **Environment-Aware** - Different behavior for debug and production modes
- 🎨 **Colored Console Output** - Beautiful, emoji-enhanced console logs with ANSI colors
- 📝 **File Logging** - Automatic file rotation and size management
- 🏷️ **Tagged Logs** - Categorize logs with custom tags
- 📋 **Metadata Support** - Attach structured data to log entries
- 🚫 **No External Dependencies** - Pure Dart/Flutter implementation
- 🌊 **Riverpod Ready** - Easy integration with Riverpod state management
- 🔧 **Fully Customizable** - Create custom handlers and actions
- ✅ **Comprehensive Tests** - Well-tested with unit tests

**Components:**

- `Logger` - Main singleton logger class
- `LogLevel` - Log severity levels enum
- `LogEntry` - Log entry data model
- `LogHandler` - Abstract handler base class
- `LogAction` - Abstract action base class
- `ConsoleLogHandler` - Console output handler with colors
- `FileLogHandler` - File output handler with rotation
- `FunctionLogAction` - Function-based action implementation
- `EmailNotificationAction` - Email notification action example
- `AnalyticsAction` - Analytics tracking action example
- `configureLogger()` - Helper function for Riverpod integration

**Examples:**

- Basic usage example
- Riverpod integration example
- Complete Flutter app example
