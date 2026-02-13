# 🔐 Server Configuration - Quick Reference Card

## 📅 Today's Password
**Date:** February 13, 2026  
**Password:** `20260213`

---

## 🎯 Where to Use

### Tenant Login Screen
- **Location:** Config icon ⚙️ in center of form
- **Purpose:** Reveal/edit server URL
- **Action:** Click icon → Enter password → Edit URL

### Login Screen  
- **Location:** Config icon ⚙️ in top-right corner
- **Purpose:** View server configuration
- **Action:** Click icon → Enter password → View info

---

## 🔢 Password Format

```
YYYY MM DD
│    │  │
│    │  └─ Day (2 digits)
│    └──── Month (2 digits)
└─────── Year (4 digits)
```

### Examples
| Date | Correct Password | ❌ Wrong |
|------|------------------|----------|
| Feb 13, 2026 | `20260213` | 2026-02-13 |
| Mar 1, 2026 | `20260301` | 202631 |
| Dec 25, 2026 | `20261225` | 12/25/2026 |

---

## ⚡ Quick Actions

### Change Server URL
1. Full logout (requires tenant password)
2. On Tenant Login screen
3. Click ⚙️ → Enter `20260213`
4. Edit URL → Save

### View Server Info
1. On Login screen
2. Click ⚙️ (top-right)
3. Enter `20260213`
4. View info → OK

---

## ✅ Validation Rules

**Server URL must:**
- Start with `http://` or `https://`
- Not be empty
- Be a valid URL format

**Examples:**
- ✅ `http://localhost:8080`
- ✅ `http://192.168.1.100:8080`
- ✅ `https://api.example.com`
- ❌ `localhost:8080` (missing http://)
- ❌ `www.example.com` (missing protocol)

---

## 🆘 Troubleshooting

### "Invalid password" error
→ Check you're using today's date  
→ Format must be YYYYMMDD  
→ No spaces, dashes, or slashes

### Can't see server URL field
→ Click ⚙️ config icon first  
→ Enter today's password  
→ Field will appear

### Can't change server URL on Login screen
→ This is by design  
→ Use Full Logout instead  
→ Change on Tenant Login screen

---

## 🔒 Security Layers

```
┌─────────────────────────────┐
│ Hidden UI (Default)         │ ← Layer 1
├─────────────────────────────┤
│ Date Password (YYYYMMDD)    │ ← Layer 2
├─────────────────────────────┤
│ Tenant Password             │ ← Layer 3
└─────────────────────────────┘
```

---

## 📱 Screen Locations

```
TENANT LOGIN               LOGIN SCREEN
┌─────────────┐           ┌─────────────┐
│             │           │        ⚙️ 🐛 │
│             │           │             │
│     ⚙️      │           │   [Login]   │
│             │           │             │
│   [Login]   │           │             │
│             │           │             │
└─────────────┘           └─────────────┘
```

---

## 📞 Need Help?

**Password:** Today's date = `20260213`  
**Format:** YYYYMMDD (8 digits)  
**No:** dashes, slashes, or spaces

---

**Print this card and keep it near your POS terminal!** 📄

