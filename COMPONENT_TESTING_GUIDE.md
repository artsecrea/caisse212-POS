# Component Fixes Testing Guide

## Overview
This guide provides step-by-step testing scenarios to verify the component fixes for:
1. Components not disappearing during database updates
2. Component pricing only charging for quantities beyond minimum

---

## Test 1: Database Sync Reliability

### Objective
Verify that components don't disappear when database sync fails or is interrupted.

### Prerequisites
- Have some products with components configured
- Know your API endpoint

### Test Steps

#### Test 1.1: Normal Sync
1. Go to Settings
2. Trigger a data sync (Update Data button)
3. Wait for sync to complete
4. Verify all components are still present
5. ✅ **Expected:** Components sync successfully and remain in database

#### Test 1.2: Failed Sync (Network Interruption)
1. Start a data sync
2. Immediately disconnect network/WiFi during sync
3. Wait for sync to fail with error message
4. Check if products still have their components
5. ✅ **Expected:** Old components remain intact (transaction rollback worked)

#### Test 1.3: Server Error During Sync
1. Temporarily make API endpoint return error (if possible)
2. Trigger a data sync
3. Wait for error
4. Verify components still exist
5. ✅ **Expected:** Old data remains, no partial updates

---

## Test 2: Component Pricing Logic

### Objective
Verify that components only charge for quantities beyond the minimum (default) quantity.

### Prerequisites
Set up test products with components that have different minQuantity values:

**Example Product Setup:**
- Product: "Burger" (€10.00)
  - Component: "Cheese" (€2.00, minQty: 1, maxQty: 3)
  - Component: "Bacon" (€3.00, minQty: 0, maxQty: 3)
  - Component: "Lettuce" (€0.50, minQty: 1, maxQty: 2)

### Test Scenarios

#### Test 2.1: Component at Minimum Quantity (No Charge)
**Component:** Cheese (minQty: 1, price: €2.00)

1. Add Burger to cart
2. In modification dialog, keep Cheese at quantity = 1 (minimum)
3. Confirm order
4. ✅ **Expected Total:** €10.00 (no extra charge for 1 cheese)
5. **Calculation:** Base €10 + €0 (1 cheese is default) = €10.00

#### Test 2.2: Component Above Minimum Quantity (Charge for Extras)
**Component:** Cheese (minQty: 1, price: €2.00)

1. Add Burger to cart
2. In modification dialog, increase Cheese to quantity = 3
3. Confirm order
4. ✅ **Expected Total:** €14.00 (charge for 2 extra cheese)
5. **Calculation:** Base €10 + €4 (2 extra × €2) = €14.00

#### Test 2.3: Optional Component at Zero (No Charge)
**Component:** Bacon (minQty: 0, price: €3.00)

1. Add Burger to cart
2. In modification dialog, keep Bacon at quantity = 0
3. Confirm order
4. ✅ **Expected Total:** €10.00 (no bacon selected)
5. **Calculation:** Base €10 + €0 (no bacon) = €10.00

#### Test 2.4: Optional Component Added (Full Charge)
**Component:** Bacon (minQty: 0, price: €3.00)

1. Add Burger to cart
2. In modification dialog, increase Bacon to quantity = 2
3. Confirm order
4. ✅ **Expected Total:** €16.00 (charge for 2 bacon)
5. **Calculation:** Base €10 + €6 (2 × €3, all chargeable since min is 0) = €16.00

#### Test 2.5: Multiple Components Mix
**Components:**
- Cheese at 2 (min: 1, price: €2.00) → charge 1 extra = €2.00
- Bacon at 1 (min: 0, price: €3.00) → charge all = €3.00
- Lettuce at 1 (min: 1, price: €0.50) → charge 0 = €0.00

1. Add Burger to cart
2. Set components as above
3. Confirm order
4. ✅ **Expected Total:** €15.00
5. **Calculation:** Base €10 + €2 (1 extra cheese) + €3 (1 bacon) + €0 (default lettuce) = €15.00

#### Test 2.6: Component Quantities at Maximum
**Component:** Cheese (minQty: 1, price: €2.00, maxQty: 3)

1. Add Burger to cart
2. Increase Cheese to maximum (3)
3. Confirm order
4. ✅ **Expected Total:** €14.00 (charge for 2 extras)
5. **Calculation:** Base €10 + €4 (2 extra × €2) = €14.00

---

## Test 3: Receipt/Ticket Display

### Objective
Verify that components display correctly on receipts and tickets.

### Test Steps

1. Create an order with components at various quantities
2. Generate a ticket/receipt
3. Verify component display:
   - ✅ Component names appear
   - ✅ Component quantities are correct (full quantity ordered, not just extras)
   - ✅ Component prices reflect only chargeable amounts
   - ✅ Total calculations are accurate

**Example Expected Receipt:**
```
Burger                           €10.00
  + Cheese x2                     €2.00
  + Bacon x1                      €3.00
  + Lettuce x1                    €0.00
                        _______________
Subtotal:                        €15.00
```

---

## Test 4: Edge Cases

### Test 4.1: All Components at Minimum
1. Add product with multiple required components
2. Keep all at their minimum quantities
3. ✅ **Expected:** No extra charges, just base product price

### Test 4.2: Modify Existing Order
1. Create order with components
2. Edit the order
3. Change component quantities
4. ✅ **Expected:** Pricing updates correctly based on new quantities

### Test 4.3: Required Component
**Component:** Cheese (required, minQty: 1)

1. Try to set quantity below minimum
2. ✅ **Expected:** Cannot reduce below minimum
3. Set to minimum
4. ✅ **Expected:** No extra charge

---

## Verification Checklist

### Database Sync
- [ ] Normal sync completes successfully
- [ ] Failed sync doesn't lose component data
- [ ] Components persist across multiple syncs
- [ ] Transaction rollback works on error

### Component Pricing
- [ ] Components at minimum quantity = €0 extra
- [ ] Components above minimum charge only for extras
- [ ] Optional components (min=0) charge full amount
- [ ] Multiple components calculate correctly together
- [ ] Price display in cart shows correct total
- [ ] Price display in modification dialog shows correct total

### Display & Receipts
- [ ] Components show correct quantities on receipt
- [ ] Component prices show on receipt (only for extras)
- [ ] Total calculations match expected values
- [ ] Component totals display correctly in order summary

---

## Common Issues to Watch For

1. **Component total showing wrong value**
   - Check if minimum quantity is being considered
   - Verify calculation: (quantity - minQuantity) × price

2. **Components disappearing**
   - Check database sync logs
   - Verify transaction completed
   - Check for API errors

3. **Receipt showing wrong prices**
   - Verify stored price in database (OrderProductComponents table)
   - Check effectivePricePerUnit calculation in modification dialog

---

## Database Queries for Debugging

```sql
-- Check component configuration for a product
SELECT pc.*, c.name, c.price, pc.minQuantity, pc.maxQuantity
FROM product_components pc
JOIN components c ON c.id = pc.componentId
WHERE pc.productId = <PRODUCT_ID>;

-- Check stored component prices in an order
SELECT opc.*, c.name, opc.quantity, opc.price
FROM order_product_components opc
JOIN components c ON c.id = opc.componentId
WHERE opc.orderProductId = <ORDER_PRODUCT_ID>;

-- Verify component total calculation
SELECT 
  opc.componentId,
  c.name,
  opc.quantity,
  opc.price as stored_price_per_unit,
  (opc.price * opc.quantity) as component_total
FROM order_product_components opc
JOIN components c ON c.id = opc.componentId
WHERE opc.orderProductId = <ORDER_PRODUCT_ID>;
```

---

## Success Criteria

All tests pass with:
- ✅ Components never disappear during sync operations
- ✅ Default component quantities (at minimum) don't add cost
- ✅ Extra quantities (above minimum) are charged correctly
- ✅ Receipts and tickets display accurate information
- ✅ Order totals match expected calculations

