# Search Order by Code Feature

## Overview
This feature allows you to search for orders by their code directly from the Orders Management screen. The search works in two steps:
1. First, it searches in the local database
2. If not found locally, it queries the server API (if online)

## How to Use

### From Orders Management Screen

1. Click the **Search** icon (🔍) in the top app bar
2. Enter the order code (e.g., "ORD-001")
3. Press Enter or click "Search"

### What Happens

- **Order found locally**: Shows the order details in the existing order details dialog
- **Order not found locally (online)**: Fetches the order from the server and displays it in a beautiful details dialog
- **Order not found locally (offline)**: Shows an error message
- **Order not found anywhere**: Shows "Order not found" error

## Order Details Display

The dialog shows comprehensive order information:

### Header Section
- Order code
- Status badge (Pending, Completed, Cancelled, On Hold)
- Close button

### Order Information
- **Type**: Dine In / Take Away / Delivery
- **Table**: Table name (if applicable)
- **Customer**: Customer name (if applicable)
- **Commercial**: Commercial name (if applicable)
- **Created By**: User who created the order
- **Served By**: User who served the order
- **Date & Time**: When the order was created

### Products Section
Each product shows:
- **Quantity** with visual badge
- **Product name**
- **Station** (kitchen station)
- **Note** (if any, highlighted in amber)
- **Options/Components** with quantities and prices
- **Discounts** (regular and manual)
- **Total price** per product

### Total Amount
- Large, prominent display of the total order amount
- Calculated based on backend logic

## API Endpoint

The feature uses the following API endpoint:

```
GET /api/pos/orders/{orderCode}
```

### Response Format

```json
{
  "id": 123,
  "code": "ORD-001",
  "state": "PENDING",
  "type": "DINE_IN",
  "businessId": 1,
  "tableId": 5,
  "tableName": "Table 5",
  "customerId": 10,
  "customerName": "John Doe",
  "commercialId": null,
  "commercialName": null,
  "createdBy": 1,
  "createdByName": "Admin User",
  "servedBy": 2,
  "servedByName": "Waiter John",
  "dateTime": "2026-02-11T14:30:00",
  "products": [
    {
      "id": 456,
      "productId": 20,
      "productName": "Margherita Pizza",
      "stationName": "Pizza Station",
      "stationId": 3,
      "quantity": 2,
      "price": 12.50,
      "discountAmount": 1.00,
      "manualDiscountAmount": 0.50,
      "totalTva": 2.20,
      "note": "Extra cheese",
      "options": [
        {
          "id": 789,
          "componentId": 15,
          "componentName": "Extra Cheese",
          "quantity": 1,
          "isSpecial": false,
          "price": 2.00
        }
      ]
    }
  ],
  "totalAmount": 50.70,
  "createdAt": "2026-02-11T14:30:00",
  "updatedAt": "2026-02-11T14:35:00"
}
```

## Files Created/Modified

### New Files
1. **lib/presentation/widgets/order_details_dialog.dart**
   - `WebOrderResponse` model class
   - `WebOrderProductResponse` model class  
   - `WebOrderProductOptionResponse` model class
   - `OrderDetailsDialog` widget for beautiful order display

### Modified Files
1. **lib/services/api_service.dart**
   - Added `fetchOrderByCode(String orderCode)` method

2. **lib/presentation/widgets/orders_management_screen.dart**
   - Added search icon button in app bar
   - Added `_showSearchByCodeDialog()` method
   - Added `_searchOrderByCode(String orderCode)` method
   - Added `_showErrorSnackBar(String message)` helper

## Features

✅ **Dual Search**: Checks local database first, then API  
✅ **Beautiful UI**: Material Design 3 with proper theming  
✅ **Responsive**: Works on all screen sizes  
✅ **Dark Mode**: Full dark mode support  
✅ **Status Badges**: Color-coded order status indicators  
✅ **Detailed Info**: Shows all order information including components  
✅ **Offline Support**: Gracefully handles offline state  
✅ **Error Handling**: Clear error messages with dismissible snackbars  
✅ **Loading States**: Shows loading dialog during search  
✅ **Currency Support**: Uses app's configured currency symbol  

## Design Highlights

### Color Coding
- **Pending**: Orange 🟠
- **Completed**: Green 🟢
- **Cancelled**: Red 🔴
- **On Hold**: Blue 🔵

### Product Card Features
- Quantity badge on the left
- Product name in bold
- Station icon and name
- Note highlighted in amber with icon
- Options listed with add icon
- Discounts shown in orange
- Separator lines for clarity

### Responsive Layout
- Maximum width: 800px
- Maximum height: 700px
- Scrollable content area
- Fixed header and footer
- Proper padding and spacing

## Testing

### Test Local Search
1. Create an order in the app
2. Search for its code
3. Should display from local database

### Test API Search
1. Create an order on another device/POS
2. Sync it to the server
3. Search for it on current device
4. Should fetch from API and display

### Test Offline Behavior
1. Disconnect internet
2. Search for a non-local order
3. Should show offline error message

### Test Error Handling
1. Search for non-existent code
2. Should show "Order not found" error
3. Search with invalid server URL
4. Should show connection error

## Future Enhancements

- [ ] Add QR code scanner for order codes
- [ ] Export order details to PDF
- [ ] Print order from details dialog
- [ ] Share order link
- [ ] Recent searches history
- [ ] Auto-complete suggestions

## Troubleshooting

**Issue**: "Order not found" but order exists  
**Solution**: Check if order code matches exactly (case-sensitive)

**Issue**: API not called when order not local  
**Solution**: Ensure device is online and server URL is configured

**Issue**: Loading dialog doesn't close  
**Solution**: Check console for API errors, may be network timeout

**Issue**: Currency symbol wrong  
**Solution**: Configure correct currency in Settings screen

---

**Status**: ✅ Complete and Ready to Use  
**Version**: 1.0.0  
**Last Updated**: 2026-02-11
