# HTTP Server API Documentation

## Overview
The POS application includes an embedded HTTP server for KDS (Kitchen Display System) integration and external communication.

## Configuration
Configure the server in **Settings > Server Settings**:
- **Port**: Default is 8080
- **Password**: Optional authentication password
- **Auto-start**: Enable to start server automatically on app launch

## Authentication
If a password is configured, all requests (except `/health`) must include the `X-Server-Password` header:
```
X-Server-Password: your-password-here
```

## Endpoints

### Health Check
```
GET /health
```
Returns server status and timestamp.

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2026-02-23T10:00:00.000Z",
  "port": 8080
}
```

---

### Get Orders
```
GET /orders/?since=date&after_id=int&station=string
```
Retrieve orders with optional filters.

**Query Parameters:**
- `since` (optional): ISO 8601 date string - get orders created after this date
- `after_id` (optional): Integer - get orders with ID greater than this
- `station` (optional): String - filter by station name

**Response:**
```json
{
  "orders": [
    {
      "id": 123,
      "code": "ORD-001",
      "status": "PENDING",
      "type": "DINE_IN",
      "priority": "NORMAL",
      "persons": 2,
      "date": "2026-02-23T10:00:00.000Z",
      "tableId": 5,
      "tableName": "Table 5",
      "clientId": null,
      "clientName": null,
      "note": null,
      "products": [
        {
          "id": 456,
          "productId": 10,
          "productName": "Burger",
          "quantity": 2,
          "unitaryPrice": 12.50,
          "state": "PENDING",
          "stationId": 1,
          "stationName": "Kitchen",
          "components": [
            {
              "componentId": 20,
              "componentName": "Extra Cheese",
              "quantity": 1,
              "isSpecial": false,
              "extraPrice": 1.50
            }
          ],
          "note": "No onions",
          "tvaAmount": 2.50,
          "discountAmount": 0.00
        }
      ],
      "createdAt": "2026-02-23T10:00:00.000Z",
      "updatedAt": "2026-02-23T10:00:00.000Z"
    }
  ],
  "count": 1
}
```

---

### Create Order
```
POST /orders/
Content-Type: application/json
```
Create a new order.

**Request Body:**
```json
{
  "code": "ORD-002",
  "status": "PENDING",
  "type": "TAKE_AWAY",
  "priority": "HIGH",
  "persons": 1,
  "date": "2026-02-23T11:00:00.000Z",
  "note": "Urgent order",
  "products": [
    {
      "productId": 15,
      "quantity": 1,
      "unitaryPrice": 8.50,
      "state": "PENDING",
      "note": null,
      "components": []
    }
  ]
}
```

**Response:**
```json
{
  "id": 124,
  "code": "ORD-002"
}
```

---

### Update Order (Full)
```
PUT /orders/{code}
Content-Type: application/json
```
Update order details.

**Request Body:**
```json
{
  "status": "IN_PROGRESS",
  "type": "DINE_IN",
  "priority": "NORMAL",
  "persons": 2,
  "note": "Updated note"
}
```

**Response:**
```json
{
  "message": "Order updated",
  "code": "ORD-001"
}
```

---

### Update Order Status (Quick)
```
PUT /orders/{code}?status=IN_PROGRESS
```
Quickly update order status without request body.

**Response:**
```json
{
  "message": "Order status updated",
  "code": "ORD-001"
}
```

**Valid statuses:** `PENDING`, `ON_HOLD`, `IN_PROGRESS`, `READY`, `DELIVERED`, `COMPLETED`, `CANCELLED`

---

### Update Product Status
```
PUT /orders/products/{id}?status=IN_PROGRESS
```
Update the status of a specific product in an order.

**Response:**
```json
{
  "message": "Product status updated",
  "id": 456
}
```

**Valid statuses:** `PENDING`, `IN_PROGRESS`, `READY`, `SERVED`, `CANCELLED`

---

## CORS
The server supports CORS with the following headers:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS`
- `Access-Control-Allow-Headers: Origin, Content-Type, Accept, X-Server-Password`

## Error Responses

### 400 Bad Request
```json
{
  "error": "Invalid date format for \"since\" parameter"
}
```

### 403 Forbidden
```json
{
  "error": "Invalid or missing server password"
}
```

### 404 Not Found
```json
{
  "error": "Order not found"
}
```

### 500 Internal Server Error
```json
{
  "error": "Internal server error",
  "details": "Error description"
}
```

## Usage Examples

### cURL Examples

#### Get all orders:
```bash
curl -H "X-Server-Password: mypassword" http://localhost:8080/orders/
```

#### Get orders since date:
```bash
curl -H "X-Server-Password: mypassword" \
  "http://localhost:8080/orders/?since=2026-02-23T00:00:00Z"
```

#### Filter by station:
```bash
curl -H "X-Server-Password: mypassword" \
  "http://localhost:8080/orders/?station=Kitchen"
```

#### Update order status:
```bash
curl -X PUT \
  -H "X-Server-Password: mypassword" \
  "http://localhost:8080/orders/ORD-001?status=IN_PROGRESS"
```

#### Create order:
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-Server-Password: mypassword" \
  -d '{
    "code": "ORD-003",
    "status": "PENDING",
    "type": "DINE_IN",
    "priority": "NORMAL",
    "persons": 2,
    "products": [
      {
        "productId": 10,
        "quantity": 2,
        "unitaryPrice": 12.50,
        "state": "PENDING"
      }
    ]
  }' \
  http://localhost:8080/orders/
```

### JavaScript/Fetch Example

```javascript
// Get orders with authentication
fetch('http://localhost:8080/orders/', {
  headers: {
    'X-Server-Password': 'mypassword'
  }
})
  .then(response => response.json())
  .then(data => console.log(data));

// Update order status
fetch('http://localhost:8080/orders/ORD-001?status=IN_PROGRESS', {
  method: 'PUT',
  headers: {
    'X-Server-Password': 'mypassword'
  }
})
  .then(response => response.json())
  .then(data => console.log(data));
```

## Integration with KDS

The server is designed to integrate with Kitchen Display Systems (KDS):

1. **Polling**: KDS can poll `/orders/?since=LAST_CHECK&station=Kitchen` every few seconds
2. **Real-time Updates**: Use WebSocket or SSE (future enhancement)
3. **Status Updates**: KDS updates product/order status as items are prepared
4. **Station Filtering**: Only show orders relevant to each station

## Security Considerations

1. **Password Protection**: Always set a strong password in production
2. **Network Access**: Server binds to `0.0.0.0` - ensure firewall rules are configured
3. **HTTPS**: Consider using a reverse proxy (nginx, Apache) for HTTPS in production
4. **Rate Limiting**: Implement at network level if needed

## Troubleshooting

### Server won't start
- Check if port is already in use
- Verify port is not restricted (< 1024 requires admin on some systems)
- Check firewall settings

### Connection refused
- Ensure server is running (check Settings > Server Settings)
- Verify correct IP address and port
- Check network connectivity

### Authentication fails
- Verify password is correctly configured
- Check `X-Server-Password` header is being sent
- Password is case-sensitive

