# Quick Start Guide - HTTP Server

## Setup (First Time)

1. **Open Settings**
   - Click dropdown menu in top-right
   - Select "Settings"

2. **Configure Server**
   - Navigate to "Server Settings" tab
   - Set port (default: 8080)
   - Set password (optional but recommended)
   - Enable "Auto-Start Server" if desired

3. **Start Server**
   - Click "Start Server" button
   - Verify status shows "Server Running"
   - Note the server URL shown

## Quick Test

```bash
# Health check (no password required)
curl http://localhost:8080/health

# Get all orders (with password)
curl -H "X-Server-Password: yourpassword" http://localhost:8080/orders/
```

## Common Use Cases

### 1. KDS Integration

Poll for new orders every 5 seconds:
```javascript
setInterval(async () => {
  const response = await fetch(
    'http://YOUR_POS_IP:8080/orders/?station=Kitchen&since=' + lastCheck,
    { headers: { 'X-Server-Password': 'yourpassword' } }
  );
  const data = await response.json();
  // Display new orders
  lastCheck = new Date().toISOString();
}, 5000);
```

### 2. Update Order Status
```bash
curl -X PUT -H "X-Server-Password: yourpassword" \
  "http://localhost:8080/orders/ORD-001?status=IN_PROGRESS"
```

### 3. Update Product Status (when item ready)
```bash
curl -X PUT -H "X-Server-Password: yourpassword" \
  "http://localhost:8080/orders/products/456?status=READY"
```

### 4. Create Order from External System
```bash
curl -X POST -H "Content-Type: application/json" \
  -H "X-Server-Password: yourpassword" \
  -d '{
    "code": "ORD-NEW",
    "status": "PENDING",
    "type": "DINE_IN",
    "priority": 0,
    "persons": 2,
    "products": [
      {
        "productId": 10,
        "quantity": 1,
        "unitaryPrice": 12.50,
        "state": "PENDING"
      }
    ]
  }' \
  http://localhost:8080/orders/
```

## Order Statuses
- `PENDING` - New order, not started
- `ON_HOLD` - Paused/waiting
- `IN_PROGRESS` - Being prepared
- `READY` - Ready for pickup/serving
- `DELIVERED` - Delivered to customer
- `COMPLETED` - Fully complete
- `CANCELLED` - Cancelled

## Product Statuses
- `PENDING` - Not started
- `IN_PROGRESS` - Being prepared
- `READY` - Ready to serve
- `SERVED` - Served to customer
- `CANCELLED` - Cancelled

## Troubleshooting

### Can't connect from another device
1. Get POS IP address: `ip addr` or `ipconfig`
2. Replace `localhost` with actual IP
3. Check firewall allows port 8080
4. Ensure both devices on same network

### Authentication fails
- Password is case-sensitive
- Must send as `X-Server-Password` header
- Check password in Settings matches

### Server won't start
- Check if port already in use
- Try different port in Settings
- Check app logs for error details

## Best Practices

1. **Security**
   - Always use a strong password in production
   - Use HTTPS reverse proxy (nginx/Apache) for public access
   - Restrict network access with firewall rules

2. **Performance**
   - Poll KDS every 5-10 seconds (not faster)
   - Use `since` parameter to get only new orders
   - Filter by station to reduce data

3. **Error Handling**
   - Check HTTP status codes
   - Handle network timeouts
   - Retry failed requests with exponential backoff

## Getting Help

- See `SERVER_API_DOCUMENTATION.md` for complete API reference
- See `SERVER_IMPLEMENTATION_SUMMARY.md` for technical details
- Check app logs for error messages

