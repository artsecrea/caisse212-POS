# Order Logging System Guide

## Overview

The order logging system tracks all order changes (creation, updates, deletions) in the `order_logs` table. This enables efficient synchronization between the POS app and external systems (KDS, backend server, etc.).

## Database Schema

### OrderLogs Table
```dart
class OrderLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer().references(Orders, #id)();
  TextColumn get action => text()(); // 'CREATED', 'UPDATED', 'DELETED'
  TextColumn get description => text().nullable()(); // eg 'Order created via API'
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}
```

## Automatic Logging

All order operations are automatically logged:

### 1. Order Creation
When an order is created (either via UI or API), a log entry is created with action `'CREATED'`.

**In OrderRepository:**
```dart
await _logService.logOrderCreated(orderId, 'Order created with code $orderCode, status $status');
```

**In Server API:**
```dart
await logService.logOrderCreated(orderId, 'Order created via API: code=${socketOrder.code}');
```

### 2. Order Updates
When an order is updated (products added/removed, status changed, etc.), a log entry is created with action `'UPDATED'`.

**In OrderRepository:**
```dart
await _logService.logOrderUpdated(orderId, 'Order updated: code=$orderCode');
await _logService.logOrderUpdated(orderId, 'Order status changed from $oldStatus to $status');
```

**In Server API:**
```dart
await logService.logOrderUpdated(id, 'Order status updated to $statusParam via API');
await logService.logOrderUpdated(id, 'Order fully updated via API');
```

### 3. Order Deletion
When an order is deleted, a log entry is created with action `'DELETED'`.

**In OrderRepository:**
```dart
await _logService.logOrderDeleted(orderId, 'Order deleted: code=${order.code}');
```

## Server API Endpoint

### GET /orders
Returns orders based on query parameters.

**Query Parameters:**
- `since` (optional): ISO 8601 date string. Returns orders created since this date.
- `updated_after_log_id` (optional): Integer. Returns updated orders since this log ID.
- `station` (optional): Filter by station name.
- `status` (optional): Comma-separated status values (e.g., `PENDING,ONHOLD`).

**Default Behavior:**
If no parameters are provided, returns orders from today.

**Response Format:**
```json
{
  "orders": [...],              // New orders created since 'since' parameter
  "orders_updated": [...],      // Full orders that were updated
  "orders_deleted": [1, 5, 10], // IDs of deleted orders
  "last_log_id": 42,            // Latest log ID for next request
  "count": 5,
  "updated_count": 3,
  "deleted_count": 2
}
```

## Usage Examples

### Example 1: Get Today's Orders
```http
GET /orders
```
Returns all orders created, updated, or deleted today.

### Example 2: Get Orders Since Specific Date
```http
GET /orders?since=2026-02-20T00:00:00.000Z
```
Returns orders created on or after Feb 20, 2026.

### Example 3: Get Updated Orders Since Last Sync
```http
GET /orders?updated_after_log_id=42
```
Returns orders that were updated since log ID 42.

### Example 4: Combined Parameters
```http
GET /orders?since=2026-02-20T00:00:00.000Z&updated_after_log_id=42&status=PENDING,COMPLETED
```
Returns:
- New orders created since Feb 20 with status PENDING or COMPLETED
- Orders updated since log ID 42
- Deleted order IDs since log ID 42

### Example 5: KDS Integration (Filter by Station)
```http
GET /orders?station=Kitchen&status=PENDING
```
Returns only orders with products assigned to the "Kitchen" station and status PENDING.

## Client Workflow

### Initial Sync
```dart
// First request - get all orders from today
final response = await http.get('/orders');
final data = jsonDecode(response.body);

// Process orders
processOrders(data['orders']);
processUpdatedOrders(data['orders_updated']);
processDeletedOrders(data['orders_deleted']);

// Save last_log_id for next request
final lastLogId = data['last_log_id'];
```

### Incremental Sync
```dart
// Subsequent requests - only get changes since last sync
final response = await http.get('/orders?updated_after_log_id=$lastLogId');
final data = jsonDecode(response.body);

// Only updated and deleted orders will have data
processUpdatedOrders(data['orders_updated']);
processDeletedOrders(data['orders_deleted']);

// Update last_log_id
lastLogId = data['last_log_id'];
```

## OrderLogService API

### Methods

#### logOrderCreated
```dart
await logService.logOrderCreated(orderId, 'Description of creation');
```

#### logOrderUpdated
```dart
await logService.logOrderUpdated(orderId, 'Description of update');
```

#### logOrderDeleted
```dart
await logService.logOrderDeleted(orderId, 'Description of deletion');
```

#### getUpdatedOrdersSinceLogId
```dart
final updatedOrderIds = await logService.getUpdatedOrdersSinceLogId(42);
// Returns: [5, 7, 10]
```

#### getDeletedOrdersSinceLogId
```dart
final deletedOrderIds = await logService.getDeletedOrdersSinceLogId(42);
// Returns: [3, 8]
```

#### getUpdatedOrdersToday
```dart
final updatedOrderIds = await logService.getUpdatedOrdersToday();
```

#### getDeletedOrdersToday
```dart
final deletedOrderIds = await logService.getDeletedOrdersToday();
```

#### getLastUpdateLogId
```dart
final lastLogId = await logService.getLastUpdateLogId();
// Returns: 42
```

## Benefits

1. **Efficient Syncing**: Only fetch changed data instead of all orders
2. **Audit Trail**: Complete history of all order changes
3. **Reliable**: Doesn't rely on `updatedAt` timestamps which can be unreliable
4. **Scalable**: Works efficiently with large datasets
5. **Flexible**: Supports both date-based and ID-based incremental sync

## Notes

- Log entries are never deleted automatically
- The `last_log_id` returned by the API can be used for the next request
- Deleted order IDs are returned even though the orders no longer exist
- Multiple updates to the same order will create multiple log entries
- The system uses `DISTINCT` order IDs when querying logs to avoid duplicates

