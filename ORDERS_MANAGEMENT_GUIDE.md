# Orders Management Screen - Quick Guide

## Access
1. Click on your profile avatar in the top-right corner
2. Select "orders" from the dropdown menu
3. The Orders Management screen will open

## Main Features

### 1. Search Orders
- Type in the search box to filter orders by:
  - Order code
  - Username

### 2. Filter by Status
Use the dropdown to show only:
- All Statuses
- On Hold
- Pending
- Preparing
- Ready
- Delivered
- Canceled

### 3. Filter by Date
- Click "Date Range" button
- Select start and end dates
- Click "X" to clear the date filter

### 4. Sort Columns
- Click any column header to sort
- Click again to reverse the sort order
- Sortable columns:
  - ID, Code, Username, Products, Discount, TVA
  - Subtotal, Total, Paid, Status, Date

### 5. Navigate Pages
- Use the bottom controls to navigate:
  - |< First page
  - < Previous page
  - > Next page
  - >| Last page
- See "Page X of Y" and "Showing 1-10 of 45 orders"

### 6. View Order Details
- Click the 👁️ (eye) icon in the Actions column
- See complete order information including:
  - Order details (ID, code, status, type, etc.)
  - All items with components
  - Paid status for each item
  - Financial summary with totals

### 7. Delete Order
- Click the 🗑️ (trash) icon in the Actions column
- Confirm deletion in the dialog
- Order and all related data will be deleted

### 8. Refresh
- Click the refresh icon (↻) in the top-right
- Reloads all orders with current filters

## Understanding the Table

### Columns Explained
| Column | Description |
|--------|-------------|
| ID | Database order ID |
| Code | Unique order code (e.g., ABC12345) |
| Username | Who created/handled the order |
| Products | Number of products in order |
| Discount | Total discount applied |
| TVA | Total tax amount |
| Subtotal | Before discounts and tax |
| Total | Final amount to be paid |
| Paid | Amount already paid (from tickets) |
| Status | Current order status |
| Date | When order was created |
| Actions | View/Edit/Delete buttons |

### Status Colors
- 🟠 **Orange** = On Hold
- 🔵 **Blue** = Pending
- 🟣 **Purple** = Preparing
- 🟢 **Green** = Ready
- ⚪ **Grey** = Delivered
- 🔴 **Red** = Canceled

### Paid Amount Colors
- 🟢 **Green** = Fully paid (Paid ≥ Total)
- 🟠 **Orange** = Partially paid (Paid < Total)

## Tips

1. **Quick Find**: Use the search box to quickly locate orders by code
2. **Check Payments**: Look at the Paid column to see payment status
3. **Filter Active Orders**: Set status to "Pending" or "Preparing" to see active orders
4. **Today's Orders**: Use date range to show only today's orders
5. **Sort by Total**: Click Total column to see highest/lowest value orders

## Keyboard Shortcuts
- **Tab**: Navigate between filter fields
- **Enter**: Apply search filter
- **Escape**: Close detail dialog

## Mobile/Tablet View
- Table scrolls horizontally for smaller screens
- All features remain accessible
- Touch-friendly buttons and controls

