# Empty Database Logout Feature

## Overview

Added automatic full logout when the database is found to be empty during login attempt. This prevents users from being stuck with an empty database and forces them to reconnect to the server or use demo mode.

## Implementation

### File Modified: `lib/presentation/login_screen/login_screen.dart`

#### Changes:

1. **Added Imports**:
   - `ApiService` - for clearing authentication data
   - `DataSyncService` - for clearing database

2. **Updated Login Logic**:
   - Checks if database has any users before attempting login
   - If no users exist (`isFirstTime == true`), triggers full logout
   - Shows informative dialog to the user

3. **Added Method: `_performFullLogout`**:
   ```dart
   Future<void> _performFullLogout(String message)
   ```
   
   This method:
   - Shows a dialog explaining the issue
   - Clears current user and session from providers
   - Clears API authentication data (access token, POS name, etc.)
   - Clears all database tables
   - Redirects to tenant login screen (`/tenant`)

## Flow

```
┌─────────────────────┐
│  User Opens App     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Check Setup        │
│  (token/demo mode)  │
└──────────┬──────────┘
           │
           ▼
    ┌──────────────┐
    │ Has Setup?   │
    └──────┬───────┘
           │
      ┌────┴────┐
      │ No      │ Yes
      ▼         ▼
   ┌─────┐  ┌──────┐
   │/tenant│  │/login│
   └─────┘  └───┬──┘
                │
                ▼
         ┌──────────────┐
         │ Check Users  │
         │  in Database │
         └──────┬───────┘
                │
         ┌──────┴─────┐
         │ Has Users? │
         └──────┬─────┘
                │
        ┌───────┴────────┐
        │ No             │ Yes
        ▼                ▼
   ┌──────────┐    ┌─────────────┐
   │ Full     │    │ Continue    │
   │ Logout   │    │ Normal Login│
   └────┬─────┘    └─────────────┘
        │
        ▼
   ┌─────────┐
   │/tenant  │
   │(restart)│
   └─────────┘
```

## User Experience

### Scenario: Empty Database on Second Login

1. User opens app
2. App detects setup exists (has token or demo mode)
3. Shows login screen
4. User enters credentials
5. System detects database has no users
6. Dialog appears:
   ```
   Title: "Database Error"
   Message: "Database is empty. Please reconnect to server or use demo mode."
   Button: "Reconnect"
   ```
7. User clicks "Reconnect"
8. All authentication data cleared
9. Database cleared
10. Redirects to tenant login screen
11. User can choose to connect to server or use demo mode

## Why This Is Needed

- **Database Corruption**: If the database file gets corrupted or accidentally deleted
- **Manual Database Deletion**: If user manually deletes the database file
- **Development/Testing**: When database schema changes require fresh start
- **Error Recovery**: Provides clean recovery path instead of error loops

## Related Files

- `lib/services/api_service.dart` - Handles clearing auth data
- `lib/services/data_sync_service.dart` - Handles clearing database
- `lib/presentation/tenant_login_screen/tenant_login_screen.dart` - Destination after logout

## Testing

To test this feature:

1. Login to the app normally
2. Close the app
3. Delete or rename the database file: `posecread11fe1zefd.db`
4. Reopen the app
5. Try to login
6. Verify that full logout dialog appears
7. Click "Reconnect"
8. Verify redirect to tenant login screen

## Notes

- The feature only triggers during login attempt, not on app startup
- User credentials are not validated if database is empty
- All SharedPreferences keys are cleared (except persistent settings)
- Full database wipe ensures clean state

