# Login Screens Visual Guide

## Tenant Login Screen Layout

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│              🔄 (Icon - 80px)                       │
│                                                     │
│           POS System Setup                          │
│     Connect to your server or use demo mode        │
│                                                     │
│  ┌──────────────────────────────────────┐ 🔧       │
│  │ Server URL (Read-only)               │ Settings │
│  │ http://localhost:8080                │          │
│  └──────────────────────────────────────┘          │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │ 📍 POS Name *                              │   │
│  │ test                                        │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │ 👤 Username *                              │   │
│  │                                             │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │ 🔒 Password *                    👁         │   │
│  │ ••••••••                                    │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  [ERROR MESSAGE IF ANY - Red background]          │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │     ☁️ Connect to Server (60px height)     │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  ─────────────── OR ───────────────                │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │      🧪 Use Demo Mode (60px height)        │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │    🐛 Test API Endpoints (50px height)     │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │    ⚠️ Report Issue (50px height)           │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Login Screen Layout

```
┌─────────────────────────────────────────────────────┐
│ 🚪              POS System             🐛           │
│ Exit                                   Report       │
│ (52px)                                 (52px)       │
│                                                     │
│              🏪 (Icon - 80px)                       │
│                                                     │
│              POS System                             │
│           Please sign in to continue                │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │ 👤 Username *                              │   │
│  │                                             │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │ 🔒 Password *                    👁         │   │
│  │ ••••••••                                    │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │ 💰 Starting Balance                        │   │
│  │ 0.0                                         │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  [ERROR MESSAGE IF ANY - Red background, 16px pad] │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │      🔓 Sign In (60px height)              │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Server Settings Dialog Flow

### Step 1: Password Protection
```
┌─────────────────────────────────────┐
│  Server Settings                    │
│                                     │
│  Enter admin password to modify     │
│  server URL:                        │
│                                     │
│  ┌────────────────────────────┐    │
│  │ 🔐 Admin Password       👁 │    │
│  │ Default: admin123          │    │
│  └────────────────────────────┘    │
│                                     │
│         [Cancel]  [Verify]          │
└─────────────────────────────────────┘
```

### Step 2: URL Editor (after password verified)
```
┌─────────────────────────────────────┐
│  Edit Server URL                    │
│                                     │
│  ┌────────────────────────────┐    │
│  │ 🌐 Server URL              │    │
│  │ http://localhost:8080      │    │
│  └────────────────────────────┘    │
│                                     │
│  Examples:                          │
│  • http://localhost:8080            │
│  • http://192.168.1.100:8080        │
│  • https://api.example.com          │
│                                     │
│         [Cancel]  [Save]            │
└─────────────────────────────────────┘
```

## Button Hierarchy

### Primary Actions (60px height)
- **Connect to Server** - Blue, filled, bold
- **Use Demo Mode** - Blue outline, bold
- **Sign In** - Blue, filled, bold

### Secondary Actions (50px height)
- **Test API Endpoints** - Orange outline
- **Report Issue** - Text button style

### Icon Buttons (52px total)
- **Exit** (top-left) - Black38 background, 36px icon
- **Report** (top-right) - Black38 background, 36px icon
- **Settings** (inline) - Grey background, 24px icon

## Color Scheme

### Primary Elements
- Primary Color: Theme primary color (typically blue)
- Text: Black (87% opacity for body text)
- Icons: Theme primary or grey[700]

### Error States
- Background: red[50]
- Border: red[300] (2px)
- Text: red[700]
- Icon: red[700]

### Disabled States
- Background: grey[300]
- Text: grey[500]
- No elevation

### Loading States
- Spinner: White on primary buttons
- Button text: "Connecting..." / "Loading..."

## Typography

### Headers
- Size: 24-28px (headlineMedium)
- Weight: Bold
- Color: Theme primary

### Subheaders
- Size: 14px
- Weight: Normal
- Color: grey[600]

### Form Labels
- Size: 16px
- Weight: Normal
- Color: grey[800]

### Button Text
- Primary: 18px, Bold
- Secondary: 16px, Normal

### Error Text
- Size: 14px
- Weight: Medium (w500)
- Color: red[700]

## Spacing

### Form Fields
- Between fields: 20px
- Before buttons: 32px
- After headers: 32px

### Buttons
- Internal padding: 16px vertical
- Between buttons: 12px
- Icon-text gap: 12px

### Card/Dialog
- Outer padding: 40px
- Max width: 500px (login), 500px (tenant)

### Corner Elements
- Top/left margin: 20px
- Border radius: 16px
- Internal padding: 16px

## Border Radius

- Form fields: 12px
- Buttons: 12px
- Cards: 16px
- Error containers: 12px
- Icon buttons: 16px

## Elevation

- Cards: 8
- Primary buttons: 4
- Icon buttons: 4
- Dialogs: 24 (default)

## Icons

### Sizes
- Main icons (headers): 80px
- Button icons: 24-28px
- Corner buttons: 36px
- Form field icons: 24px
- Settings icon: 24px

### Common Icons Used
- 🔄 cloud_sync (tenant login header)
- 🏪 point_of_sale (login header)
- 👤 person (username)
- 🔒 lock (password)
- 💰 account_balance_wallet (balance)
- 🌐/📍 dns/point_of_sale (server/POS)
- 🔧 settings (server settings)
- 🚪 exit_to_app (exit)
- 🐛 bug_report (report issue)
- ☁️ cloud_done (connect)
- 🧪 science (demo)
- ⚠️ error_outline (errors)
- 👁 visibility/visibility_off (password toggle)

