# Session Code Implementation Summary

## Changes Made

### 1. Database Schema Update
**File**: `lib/data/database/tables/cash_session_table.dart`
- Added `code` field: `TextColumn get code => text().unique()();`
- This field will be used by the backend as the primary identifier for sessions

### 2. Session Code Generation
**File**: `lib/services/session_service.dart`
- Updated `startSession()` method to generate unique session codes
- Format: `CS-YYYYMMDD-HHMMSS-XXX` (e.g., `CS-20260127-143052-123`)
- Updated `endSession()` to use session code when queuing update operations
- Updated `deleteSession()` to use session code when queuing delete operations

### 3. API Service Updates
**File**: `lib/services/api_service.dart`
- Updated `syncSingleSession()` to accept `sessionCode` (String) instead of `sessionId` (int)
- Updated `deleteSession()` to accept `sessionCode` (String) instead of `sessionId` (int)
- Updated `updateSession()` to accept `sessionCode` (String) instead of `sessionId` (int)
- All session endpoints now use `/pos/cash-sessions/{sessionCode}`

### 4. Pending Operations Service
**File**: `lib/services/pending_operations_service.dart`
- Updated `queueSessionDelete()` to use `sessionCode` instead of `sessionId`
- Updated `queueSessionUpdate()` to use `sessionCode` instead of `sessionId`
- Session codes are stored in `updateData` JSON as `_sessionCode`

### 5. Data Sync Service
**File**: `lib/services/data_sync_service.dart`
- Updated `getSessionsForSync()` to include session `code` in sync data
- Updated `getTicketsForSync()` to fetch and include session codes for tickets
- Updated `syncSingleSession()` to use session code instead of ID
- Updated `_processPendingDelete()` SESSION case to use session code
- Updated `_processPendingUpdate()` SESSION case to use session code
- Updated `deleteSessionEntity()` to use session code
- Updated `updateSessionEntity()` to use session code

## Required Actions

### ⚠️ IMPORTANT: Database Regeneration Required

After adding the `code` field to the CashSessions table, you MUST regenerate the database:

```bash
cd /home/artecrea/StudioProjects/posecrea
flutter pub run build_runner build --delete-conflicting-outputs
```

This will:
1. Generate the new `CashSession` class with the `code` field
2. Update all database companions and queries
3. Fix all the compilation errors related to missing `code` getter

### Database Migration

Since we changed the schema, existing sessions in the database won't have codes. You have two options:

**Option 1: Delete and recreate the database** (recommended for development)
```bash
# Delete the existing database file
rm -rf <app_documents_directory>/.hgkvhg.db
# App will create new database with updated schema on next run
```

**Option 2: Add migration code** (for production)
Add a migration in `app_database.dart`:
```dart
@override
int get schemaVersion => 2; // Increment version

@override
MigrationStrategy get migration => MigrationStrategy(
  onUpgrade: (migrator, from, to) async {
    if (from == 1) {
      // Add code column to existing sessions table
      await migrator.addColumn(cashSessions, cashSessions.code);
      
      // Generate codes for existing sessions
      final sessions = await select(cashSessions).get();
      for (final session in sessions) {
        final now = session.startedAt;
        final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
        final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
        final code = 'CS-$dateStr-$timeStr-${session.id.toString().padLeft(3, '0')}';
        
        await (update(cashSessions)..where((t) => t.id.equals(session.id)))
          .write(CashSessionsCompanion(code: Value(code)));
      }
    }
  },
);
```

## Backend API Endpoints

The backend should support these endpoints:

### Session Endpoints
- `PUT /api/pos/cash-sessions/{sessionCode}` - Create or update session
- `DELETE /api/pos/cash-sessions/{sessionCode}` - Delete session
- `POST /api/pos/cash-sessions/bulk` - Bulk create/update sessions

### Expected Session Data Format
```json
{
  "code": "CS-20260127-143052-123",
  "cashierId": 1,
  "moneyAtStart": 100.0,
  "moneyAtEnd": 500.0,
  "status": "ended",
  "startedAt": "2026-01-27T14:30:52.000Z",
  "endedAt": "2026-01-27T22:15:30.000Z",
  "pausedAt": null
}
```

### Ticket Data with Session Code
```json
{
  "num": "T001",
  "orderCode": "ORD-20260127-143052-001",
  "sessionCode": "CS-20260127-143052-123",
  "paymentMethod": "CASH",
  "amount": 25.50,
  "isPaid": true
}
```

## Testing Checklist

After regenerating the database:

- [ ] Create a new session - verify code is generated
- [ ] End a session - verify it queues update with session code when synced
- [ ] Delete a session - verify it queues delete with session code when synced
- [ ] Sync sessions to server - verify session code is used in API calls
- [ ] Sync tickets to server - verify session codes are included
- [ ] Test offline mode - verify pending operations use session codes
- [ ] Test pending operations sync - verify session operations execute correctly

## Session Code Format Details

**Format**: `CS-YYYYMMDD-HHMMSS-XXX`

Where:
- `CS` = Cash Session prefix
- `YYYYMMDD` = Date (e.g., 20260127)
- `HHMMSS` = Time (e.g., 143052)
- `XXX` = Microsecond suffix for uniqueness (first 3 digits)

**Example**: `CS-20260127-143052-123`

This ensures:
- ✅ Globally unique codes
- ✅ Human-readable format
- ✅ Sortable by creation time
- ✅ No dependency on auto-increment IDs

