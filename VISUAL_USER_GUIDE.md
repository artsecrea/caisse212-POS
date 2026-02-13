# Visual User Guide - Server Configuration

## Tenant Login Screen - Before and After

### BEFORE (Server URL Visible - Old Design)
```
┌─────────────────────────────────────────┐
│         POS System Setup                │
│   Connect to your server or demo        │
│                                          │
│  ┌─────────────────────────┬──────┐    │
│  │ Server URL              │ ⚙️   │    │
│  │ http://localhost:8080   │      │    │
│  └─────────────────────────┴──────┘    │
│                                          │
│  [ POS Name: test          ]            │
│  [ Username:               ]            │
│  [ Password:               ]            │
│                                          │
│  [  Connect to Server  ]                │
│           OR                             │
│  [  Use Demo Mode     ]                 │
└─────────────────────────────────────────┘
```

### AFTER (Server URL Hidden - New Design)
```
┌─────────────────────────────────────────┐
│         POS System Setup                │
│   Connect to your server or demo        │
│                                          │
│            [ ⚙️ ]                        │
│       (Click to configure)               │
│                                          │
│  [ POS Name: test          ]            │
│  [ Username:               ]            │
│  [ Password:               ]            │
│                                          │
│  [  Connect to Server  ]                │
│           OR                             │
│  [  Use Demo Mode     ]                 │
└─────────────────────────────────────────┘
```

### When Config Icon Clicked
```
┌─────────────────────────────────────────┐
│       Server Settings                    │
│                                          │
│  Enter today's date as password          │
│  (YYYYMMDD):                            │
│                                          │
│  ┌─────────────────────────────────┐    │
│  │ Password                         │    │
│  │ Example: 20250213                │    │
│  └─────────────────────────────────┘    │
│                                          │
│         [ Cancel ]  [ Verify ]          │
└─────────────────────────────────────────┘
```

### After Password Verified
```
┌─────────────────────────────────────────┐
│         POS System Setup                │
│   Connect to your server or demo        │
│                                          │
│  ┌─────────────────────────┬──────┐    │
│  │ Server URL              │ 👁️   │    │
│  │ http://localhost:8080   │      │    │
│  └─────────────────────────┴──────┘    │
│  (Now editable - click 👁️ to hide)     │
│                                          │
│  [ POS Name: test          ]            │
│  [ Username:               ]            │
│  [ Password:               ]            │
│                                          │
│  [  Connect to Server  ]                │
│           OR                             │
│  [  Use Demo Mode     ]                 │
└─────────────────────────────────────────┘
```

## Login Screen - New Config Icon

### Screen Layout
```
┌─────────────────────────────────────────┐
│  ↩️                          ⚙️  🐛     │ ← Top buttons
│                                          │
│         ┌─────────────────┐             │
│         │                  │             │
│         │   POS Login      │             │
│         │                  │             │
│         │  Username: [ ]   │             │
│         │  Password: [ ]   │             │
│         │  Balance:  [ ]   │             │
│         │                  │             │
│         │  [ Sign In ]     │             │
│         │                  │             │
│         └─────────────────┘             │
│                                          │
└─────────────────────────────────────────┘

Legend:
↩️  = Exit to Tenant (requires tenant password)
⚙️  = Server Config (requires date password)
🐛 = Report Issue
```

### Config Dialog (After Password Entry)
```
┌─────────────────────────────────────────┐
│     Server Configuration                 │
│                                          │
│  Current Configuration:                  │
│                                          │
│  Server URL:    http://localhost:8080   │
│  Demo Mode:     No                       │
│                                          │
│  ╔════════════════════════════════════╗ │
│  ║ ℹ️  To change server settings,     ║ │
│  ║    logout completely and reconnect ║ │
│  ║    from the tenant screen.         ║ │
│  ╚════════════════════════════════════╝ │
│                                          │
│                    [ OK ]                │
└─────────────────────────────────────────┘
```

## User Workflow

### Scenario 1: IT Admin Sets Up New POS Terminal

1. ✅ App opens to Tenant Login screen
2. ✅ Admin clicks ⚙️ config icon
3. ✅ Enters today's date (e.g., `20250213`)
4. ✅ Server URL field appears
5. ✅ Admin enters server URL (e.g., `http://192.168.1.100:8080`)
6. ✅ Clicks hide icon to secure it
7. ✅ Completes login with credentials
8. ✅ Data syncs from server
9. ✅ Ready for use

### Scenario 2: Cashier Daily Login

1. ✅ App opens to Login screen (server already configured)
2. ✅ Cashier does NOT see server URL
3. ✅ Cashier enters username and password
4. ✅ Clicks Sign In
5. ✅ Ready to work

### Scenario 3: Manager Checks Server Config

1. ✅ Manager at Login screen
2. ✅ Clicks ⚙️ config icon in top-right
3. ✅ Enters today's date (e.g., `20250213`)
4. ✅ Views current server configuration
5. ✅ Clicks OK
6. ✅ (Cannot change here - must logout completely)

### Scenario 4: Change Server URL

1. ✅ User needs to change server
2. ✅ Goes to dropdown menu → Full Logout
3. ✅ Enters tenant password for verification
4. ✅ Returns to Tenant Login screen
5. ✅ Clicks ⚙️ config icon
6. ✅ Enters today's date
7. ✅ Server URL field appears
8. ✅ Changes URL
9. ✅ Reconnects with new server

## Security Benefits

### Hidden by Default
- ❌ Casual users cannot see server URL
- ❌ Casual users cannot change server URL
- ✅ Clean, simple interface for daily use

### Protected Access
- ✅ Date-based password required
- ✅ Password changes daily automatically
- ✅ No hard-coded credentials to leak

### Layered Security
```
┌─────────────────────────────────────────┐
│  Server URL Access                       │
│                                          │
│  Layer 1: Hidden by default (UI)        │
│  Layer 2: Date password (Config)        │
│  Layer 3: Tenant password (Full Logout) │
│                                          │
└─────────────────────────────────────────┘
```

## Troubleshooting

### "Invalid password" when trying to access config
- ✅ Check today's date
- ✅ Format must be YYYYMMDD
- ✅ Example: Feb 13, 2025 = `20250213`
- ✅ No dashes, slashes, or spaces

### Cannot change server URL in Login screen
- ✅ This is by design
- ✅ Must logout completely (Full Logout)
- ✅ Return to Tenant Login screen
- ✅ Then access config

### Forgot tenant password
- ❌ Cannot recover
- ⚠️ May need to reinstall app
- ⚠️ Will lose all local data
- ✅ Can still use demo mode

