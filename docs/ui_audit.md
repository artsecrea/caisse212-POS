# UI Audit — caisse212

A pass over `lib/presentation/` to catalog UI debt that's grown organically
across the app. Generated 2026-06-14. Each item names what's wrong, the
files involved, the recommended fix, and a rough effort label.

**Legend:**
- **Impact:** 🔴 high (visible to cashiers daily / breaks dark mode / a11y) ·
  🟡 medium (polish, theme consistency) · 🟢 low (style hygiene)
- **Effort:** S = under 1h · M = 1–3h · L = a day or more

---

## 1. Theme tokens — `Theme.of(context).primaryColor` (🔴 High · M)

**Why it matters.** The app uses Material 3 (`useMaterial3: true` in
`app_theme.dart`). `primaryColor` is the M2 holdover that bypasses the M3
`colorScheme`. Calls work today because Material's compatibility shim maps
it, but it doesn't respect dark mode tonal shifts and won't pick up future
theme tweaks.

**Scope.** 20 files. Verified via grep — `lib/presentation/**`:

```
api_tester_screen.dart                report_issue_dialog.dart
session_details_screen.dart           sessions_management_screen.dart
settings_screen.dart                  table_selection_dialog.dart
tenant_login_screen.dart              tickets_management_screen.dart
tenant_screen.dart                    top_bar.dart
category_grid.dart                    waiter_selection_dialog.dart
category_selector.dart                commercial_selection_dialog.dart
devices_management_screen.dart        manual_discount_dialog.dart
orders_management_screen.dart         product_modification_dialog.dart
settings_screen_backup.dart (dead)    settings_screen_new.dart (dead)
```

**Fix.**
- `Theme.of(context).primaryColor` → `Theme.of(context).colorScheme.primary`
- Where it was paired with `Colors.white` as `foregroundColor`, swap to
  `Theme.of(context).colorScheme.onPrimary` so dark mode behaves correctly.
- The two `settings_screen_backup.dart` / `settings_screen_new.dart` files
  are dead per `CLAUDE.md` — delete them in the same pass.

**Verification.** After the sweep, `grep -rn "Theme.of(context).primaryColor" lib/` returns zero matches.

---

## 2. Hardcoded `Colors.X.shade` / `Colors.X[NNN]` (🔴 High · M)

**Why it matters.** Reads `Colors.blue[50]` / `Colors.red.shade300` /
`Colors.green[700]` etc. that bypass `colorScheme`. These look great in
light mode and are **legibility hazards in dark mode** (`Colors.blue[50]`
on a dark background is white-on-dark light blue text — unreadable).

**Scope.** 34 files in `lib/presentation/`. Notable offenders:
- `close_session_dialog.dart`, `daily_summary_dialog.dart`,
  `external_orders_tab.dart`, `orders_management_screen.dart`,
  `customer_selection_dialog.dart`, `tenant_login_screen.dart`,
  `report_issue_dialog.dart`.

**Mapping cheat-sheet:**

| Old | M3 token |
|---|---|
| `Colors.blue[50]` / `Colors.blue.shade50` | `cs.secondaryContainer` or `cs.surfaceContainerLow` |
| `Colors.blue[700]` | `cs.onSecondaryContainer` |
| `Colors.red.shade50` / `Colors.red[50]` | `cs.errorContainer` |
| `Colors.red.shade300` / `Colors.red.shade700` | `cs.error` / `cs.onErrorContainer` |
| `Colors.green[xxx]` | `cs.tertiary` / `cs.tertiaryContainer` (semantic "success") |
| `Colors.orange[xxx]` | `cs.tertiary` (warnings) — or define a `warning` token in theme |
| `Colors.grey[xxx]` | `cs.onSurfaceVariant` for muted text |

**Recommended approach.** Don't sweep blindly — go file-by-file in priority
order: `close_session_dialog`, `daily_summary_dialog`,
`orders_management_screen` first (most visible). The remaining 30+ files can
be batched.

---

## 3. Direct `ScaffoldMessenger…showSnackBar` everywhere (🔴 High · M)

**Why it matters.** A `SnackBarHelper` already exists at
`lib/utils/snackbar_helper.dart` and is **settings-aware** (respects
`settings.enableSnackBars`). But hundreds of direct
`ScaffoldMessenger.of(context).showSnackBar(SnackBar(... backgroundColor:
Colors.red))` calls bypass it — cashiers can't disable noise even when they
turn the setting off. The helper also hardcodes `Colors.red.shade700`
itself, which is ironic given (2).

**Scope.** Counts of `showSnackBar` calls per file (top offenders):

```
orders_management_screen.dart    13
payment_screen.dart              12
devices_management_screen.dart    9
login_screen.dart                 9
settings_screen.dart              9
session_details_screen.dart       6
daily_summary_dialog.dart         5
...
```

**Fix.**
1. Rewrite `SnackBarHelper` so it takes `BuildContext` only (no `ref`) and
   uses `colorScheme.error` / `colorScheme.errorContainer` / `colorScheme.tertiary`
   tokens internally. Provide three call sites:
   `SnackBarHelper.error(context, msg)`,
   `SnackBarHelper.success(context, msg)`,
   `SnackBarHelper.info(context, msg)`.
2. Migrate all direct `showSnackBar(... Colors.red)` to the helper.
3. The settings gate (`enableSnackBars`) stays — but lives behind a
   convenience factory `SnackBarHelper.maybeShow(ref, ...)` for routine
   notifications. Errors should always show regardless of the setting.

**Recommended sequencing:** ship the helper rewrite first, then do the
file-by-file migration over a few days.

---

## 4. Border radius inconsistency (🟡 Medium · S)

**Why it matters.** `BorderRadius.circular(...)` is called **343 times**
across `lib/presentation/`. The distribution:

```
   143 ×  8
    70 × 12
    35 × 10
    26 × 16
    18 ×  6
    18 × 20
    17 ×  4
     9 × 14
     3 ×  7
     1 each: 9, 3, 2, 18
```

13 distinct radii is a tell that no design system exists. Cards at 8 here,
12 there; one-off `9` and `7` look like accidents.

**Fix.** Define 4 tokens in `lib/core/theme/app_theme.dart`:

```dart
class AppRadius {
  static const xs   = 6.0;   // chips, badges, dense inputs
  static const sm   = 10.0;  // buttons, list items
  static const md   = 14.0;  // cards, form fields, dialogs
  static const lg   = 20.0;  // hero cards, modal sheets
}
```

Bulk-replace existing usages by approximation (4→6, 8→10, 12/14→14, 16/20→20).
Visual diff before merging — some buttons use 8 deliberately to look pill-y.

---

## 5. Hardcoded English strings (🔴 High · M)

**Why it matters.** Arabic and French users see English in 95+ places. We
ship to ar/fr customers as a primary use case.

**Sample offenders** (capital-first `Text('...')` not preceded by
`l10n.translate`):

```
Text('Close')           Text('Reset')           Text('Reconnect')
Text('Cancel')          Text('Save')            Text('Retry')
Text('Verify')          Text('Today')           Text('Next day')
Text('Unassigned')      Text('External')        Text('Session paused')
Text('Session resumed')
```

Many of these likely have existing keys — e.g. `close`, `cancel`, `save`,
`reset` are universal POS terms.

**Fix.**
1. Run `grep -rohE "Text\('[A-Z][a-zA-Z ]+'" lib/presentation` and audit
   the 95 unique strings.
2. For each: if a key exists in `app_localizations.dart`, use it; else add
   one (en/ar/fr).
3. Add a `dart analyze` rule via `lints` or a custom lint to flag
   `Text('Capitalized')` literals — prevents regression.

---

## 6. `TextField` vs `OnscreenKeyboardTextField` coverage (🟡 Medium · S)

**Why it matters.** Tablet cashiers can't bring up the on-screen keyboard
on plain `TextField`s, blocking them from typing in 31 of the 46 textfield
sites. The dialogs that already converted (`customer_selection_dialog`,
`orders_management_screen`) work fine.

**Counts:**
- 31 files use `TextField` / `TextFormField`
- 15 files use `OnscreenKeyboardTextField`

**Fix.** Triage 31 files by call site:
- **Cashier flow** (anything the cashier touches during normal service) →
  convert to `OnscreenKeyboardTextField`.
- **Admin/settings flow** (admin-only screens that assume a physical
  keyboard) → leave as-is. Settings screens, printer-management,
  user-management.

Per-file decision goes faster than a blanket rule. Estimated ~10 of the 31
genuinely need conversion.

---

## 7. Dialog inconsistency (🟡 Medium · L)

**Why it matters.** Every dialog rolls its own `AlertDialog` /
`showDialog`, with hand-tuned padding, title styles, action button colors.
Result: title fonts vary, "Cancel" sits left in some, right in others,
"Save" is `ElevatedButton` here, `FilledButton` there, `TextButton`
elsewhere.

**Fix.** Build a tiny `AppDialog` wrapper:

```dart
showAppDialog<T>(
  context: context,
  title: 'Delete printer',
  body: Text('Remove "Bar" from the pool?'),
  primaryAction: ('Delete', () => Navigator.pop(context, true), kind: .destructive),
  secondaryAction: ('Cancel', () => Navigator.pop(context, false)),
);
```

Migrate dialogs file-by-file. ~50 dialog call sites in the codebase.

---

## 8. Touch targets — IconButtons without explicit size (🟡 Medium · S)

**Why it matters.** Material 3's default `IconButton` is 48dp tap target,
which is fine on touch screens. But the `top_bar`, several management
screens, and some dialogs use `Icon` inside `InkWell` with `Padding(12)` —
that's a 48dp target only when the icon is 24dp. The `_GlassButton` in
login was originally on the edge.

**Fix.** Sweep `lib/presentation/` for `Icon(...)` inside `InkWell` /
`GestureDetector` and verify total tap-area is ≥ 48×48dp. Wrap small
icons in `SizedBox(width: 48, height: 48)` where they fall short.

---

## 9. Dark mode hazards (🔴 High · M)

**Why it matters.** Items (2) and (5) of this audit collectively break dark
mode in dozens of places. Specifically:
- `Container(decoration: BoxDecoration(color: Colors.white))` — white-on-
  white in dark mode.
- `TextStyle(color: Colors.black)` — invisible.
- `backgroundColor: Colors.grey[100]` — washed out.

**Fix.** After items (1)-(2) land, do a manual dark-mode walkthrough of
each screen group and fix what's left:
1. Login → Main screen → Order panel
2. Payment → Order confirmation
3. Settings → Printers management
4. Sessions → Orders management → Tickets management

Recommend a side-by-side screenshot diff (light vs dark) per screen to
catch hairline issues.

---

## 10. Empty / loading / error states (🟡 Medium · M)

**Why it matters.** Management screens currently show `Text('—')`,
`CircularProgressIndicator()`, or `Text('Error: $e')` for these three
states. No consistent visual treatment.

**Fix.** Three reusable widgets:

```dart
AppEmpty(icon: Icons.print_outlined, message: 'No printers yet')
AppLoading(message: 'Loading orders…')
AppError(message: 'Couldn\'t load orders', onRetry: refetch)
```

Use across all `AsyncValue.when(...)` call sites. Migrate the management
screens first since they have the most async surface area.

---

## 11. Animation cost on cold start (🟢 Low · S)

**Why it matters.** Login screen has 900ms+ of staggered animations. On
low-end Android, that's measurable frame drops. The animation looks
great, but it should bail when the OS asks for reduced motion.

**Fix.** Gate `_entranceCtrl.forward()` behind
`MediaQuery.disableAnimationsOf(context)`:

```dart
if (MediaQuery.disableAnimationsOf(context)) {
  _entranceCtrl.value = 1.0;
} else {
  _entranceCtrl.forward();
}
```

Apply the same guard to any future hero/page-transition work.

---

## 12. Login screen — user selector as touch grid (🟡 Medium · M)

**Why it matters.** Cashiers log in 5–20 times a day. The current
`DropdownButtonFormField` pattern requires "tap → scroll → tap" — slower
than "tap your name from a grid of avatars".

**Status.** Already proposed in this session as Pass B. Not in scope of
this audit, but flagging here so it doesn't get lost.

---

## Suggested execution order

Items 1, 2, 3, 5 are the most user-visible and overlap heavily — do them
together as a "theme + l10n sweep" of one screen at a time. Pattern:

1. Pick a screen.
2. Replace `primaryColor` → `colorScheme.primary` (item 1).
3. Replace `Colors.X[NNN]` / `.shade` with tokens (item 2).
4. Migrate snackbars via the new helper (item 3).
5. Replace hardcoded English Text literals (item 5).
6. Verify in both light & dark mode.
7. Commit.

Items 4, 6, 7, 8 are mechanical cleanups that can ride along when a screen
is otherwise being touched.

Items 9, 10 are end-state polishes — do after 1-5 are mostly done.

Item 11 is opportunistic — one line fix when next in the login file.

---

## Out of scope (separately tracked)

- Per-station printer routing (already landed — see `printers_management_screen.dart`).
- External-order confirm review dialog (separate plan).
- Session-close email report (see `docs/session_close_email_report.md`).
- Login user-selector grid redesign — opt-in Pass B in the same session
  this doc was written.
