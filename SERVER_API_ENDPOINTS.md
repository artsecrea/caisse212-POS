# Server API Endpoints - Quick Reference

## Required Endpoints for Offline Sync

### DELETE Operations

#### Delete Order
```
DELETE /api/pos/orders/{id}
```
**Response:** 204 No Content or 200 OK

**Example:**
```bash
curl -X DELETE "https://api.example.com/api/pos/orders/123" \
  -H "Authorization: Bearer {token}" \
  -H "X-POS-Name: {pos_name}"
```

---

#### Delete Ticket
```
DELETE /api/pos/tickets/{id}
```
**Response:** 204 No Content or 200 OK

**Example:**
```bash
curl -X DELETE "https://api.example.com/api/pos/tickets/456" \
  -H "Authorization: Bearer {token}" \
  -H "X-POS-Name: {pos_name}"
```

---

#### Delete Order Product
```
DELETE /api/pos/order-products/{id}
```
**Response:** 204 No Content or 200 OK

**Note:** This should also recalculate the ticket total if the product belongs to a ticket.

**Example:**
```bash
curl -X DELETE "https://api.example.com/api/pos/order-products/789" \
  -H "Authorization: Bearer {token}" \
  -H "X-POS-Name: {pos_name}"
```

---

### UPDATE Operations

#### Update Order
```
PUT /api/pos/orders/{id}
```

**Request Body:**
```json
{
  "status": "COMPLETED",
  "totalAmount": 125.50,
  "discountPercentage": 10.0
}
```

**Response:** 200 OK
```json
{
  "id": 123,
  "status": "COMPLETED",
  "updatedAt": "2026-01-20T10:30:00Z"
}
```

**Example:**
```bash
curl -X PUT "https://api.example.com/api/pos/orders/123" \
  -H "Authorization: Bearer {token}" \
  -H "X-POS-Name: {pos_name}" \
  -H "Content-Type: application/json" \
  -d '{"status": "COMPLETED", "totalAmount": 125.50}'
```

---

#### Update Ticket
```
PUT /api/pos/tickets/{id}
```

**Request Body:**
```json
{
  "amount": 45.75,
  "status": "PAID"
}
```

**Response:** 200 OK
```json
{
  "id": 456,
  "amount": 45.75,
  "status": "PAID",
  "updatedAt": "2026-01-20T10:30:00Z"
}
```

**Example:**
```bash
curl -X PUT "https://api.example.com/api/pos/tickets/456" \
  -H "Authorization: Bearer {token}" \
  -H "X-POS-Name: {pos_name}" \
  -H "Content-Type: application/json" \
  -d '{"amount": 45.75}'
```

---

#### Update Order Product
```
PUT /api/pos/order-products/{id}
```

**Request Body:**
```json
{
  "quantity": 3,
  "unitaryPrice": 15.25,
  "state": "SERVED"
}
```

**Response:** 200 OK
```json
{
  "id": 789,
  "quantity": 3,
  "unitaryPrice": 15.25,
  "state": "SERVED",
  "updatedAt": "2026-01-20T10:30:00Z"
}
```

---

### Health Check (Already Exists)
```
GET /api/health
```
**Response:** 200 OK
```json
{
  "status": "ok"
}
```

---

## Common Headers

All requests include:
- `Authorization: Bearer {access_token}`
- `X-POS-Name: {pos_name}`
- `X-Tenant-ID: {tenant_id}`
- `Content-Type: application/json` (for PUT requests)

---

## Error Responses

### 401 Unauthorized
```json
{
  "error": "Unauthorized",
  "message": "Invalid or expired token"
}
```

### 404 Not Found
```json
{
  "error": "Not Found",
  "message": "Order with ID 123 not found"
}
```

### 400 Bad Request
```json
{
  "error": "Bad Request",
  "message": "Invalid data format",
  "details": {
    "amount": "must be a positive number"
  }
}
```

### 500 Internal Server Error
```json
{
  "error": "Internal Server Error",
  "message": "An unexpected error occurred"
}
```

---

## Business Logic Notes

### When Deleting Order Product:
1. Delete the order product record
2. If product belongs to a ticket:
   - Recalculate ticket total
   - If it was the last product, delete the ticket
3. If ticket was the last unpaid ticket:
   - Check if order should be marked complete

### When Updating Ticket Amount:
1. Validate the new amount
2. Update ticket record
3. Optionally: validate against sum of products
4. Update order total if needed

### When Deleting Ticket:
1. Check if any products still reference it
2. Set products' `ticketId` to null or handle appropriately
3. Delete ticket record
4. Recalculate order status

---

## Testing with cURL

### Complete Example Flow:

```bash
# 1. Login (get token)
TOKEN=$(curl -X POST "https://api.example.com/api/pos/login" \
  -H "Content-Type: application/json" \
  -H "X-POS-Name: MAIN_POS" \
  -d '{"username":"user","password":"pass"}' \
  | jq -r '.token')

# 2. Delete an order product
curl -X DELETE "https://api.example.com/api/pos/order-products/789" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-POS-Name: MAIN_POS"

# 3. Update a ticket
curl -X PUT "https://api.example.com/api/pos/tickets/456" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-POS-Name: MAIN_POS" \
  -H "Content-Type: application/json" \
  -d '{"amount": 45.75}'

# 4. Delete a ticket
curl -X DELETE "https://api.example.com/api/pos/tickets/456" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-POS-Name: MAIN_POS"
```

---

## Implementation Checklist

- [ ] Implement DELETE /api/pos/orders/{id}
- [ ] Implement DELETE /api/pos/tickets/{id}
- [ ] Implement DELETE /api/pos/order-products/{id}
- [ ] Implement PUT /api/pos/orders/{id}
- [ ] Implement PUT /api/pos/tickets/{id}
- [ ] Implement PUT /api/pos/order-products/{id}
- [ ] Add authorization checks
- [ ] Add tenant isolation
- [ ] Add cascade delete logic
- [ ] Add amount recalculation logic
- [ ] Add validation
- [ ] Add error handling
- [ ] Add logging
- [ ] Add tests

