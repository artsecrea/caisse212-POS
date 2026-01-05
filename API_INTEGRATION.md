# API Integration Documentation

## Server Connection Setup

The POS app connects to a backend server to fetch product data, user information, and sync local data.

## Authentication Flow

### 1. Server Login (Tenant Login Screen)

**Endpoint:** `POST /auth/pos-login`

**Headers:**
```
X-POS-Name: POS-1
Content-Type: application/json
```

**Request Body:**
```json
{
  "username": "admin",
  "password": "admin123"
}
```

**Response:**
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "tenantId": "tenant-001",
  "user": {
    "id": 1,
    "username": "admin",
    "firstName": "Admin",
    "lastName": "User",
    "type": "admin"
  }
}
```

### 2. All Subsequent Requests

**Headers:**
```
Authorization: Bearer <accessToken>
X-POS-Name: POS-1
X-Tenant-ID: tenant-001
Content-Type: application/json
```

---

## Data Fetch Endpoints (Server → POS)

### GET /pos/users
```json
[
  {
    "id": 1,
    "username": "admin",
    "password": "admin123",
    "firstName": "Admin",
    "lastName": "User",
    "type": "admin",
    "imageUrl": null,
    "permissions": "all,users,orders,settings"
  },
  {
    "id": 2,
    "username": "cashier",
    "password": "cashier123",
    "firstName": "John",
    "lastName": "Doe",
    "type": "cashier",
    "imageUrl": "https://example.com/images/john.jpg",
    "permissions": "orders,tickets"
  }
]
```

### GET /pos/categories
```json
[
  {
    "id": 1,
    "name": "Burgers",
    "imageUrl": "https://example.com/images/burgers.jpg",
    "description": "Delicious burgers",
    "displayOrder": 1,
    "isActive": true
  },
  {
    "id": 2,
    "name": "Pizza",
    "imageUrl": "https://example.com/images/pizza.jpg",
    "description": "Fresh pizza",
    "displayOrder": 2,
    "isActive": true
  }
]
```

### GET /pos/products
```json
[
  {
    "id": 1,
    "name": "Classic Burger",
    "barcode": "123456789",
    "imageUrl": "https://example.com/images/classic-burger.jpg",
    "description": "Our signature burger",
    "price": 8.50,
    "uom": "unit",
    "categoryId": 1,
    "stationId": 2,
    "tvaAmount": 1.70,
    "discountAmount": 0.0,
    "finalPrice": 8.50,
    "isActive": true
  },
  {
    "id": 2,
    "name": "Cheese Burger",
    "barcode": "123456790",
    "imageUrl": "https://example.com/images/cheese-burger.jpg",
    "description": "Burger with extra cheese",
    "price": 10.50,
    "uom": "unit",
    "categoryId": 1,
    "stationId": 2,
    "tvaAmount": 2.10,
    "discountAmount": 1.00,
    "finalPrice": 10.50,
    "isActive": true
  }
]
```

### GET /pos/component-groups
```json
[
  {
    "id": 1,
    "name": "Toppings",
    "description": "Add extra toppings",
    "displayOrder": 1
  },
  {
    "id": 2,
    "name": "Sauces",
    "description": "Special sauces",
    "displayOrder": 2
  }
]
```

### GET /pos/components
```json
[
  {
    "id": 1,
    "name": "Extra Cheese",
    "price": 1.50,
    "componentGroupId": 1
  },
  {
    "id": 2,
    "name": "Bacon",
    "price": 2.00,
    "componentGroupId": 1
  },
  {
    "id": 7,
    "name": "Ketchup",
    "price": 0.00,
    "componentGroupId": 2
  }
]
```

### GET /pos/product-components
```json
[
  {
    "productId": 1,
    "componentId": 1,
    "defaultPrice": 0.0,
    "isRequired": false
  },
  {
    "productId": 1,
    "componentId": 2,
    "defaultPrice": 0.0,
    "isRequired": false
  }
]
```

### GET /pos/stations
```json
[
  {
    "id": 1,
    "name": "all",
    "description": "Default station"
  },
  {
    "id": 2,
    "name": "burgers",
    "description": "Burger station"
  }
]
```

### GET /pos/areas
```json
[
  {
    "id": 1,
    "name": "Main Hall",
    "description": "Main dining area"
  },
  {
    "id": 2,
    "name": "Terrace",
    "description": "Outdoor seating"
  }
]
```

### GET /pos/tables
```json
[
  {
    "id": 1,
    "name": "Table 1",
    "capacity": 4,
    "areaId": 1
  },
  {
    "id": 2,
    "name": "Table 2",
    "capacity": 6,
    "areaId": 1
  }
]
```

### GET /pos/commercials
```json
[
  {
    "id": 1,
    "firstName": "Mohamed",
    "lastName": "Alami",
    "cin": "123456789"
  }
]
```

### GET /pos/customers
```json
[
  {
    "id": 1,
    "firstName": "Ahmed",
    "lastName": "Benali",
    "phone": "0555123456",
    "email": "ahmed@example.com"
  }
]
```

---

## Data Sync Endpoints (POS → Server)

### POST /pos/sync/orders

**Request Body:**
```json
{
  "orders": [
    {
      "id": 1,
      "code": "ORD-20260102-001",
      "status": "DELIVERED",
      "type": "DINE_IN",
      "priority": 0,
      "coupon": null,
      "persons": 2,
      "tableId": 1,
      "clientId": 1,
      "commercialId": null,
      "discountPercentage": 10.0,
      "note": "No onions",
      "createdAt": "2026-01-02T10:30:00.000Z",
      "updatedAt": "2026-01-02T11:00:00.000Z"
    }
  ]
}
```

### POST /pos/sync/tickets

**Request Body:**
```json
{
  "tickets": [
    {
      "id": 1,
      "num": "0001",
      "orderId": 1,
      "sessionId": 1,
      "paymentMethod": "CASH",
      "amount": 25.50,
      "isPaid": true,
      "printCount": 1,
      "date": "2026-01-02T11:00:00.000Z",
      "createdAt": "2026-01-02T11:00:00.000Z"
    }
  ]
}
```

### POST /pos/sync/sessions

**Request Body:**
```json
{
  "sessions": [
    {
      "id": 1,
      "cashierId": 2,
      "moneyAtStart": 100.00,
      "moneyAtEnd": 350.00,
      "status": "ended",
      "startedAt": "2026-01-02T08:00:00.000Z",
      "endedAt": "2026-01-02T16:00:00.000Z",
      "pausedAt": null
    }
  ]
}
```

### POST /pos/sync/customers

**Request Body:**
```json
{
  "customers": [
    {
      "id": 100,
      "firstName": "New",
      "lastName": "Customer",
      "phone": "0555999888",
      "email": "new@example.com"
    }
  ]
}
```

---

## Health Check

### GET /health

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2026-01-02T12:00:00.000Z"
}
```

---

## Data Sync Order

When syncing data from server, the app fetches data in this order to respect foreign key constraints:

1. **Users** - No dependencies
2. **Categories** - No dependencies
3. **Stations** - No dependencies
4. **Products** - Depends on: categories, stations
5. **Component Groups** - No dependencies
6. **Components** - Depends on: component groups
7. **Product Components** - Depends on: products, components
8. **Areas** - No dependencies
9. **Tables** - Depends on: areas
10. **Commercials** - No dependencies
11. **Customers** - No dependencies

---

## Demo Mode

When using demo mode, the app generates sample data locally without connecting to any server. The sample data generator creates:

- 2 users (admin, cashier)
- 3 areas (Main Hall, Terrace, VIP Section)
- 5 categories (Burgers, Pizza, Drinks, Desserts, Salads)
- 18 products
- 4 component groups
- 16 components
- Product-component relationships
- 10 tables
- 3 customers
- 2 commercials
- 3 stations

---

## Storage

The following data is stored in SharedPreferences:

| Key | Description |
|-----|-------------|
| `server_access_token` | JWT access token for API calls |
| `pos_name` | POS device name (sent in X-POS-Name header) |
| `api_base_url` | Server API base URL |
| `tenant_id` | Tenant identifier |
| `is_demo_mode` | Boolean flag for demo mode |
| `default_order_status` | Default order status when creating new orders (PENDING, ONHOLD, PREPARING, COMPLETED) |

---

## Sync Tracking (isSynced Property)

The following tables have an `isSynced` boolean field to track synchronization status:

| Table | Sync Condition |
|-------|----------------|
| `orders` | Only orders with status `COMPLETED` are synced |
| `tickets` | Only tickets belonging to synced orders are synced |
| `cash_sessions` | Only sessions with status `ended` are synced |
| `customers` | New customers created locally are synced |

### Sync Flow:

1. **Data from server** → `isSynced = true` (already in sync)
2. **Data created locally** → `isSynced = false` (needs to be synced)
3. **After successful upload** → `isSynced = true` (marked as synced)

### Order Sync Logic:

1. Orders must have `status = 'COMPLETED'` to be eligible for sync
2. Tickets are only synced after their parent order is synced
3. This ensures data integrity on the server

### Default Order Status Setting:

- Can be configured in Settings
- Options: `ONHOLD`, `PENDING`, `PREPARING`, `COMPLETED`
- Default is `PENDING`
- Orders set to `COMPLETED` by default will sync immediately after creation

---

## Error Handling

All API calls should handle:

- **401 Unauthorized**: Token expired, redirect to login
- **404 Not Found**: Resource doesn't exist
- **500 Server Error**: Display error message to user
- **Network Error**: Show offline indicator, allow offline operations

