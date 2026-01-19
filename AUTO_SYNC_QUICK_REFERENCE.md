# Auto-Sync & Data Retention - Quick Reference

## Settings Location
**Settings → Sync & Data**

## Default Values
- **Auto-Sync Online**: ON
- **Bulk Sync Size**: 50 orders
- **Data Retention**: 7 days

## How Orders Are Synced

### Online (Auto-Sync Enabled)
```
Order Completed → ✓ Online → Sync Immediately → Server Updated
```

### Offline (Queued)
```
Order Completed → ✗ Offline → Queue → Bulk Sync (5min) → Server Updated
```

### Manual Sync
```
User Clicks Sync → Upload Queued → Download Fresh → Old Data Cleaned
```

## Configuration Guide

### Auto-Sync Online
- **ON**: Orders sync immediately when completed (if online)
- **OFF**: All orders wait for bulk sync

### Bulk Sync Size
- **10-30**: Low-volume, slow connection
- **30-70**: Medium-volume, normal connection
- **70-100**: High-volume, fast connection

### Data Retention Days
- **1-3**: Minimal storage, frequent refresh
- **7-14**: Balanced (recommended)
- **15-30**: Maximum history

## What Gets Synced

### Immediately (If Auto-Sync ON + Online)
- Completed orders with all products
- Product components
- Applied discounts
- Customer/commercial info

### In Bulk (Every 5 Minutes)
- Queued completed orders
- Failed auto-syncs
- Offline orders

### Never Synced
- Draft orders (not completed)
- Orders with unpaid items
- Demo mode orders

## Data Cleanup

### Cleared on Refresh
✅ Products, Categories, Users, Tables, etc. (Master data)

### Preserved Until Retention
✅ Orders (unsynced or recent)
✅ Tickets (unsynced or recent)
✅ Sessions (unsynced or recent)
✅ Customers (unsynced or recent)

### Deleted After Retention
❌ Synced orders older than X days
❌ Synced tickets older than X days
❌ Synced sessions older than X days
❌ Synced customers older than X days

## Triggering Sync

### Automatic
- Order completed → Auto-sync (if enabled + online)
- Every 5 minutes → Bulk sync (if unsynced orders + online)

### Manual
- Top bar → Sync button → Full sync + cleanup

## Monitoring

### Check Sync Status
- Unsynced orders visible in Orders Management
- `isSynced = false` flag in database

### Verify Auto-Sync Working
1. Complete an order (pay all items)
2. Check logs: "Order X auto-synced successfully"
3. Or: "Order X queued for bulk sync"

## Troubleshooting

### Orders Not Syncing?
- Check network connectivity
- Verify auto-sync enabled in settings
- Ensure order is COMPLETED (all items paid)
- Check demo mode is OFF

### Too Much Data?
- Reduce retention days (1-7)
- Run manual sync to trigger cleanup
- Check bulk sync size not too large

### Sync Too Slow?
- Reduce bulk sync size (10-30)
- Check network speed
- Enable auto-sync for immediate backup

## Code Examples

### Trigger Auto-Sync
```dart
final syncManager = ref.read(syncManagerProvider.notifier);
await syncManager.autoSyncOrder(orderId);
```

### Trigger Bulk Sync
```dart
final syncManager = ref.read(syncManagerProvider.notifier);
final count = await syncManager.performBulkSync();
print('Synced $count orders');
```

### Check Settings
```dart
final settings = ref.read(settingsProvider);
if (settings.autoSyncOnline) {
  // Auto-sync is enabled
}
```

## Best Practices

✅ **Keep auto-sync ON** - Immediate backup
✅ **Set retention 7-14 days** - Balance storage/history
✅ **Adjust bulk size to network** - Optimize for connection
✅ **Monitor sync status** - Check for stuck orders
✅ **Test offline mode** - Verify queue works

## Tips

💡 **High-volume**: Increase bulk size, decrease retention
💡 **Slow network**: Decrease bulk size, keep auto-sync
💡 **Audit needs**: Increase retention to 30 days
💡 **Storage limited**: Decrease retention to 3 days
💡 **Always offline**: Disable auto-sync, manual sync daily

