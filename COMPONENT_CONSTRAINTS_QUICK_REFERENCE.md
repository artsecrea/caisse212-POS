# Quick Reference: Component Constraints

## For Developers

### Adding a Required Component

In the database (or via migration/data generator):

```dart
await database.into(database.productComponents).insert(
  ProductComponentsCompanion.insert(
    productId: 1,              // Product ID
    componentId: 5,            // Component ID (e.g., Cheese)
    defaultPrice: const Value(0.0),
    isRequired: const Value(true),     // ✅ Make it required
    minQuantity: const Value(1),       // Must have at least 1
    maxQuantity: const Value(3),       // Can have up to 3
  ),
);
```

### Configuration Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `isRequired` | bool | false | Must be selected |
| `minQuantity` | int | 0 | Minimum quantity |
| `maxQuantity` | int | 10 | Maximum quantity |
| `defaultPrice` | double | 0.0 | Override component price |

---

## For Users

### Understanding the Dialog

**Orange "REQUIRED" Badge:**
- This component MUST be selected
- Cannot be removed completely
- Starts at minimum quantity

**"Min: X, Max: Y" Text:**
- Shows allowed quantity range
- Example: "Min: 1, Max: 3" means you must have 1-3 portions

**Button States:**
- **Enabled (colored):** Can press
- **Disabled (gray):** Cannot press (at limit)

### Examples

**Burger with Required Cheese:**
```
Cheese [REQUIRED]
Min: 1, Max: 3
[-] [1] [+]
```
- `-` button: Disabled (already at minimum)
- `+` button: Enabled (can add more)
- Current: 1 cheese (required minimum)

**Adding Extra Cheese:**
```
Cheese [REQUIRED]
Min: 1, Max: 3
[-] [2] [+]
```
- `-` button: Enabled (can reduce to 1)
- `+` button: Enabled (can increase to 3)
- Current: 2 cheese (above minimum, will be saved)

**At Maximum:**
```
Cheese [REQUIRED]
Min: 1, Max: 3
[-] [3] [+]
```
- `-` button: Enabled (can reduce)
- `+` button: Disabled (at maximum)
- Current: 3 cheese (maximum reached)

---

## Behavior Summary

### Single Click/Tap
- **Product with required components** → Opens dialog
- **Product without required components** → Quick-add to order

### Long Press
- **Any product** → Opens dialog for customization

### Save Behavior
- **Required at minimum:** Shown in dialog, NOT saved in order
- **Above minimum:** Saved in order
- **Optional at 0:** Not shown, not saved
- **Optional > 0:** Saved in order

---

## Common Scenarios

### Q: Why can't I remove this component?
**A:** It's marked as REQUIRED. You must have at least the minimum quantity.

### Q: Why is the + button disabled?
**A:** You've reached the maximum allowed quantity.

### Q: Does the required component add extra cost?
**A:** Only if you select MORE than the minimum quantity.

### Q: Can I skip required components?
**A:** No. The dialog validates before allowing you to save.

---

## Error Messages

| Message | Meaning | Solution |
|---------|---------|----------|
| "[Component] is required (minimum: X)" | Haven't met minimum | Add more of this component |
| "Quantity must be at least 1" | Product quantity too low | Increase product quantity |

---

*Quick Reference Guide - Component Constraints*

