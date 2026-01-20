# Offline Delete/Update Sync Implementation - Setup Guide

## 🎯 Overview
This system allows the app to queue delete and update operations when offline, then automatically sync them when the network connection is restored.

## ✅ What's Been Implemented

### 1. **Database Table: PendingSyncOperations**
Location: `/lib/data/database/tables/pending_sync_operation_table.dart`

Tracks operations that need to be synced:
- `operationType`: 'DELETE' or 'UPDATE'
- `entityType`: 'ORDER', 'TICKET', 'ORDER_PRODUCT'
- `entityId`: Local database ID
- `serverId`: Server ID (if already synced)
- `updateData`: JSON for UPDATE operations
- `retryCount`, `lastError`: For retry logic

### 2. **PendingOperationsService**
Location: `/lib/services/pending_operations_service.dart`

Methods:
- `queueDelete()` - Queue a delete operation
- `queueUpdate()` - Queue an update operation
- `getPendingOperations()` - Get all pending operations
- `markCompleted()` - Remove from queue after successful sync
- `recordFailure()` - Track failed attempts

### 3. **DataSyncService Updates**
Location: `/lib/services/data_sync_service.dart`

New methods:
- `syncPendingOperations()` - Process all pending operations
- `deleteEntity()` - Execute delete immediately if online, queue if offline
- `updateEntity()` - Execute update immediately if online, queue if offline
- `queueDelete()` - Wrapper for queueing deletes
- `queueUpdate()` - Wrapper for queueing updates

### 4. **ApiService Updates**
Location: `/lib/services/api_service.dart`

Added HTTP methods:
- `deleteOrder(serverId)`
- `deleteTicket(serverId)`
- `deleteOrderProduct(serverId)`
- `updateOrder(serverId, updateData)`
- `updateTicket(serverId, updateData)`
- `updateOrderProduct(serverId, updateData)`

### 5. **Network Status Providers**
Location: `/lib/providers/network_provider.dart`

Providers:
- `connectivityProvider` - Monitors network connectivity
- `isOnlineProvider` - Checks network + server reachability
- `lastKnownOnlineStatusProvider` - Synchronous online status
- **Auto-sync trigger**: When network comes back online, automatically syncs pending operations

### 6. **Order Panel Integration**
Location: `/lib/presentation/widgets/order_panel.dart`

Updated `_showDeletePaidItemDialog()` to:
- Check online status before deleting
- Queue operations when offline
- Execute immediately when online
- Handle both ticket deletion and ticket amount updates

## 🔧 Required Setup Steps

### Step 1: Generate Database Code
Run this command to generate the drift database code:

```bash
cd /home/artecrea/StudioProjects/posecrea
dart run build_runner build --delete-conflicting-outputs
```

This will generate:
- `PendingSyncOperation` class
- `PendingSyncOperationsCompanion` class
- Database table accessors

### Step 2: Update Database Version (If Needed)
If you want to trigger a migration, update in `/lib/data/database/app_database.dart`:

```dart
@override
int get schemaVersion => 2; // Increment from 1 to 2
```

**WARNING**: Current code says "never change the db version, just delete the db file to reset"

### Step 3: Initialize Network Provider
In your main app widget, make sure to initialize the network provider so it starts monitoring:

```dart
// In main.dart or root widget
Consumer(
  builder: (context, ref, child) {
    // This initializes the network monitoring
    ref.watch(lastKnownOnlineStatusProvider);
    return YourApp();
  },
)
```

### Step 4: Test the System

#### Test Offline Delete:
1. Turn off network
2. Delete a paid item from order panel (long press)
3. Check `pending_sync_operations` table - should have DELETE record
4. Turn on network
5. Check logs - should see "Deleted order product #X from server"
6. Check table - operation should be removed

#### Test Offline Update:
1. Turn off network
2. Delete one item from multi-item ticket (triggers update)
3. Check table - should have UPDATE record with new amount
4. Turn on network
5. Operation auto-syncs

## 📊 How It Works

### Online Flow:
```
User Action → Check isOnline → Execute API Call → Update Local DB
```

### Offline Flow:
```
User Action → Check isOnline → Update Local DB → Queue Operation
```

### Auto-Sync Flow:
```
Network Restored → Trigger syncPendingOperations() → Process Queue → Remove Completed
```

## 🔄 Integration Points

### To Use in Other Screens/Services:

```dart
// Get the sync service
final syncService = ref.read(dataSyncServiceProvider);
final isOnline = ref.read(lastKnownOnlineStatusProvider);

// Delete an order
await syncService.deleteEntity(
  entityType: 'ORDER',
  entityId: localOrderId,
  serverId: serverOrderId, // null if not synced yet
  isOnline: isOnline,
);

// Update a ticket
await syncService.updateEntity(
  entityType: 'TICKET',
  entityId: localTicketId,
  serverId: serverTicketId,
  updateData: {'amount': 25.50, 'status': 'paid'},
  isOnline: isOnline,
);
```

## 🌐 Server API Endpoints Expected

The server needs these endpoints:

```
DELETE /api/pos/orders/{id}
DELETE /api/pos/tickets/{id}
DELETE /api/pos/order-products/{id}

PUT /api/pos/orders/{id}
PUT /api/pos/tickets/{id}
PUT /api/pos/order-products/{id}
```

## 🐛 Error Handling

- Failed operations are tracked with `retryCount` and `lastError`
- Auto-sync continues even if some operations fail
- Failed operations remain in queue for next sync attempt
- Manual cleanup available via `clearOldOperations(daysOld: 30)`

## 📝 Database Queries

Check pending operations:
```sql
SELECT * FROM pending_sync_operations;
```

Clear all pending:
```sql
DELETE FROM pending_sync_operations;
```

## ✨ Future Enhancements

Possible improvements:
1. Add retry limit (e.g., after 5 failures, mark as permanent failure)
2. Add manual sync button in settings
3. Show pending operations count in UI
4. Conflict resolution (if server data changed while offline)
5. Batch operations for better performance
6. Add support for other entity types (Customers, Sessions, etc.)

## 🎉 Status

✅ Table created
✅ Service implemented  
✅ API methods added
✅ Network monitoring added
✅ Auto-sync on reconnect added
✅ Order panel integrated
⏳ Database code generation (needs build_runner)
⏳ Testing required
⏳ Server API implementation required

