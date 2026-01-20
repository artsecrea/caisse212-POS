# ⚡ Quick Start - Offline Sync System

## 🚀 3 Steps to Get Running

### Step 1: Generate Database Code (REQUIRED)
```bash
cd /home/artecrea/StudioProjects/posecrea
dart run build_runner build --delete-conflicting-outputs
```

### Step 2: Initialize in Main App
Add to `lib/main.dart`:
```dart
@override
Widget build(BuildContext context) {
  return Consumer(
    builder: (context, ref, child) {
      ref.watch(lastKnownOnlineStatusProvider); // ← Add this line
      return MaterialApp(
        // ...rest of your app
      );
    },
  );
}
```

### Step 3: Test It!
1. Long-press a paid item in order panel
2. Confirm delete
3. ✅ Works offline (queues operation)
4. ✅ Works online (deletes immediately)
5. ✅ Auto-syncs when network returns

---

## 📚 Full Documentation

- **Detailed Guide**: `OFFLINE_SYNC_IMPLEMENTATION.md`
- **API Specs**: `SERVER_API_ENDPOINTS.md`
- **Complete Summary**: `SYNC_SYSTEM_SUMMARY.md`

---

## 🎯 What You Get

✅ Offline delete tracking
✅ Offline update tracking  
✅ Auto-sync on reconnect
✅ Order panel integration
✅ Network status monitoring
✅ Error handling & retries

---

## 🐛 If Something Goes Wrong

**Compilation errors?**
→ Run build_runner (Step 1)

**Not syncing?**
→ Initialize network provider (Step 2)

**API errors?**
→ Check `SERVER_API_ENDPOINTS.md` for required endpoints

---

## 💡 Quick Example

```dart
// Delete an order (works offline & online)
final syncService = ref.read(dataSyncServiceProvider);
final isOnline = ref.read(lastKnownOnlineStatusProvider);

await syncService.deleteEntity(
  entityType: 'ORDER',
  entityId: 123,
  serverId: 456,
  isOnline: isOnline,
);
```

That's it! 🎉

