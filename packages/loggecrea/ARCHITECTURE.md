# Loggecrea Architecture Diagram

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Flutter App                          │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ Logger.instance.info("message")
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Logger (Singleton)                           │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ • setMinLevel()                                           │  │
│  │ • setProduction()                                         │  │
│  │ • setEnabled()                                            │  │
│  │ • registerHandler()                                       │  │
│  │ • registerAction()                                        │  │
│  │ • log(), info(), debug(), error(), etc.                  │  │
│  └───────────────────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ Creates LogEntry
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                        LogEntry                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ • level: LogLevel                                         │  │
│  │ • message: String                                         │  │
│  │ • timestamp: DateTime                                     │  │
│  │ • tag: String?                                            │  │
│  │ • error: Object?                                          │  │
│  │ • stackTrace: StackTrace?                                │  │
│  │ • metadata: Map<String, dynamic>                         │  │
│  └───────────────────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Processing Pipeline                            │
│                                                                   │
│  Step 1: Execute BEFORE Actions                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ • FunctionLogAction (before)                            │    │
│  │ • Custom Before Actions                                 │    │
│  │ • Filtered by production/debug                          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                         │                                         │
│                         ▼                                         │
│  Step 2: Execute Handlers (Parallel)                            │
│  ┌──────────────┬──────────────┬──────────────┬──────────────┐  │
│  │   Console    │     File     │   Database   │    Custom    │  │
│  │   Handler    │   Handler    │   Handler    │   Handler    │  │
│  │              │              │              │              │  │
│  │ • Colors     │ • Rotation   │ • Persist    │ • Your       │  │
│  │ • Emojis     │ • Size mgmt  │ • Query      │   Logic      │  │
│  │ • Format     │ • Archives   │ • Indexes    │              │  │
│  └──────────────┴──────────────┴──────────────┴──────────────┘  │
│                         │                                         │
│                         ▼                                         │
│  Step 3: Execute AFTER Actions                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ • EmailNotificationAction                               │    │
│  │ • AnalyticsAction                                       │    │
│  │ • FunctionLogAction (after)                             │    │
│  │ • Custom After Actions                                  │    │
│  │ • Filtered by production/debug                          │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Output Destinations                       │
│  ┌─────────────┬────────────┬──────────────┬────────────────┐   │
│  │   Console   │   File     │   Database   │   External     │   │
│  │             │            │              │   Service      │   │
│  │ stdout      │ app.log    │ SQLite/etc   │ API calls      │   │
│  └─────────────┴────────────┴──────────────┴────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Log Levels Flow

```
User Code
    │
    ├─ logger.verbose("msg")  ──┐
    ├─ logger.debug("msg")    ──┤
    ├─ logger.info("msg")     ──┤
    ├─ logger.warning("msg")  ──┼──▶ Check minLevel ──▶ Process if level >= minLevel
    ├─ logger.error("msg")    ──┤                       │
    └─ logger.fatal("msg")    ──┘                       ▼
                                                    Dropped if below minLevel
```

## Handler Selection

```
LogEntry
    │
    ├─ Level: INFO
    │  Tag: AUTH
    │  Message: "User logged in"
    │
    ▼
┌──────────────────────────────────────┐
│  For each registered handler:        │
│  ┌────────────────────────────────┐  │
│  │  if (entry.level >= minLevel)  │  │
│  │    handler.handle(entry)       │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
    │
    ├─▶ ConsoleLogHandler (minLevel: VERBOSE) ──▶ ✅ Handled
    ├─▶ FileLogHandler (minLevel: INFO)       ──▶ ✅ Handled
    └─▶ DatabaseLogHandler (minLevel: ERROR)  ──▶ ❌ Skipped
```

## Action Execution Flow

```
Production Mode: true
    │
    ▼
EmailNotificationAction
    ├─ enabledInProduction: true   ──▶ ✅ Execute
    └─ enabledInDebug: false

DebugLoggingAction
    ├─ enabledInProduction: false  ──▶ ❌ Skip
    └─ enabledInDebug: true

AnalyticsAction
    ├─ enabledInProduction: true   ──▶ ✅ Execute
    └─ enabledInDebug: false
```

## Riverpod Integration Flow

```
┌─────────────────────────────────────┐
│         ProviderScope               │
│  ┌───────────────────────────────┐  │
│  │  final loggerProvider =       │  │
│  │    Provider<Logger>((ref) {   │  │
│  │      return configureLogger();│  │
│  │    });                        │  │
│  └───────────────────────────────┘  │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│      ConsumerWidget                 │
│  ┌───────────────────────────────┐  │
│  │  final logger =               │  │
│  │    ref.watch(loggerProvider); │  │
│  │  logger.info("Widget built"); │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

## Extension Points

```
Your Custom Components
    │
    ├─▶ Custom Handler (extends LogHandler)
    │       │
    │       ├─ Implement handle()
    │       ├─ Optional: Override shouldHandle()
    │       └─ Optional: Override close()
    │
    ├─▶ Custom Action (extends LogAction)
    │       │
    │       ├─ Implement execute()
    │       ├─ Set timing (before/after)
    │       └─ Set production/debug flags
    │
    └─▶ Custom LogEntry processing
            │
            └─ Access entry.metadata for custom data
```

## Thread Safety & Async

```
Multiple log() calls
    │
    ├─ log("A") ─┐
    ├─ log("B") ─┤
    ├─ log("C") ─┼─▶ All queued
    └─ log("D") ─┘
            │
            ▼
    Processed sequentially (await)
            │
            ├─ Before actions (parallel via Future.wait)
            ├─ Handlers (parallel via Future.wait)
            └─ After actions (parallel via Future.wait)
```

## File Handler Rotation

```
app.log (current)
    │
    ├─ Size check
    │      │
    │      ├─ < maxSize ──▶ Continue writing
    │      │
    │      └─ >= maxSize ──▶ Rotate
    │                         │
    │                         ├─ app.log.4 ──▶ Delete
    │                         ├─ app.log.3 ──▶ Rename to app.log.4
    │                         ├─ app.log.2 ──▶ Rename to app.log.3
    │                         ├─ app.log.1 ──▶ Rename to app.log.2
    │                         ├─ app.log   ──▶ Rename to app.log.1
    │                         └─ Create new app.log
```

## Configuration Cascade

```
main()
    │
    └─▶ setupLogger()
            │
            ├─ Set production mode
            ├─ Set min level
            ├─ Register handlers
            └─ Register actions
                    │
                    ▼
            App runs with configuration
                    │
                    ├─ All log() calls use same config
                    ├─ Change config anytime
                    └─ Effects are immediate
```

## Key Design Patterns

1. **Singleton** - Logger.instance
2. **Strategy** - Pluggable handlers
3. **Observer** - Actions listen to log events
4. **Chain of Responsibility** - Multiple handlers process each log
5. **Template Method** - LogHandler base class
6. **Factory** - configureLogger() helper

