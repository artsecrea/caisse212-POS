# Order Workflow Implementation

## Summary
Implemented a comprehensive order workflow management system with proper state tracking for orders and items through the Proceed, Pay, and Hold actions.

## Changes Made

### 1. Order Item State Tracking (`lib/domain/models/order_models.dart`)
- **Added `state` field** to `OrderItem` class to track item status (PENDING, ONHOLD, PAID, etc.)
- Updated `copyWith()` method to include state parameter
- Updated `toJson()` to export state field
- Removed unused `_isSaved` field from `CurrentOrder`

### 2. Order Repository Updates (`lib/providers/order_provider.dart`)

#### `saveOrder()` Method
- Now sets item state based on order status
- Items in ONHOLD orders get 'ONHOLD' state
- Items in PENDING orders get 'PENDING' state

#### `holdOrder()` Method
- **Validation**: Prevents holding saved orders with new unsaved items
  - Checks for items without database IDs (new items)
  - Throws error message: "Cannot hold order with new items. Press Proceed first to save them."
- **Updates item states**: Sets all unpaid items to 'ONHOLD' state when holding
- **Order status**: Updates order status to 'ONHOLD' in database

#### `loadOrderDetails()` Method
- Now loads and includes item state from database

### 3. Payment Screen Updates (`lib/presentation/paymen_screen/payment_screen.dart`)

#### `_payTicket()` Method
- **Updates item states**: When a ticket is paid, sets all items to 'PAID' state
- Updates both database records and UI state
- Properly tracks ticket IDs and payment states

#### Import Cleanup
- Removed incorrect import statement that was causing compile errors

### 4. Main Screen Button Logic (`lib/presentation/main_screen/main_screen.dart`)

#### **Proceed Button**
- Saves/updates order with status 'PENDING'
- New items get 'PENDING' state
- **Reloads order** from database to show updated IDs and states
- **Does NOT clear order** - allows continued editing
- Success message: "Order saved successfully"

#### **Pay Button**
- **Saves/updates order first** before opening payment screen
- Reloads order from database to get proper IDs
- Opens payment screen with reloaded order
- After payment screen closes:
  - If payment completed: clears order
  - If cancelled: reloads order to show updated payment states
- Handles errors with proper error messages

#### **Hold Button**
- Validates that saved orders don't have new items
- Shows error if trying to hold saved order with new items
- Updates order and item states to 'ONHOLD'
- Clears order after successful hold
- Success message: "Order held successfully" (orange background)

### 5. Order Panel Visual Indicators (`lib/presentation/widgets/order_panel.dart`)

#### Held Items Display
- **Orange border** (2px) for held items
- **Orange background** (Colors.orange[50])
- **"On Hold" badge**:
  - Orange background with border
  - Pause icon
  - Shows below product name

#### Card Styling
- Paid items: Grey background with lock icon
- Held items: Orange theme with pause icon badge
- Regular items: White background

## Workflow Summary

### User Actions:

1. **Proceed**
   - Saves order as PENDING
   - Items become PENDING state
   - Order stays loaded for continued editing
   - Can add more items and press Proceed again

2. **Pay**
   - Saves/updates order first
   - Opens payment screen
   - User can split into tickets
   - When ticket is paid, those items become PAID state
   - Can partially pay (some tickets) and close
   - Order reloads with updated states

3. **Hold**
   - New orders: Saves as ONHOLD with items in ONHOLD state
   - Saved orders: Only if no new items added
   - Shows error if new items exist (must Proceed first)
   - Clears order after holding

### Item States:
- **PENDING**: New items or items in active orders
- **ONHOLD**: Items in held orders (orange badge)
- **PAID**: Items in paid tickets (green badge with lock)

### Visual Indicators:
- **Regular items**: White card, grey border
- **Held items**: Orange card, orange thick border, "On Hold" badge
- **Paid items**: Grey card, grey border, "Paid - Ticket #X" badge, lock icon

## Notes
- Items without database IDs are considered "new" and must be saved via Proceed before Hold
- Paid items cannot be edited, deleted, or moved
- Order stays loaded after Proceed to allow continued editing
- Payment screen automatically reloads order to get proper database IDs for tickets

