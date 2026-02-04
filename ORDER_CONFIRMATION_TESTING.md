# Order Confirmation Feature - Testing Guide

## Prerequisites
- Application running
- At least one order with status "ONHOLD" in the database
- User logged in with appropriate permissions

## How to Test

### Test 1: View On-Hold Orders
1. Launch the application
2. Click the **"Confirm Order"** button (purple button in the top action bar)
3. **Expected Result**: 
   - Screen shows all orders with "ONHOLD" status
   - Each order displays: Code, Item count, Type, Persons (if > 1), Total amount
   - If no orders, shows "No orders on hold" message

### Test 2: Search Functionality
1. In the Confirm Order screen with multiple orders
2. Type an order code in the search box at the top
3. **Expected Result**: 
   - Orders list filters to show only matching orders
   - Search is case-insensitive
   - Results update as you type

### Test 3: Select and View Order Details
1. Click on any order in the list
2. **Expected Result**:
   - Order is highlighted with a different background color
   - Right panel shows:
     - Order header with code and "Order On Hold" badge
     - List of all items with quantities and prices
     - Three action buttons at the bottom

### Test 4: Confirm Order (Send to KDS)
1. Select an order
2. Click the green **"Confirm Order"** button
3. **Expected Result**:
   - Success message appears: "Order [CODE] confirmed and sent to KDS"
   - Order status changes from "ONHOLD" to "PENDING"
   - Order disappears from the on-hold list
   - Screen closes and returns to main screen

### Test 5: Confirm and Pay
1. Select an order
2. Click the blue **"Confirm & Pay"** button
3. **Expected Result**:
   - Order status changes from "ONHOLD" to "PENDING"
   - Payment screen opens with the selected order
   - User can proceed with payment
   - After payment, order status remains "PENDING" (NOT COMPLETED)

### Test 6: Cancel Selection
1. Select an order
2. Click the **"Cancel"** button
3. **Expected Result**:
   - Right panel returns to empty state
   - Shows "Select an order to confirm" message
   - No changes made to the order

### Test 7: Empty State
1. Ensure there are no orders with "ONHOLD" status
2. Click the **"Confirm Order"** button
3. **Expected Result**:
   - Shows "No orders on hold" message
   - Empty state icon displayed
   - No orders in the list

### Test 8: Order from External Device (Integration)
This test requires an external device/system that can create orders:
1. Create an order from external device with status "ONHOLD"
2. Open Confirm Order screen in POS
3. Find the newly created order
4. Confirm it
5. **Expected Result**:
   - Order appears in the list
   - Can be confirmed and sent to KDS
   - Status changes to "PENDING"

### Test 9: Payment Flow (No Status Change)
1. Create or find an order with status "PENDING"
2. Navigate to payment screen
3. Complete payment for all items
4. Check order status
5. **Expected Result**:
   - Payment completes successfully
   - Tickets are created
   - Order status remains "PENDING" (should NOT change to "COMPLETED")

### Test 10: Multi-language Support
1. Change app language to Arabic
2. Open Confirm Order screen
3. **Expected Result**: All UI text displays in Arabic
4. Change to French
5. **Expected Result**: All UI text displays in French
6. Change back to English
7. **Expected Result**: All UI text displays in English

### Test 11: Dark Mode
1. Enable dark mode in settings
2. Open Confirm Order screen
3. **Expected Result**:
   - All colors adapt to dark theme
   - Text remains readable
   - Cards and backgrounds use appropriate dark colors

### Test 12: Error Handling
1. Disconnect from database (simulate error)
2. Try to confirm an order
3. **Expected Result**:
   - Error message displayed to user
   - No crash
   - User can try again

## Edge Cases to Test

### Edge Case 1: Order with No Items
- Create an ONHOLD order with 0 items
- Should display with 0 items count

### Edge Case 2: Order with Large Number of Items
- Create an ONHOLD order with 20+ items
- Should display all items in scrollable list

### Edge Case 3: Order with Long Code
- Create order with very long code
- Should display without text overflow

### Edge Case 4: Multiple Users
- User A creates ONHOLD order
- User B confirms it
- Should work correctly

### Edge Case 5: Network Issues During Confirm
- Disconnect network
- Try to confirm order
- Should queue for sync when network returns

## Performance Tests

### Test 1: Many Orders
- Create 50+ ONHOLD orders
- Open Confirm Order screen
- **Expected**: Loads quickly, smooth scrolling

### Test 2: Search Performance
- With 50+ orders, type in search
- **Expected**: Instant filtering, no lag

## Known Limitations
1. Cannot batch-confirm multiple orders (future enhancement)
2. Cannot modify order before confirmation (future enhancement)
3. Search only by order code (not by customer, items, etc.)

## Bug Report Template
If you find a bug, report it with:
- **Steps to Reproduce**: 
- **Expected Behavior**: 
- **Actual Behavior**: 
- **Screenshots**: 
- **Device/Platform**: 
- **App Version**: 
- **Additional Notes**: 
