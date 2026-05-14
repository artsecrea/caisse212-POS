import 'package:bcrypt/bcrypt.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:drift/drift.dart';

/// Sample data generator for testing the POS app
/// Run this after the first launch to populate the database
class SampleDataGenerator {
  final AppDatabase database;

  SampleDataGenerator(this.database);

  Future<void> generateAll() async {
    print('Generating sample data...');

    await _generateUsers();
    await _generateAreas();
    await _generateWaiters();
    await _generateCategories();
    await _generateComponentGroups();
    await _generateStations();
    await _generateComponents();
    await _generateProducts();
    await _generateProductComponents();
    await _generateTables();
    await _generateCustomers();
    await _generateCommercials();

    print('Sample data generated successfully!');
  }

  Future<void> _generateUsers() async {
    print('Creating users...');
    // Admin user - has all permissions automatically by type
    await database.into(database.users).insert(
      UsersCompanion.insert(
        id: const Value(1),
        username: 'admin',
        password: BCrypt.hashpw("admin123",BCrypt.gensalt()),
        firstName: 'Admin',
        lastName: 'User',
        type: 'admin',
        permissions: const Value('pos:*'), // All permissions
      ),
    );

    // Cashier with full permissions
    await database.into(database.users).insert(
      UsersCompanion.insert(
        id: const Value(2),
        username: 'cashier',
        password: BCrypt.hashpw("cashier123",BCrypt.gensalt()),
        firstName: 'John',
        lastName: 'Doe',
        type: 'cashier',
        permissions: const Value('pos:products:view,pos:orders:view,pos:tickets:create,pos:tickets:view,pos:commercial:set,pos:tables:set,pos:printing'),
      ),
    );

    // Supervisor with extended permissions
    await database.into(database.users).insert(
      UsersCompanion.insert(
        id: const Value(3),
        username: 'supervisor',
        password: 'super123',
        firstName: 'Jane',
        lastName: 'Smith',
        type: 'cashier',
        permissions: const Value('pos:products:view,pos:orders:*,pos:tickets:*,pos:sessions:view,pos:customer:*,pos:commercial:*,pos:tables:*,pos:printing,pos:manualDiscount,pos:reports:view'),
      ),
    );
  }

  Future<void> _generateAreas() async {
    print('Creating areas...');
    final areas = [
      {'id': 1, 'name': 'Main Hall', 'description': 'Main dining area'},
      {'id': 2, 'name': 'Terrace', 'description': 'Outdoor seating'},
      {'id': 3, 'name': 'VIP Section', 'description': 'Private dining'},
    ];

    for (var area in areas) {
      await database.into(database.areas).insert(
        AreasCompanion.insert(
          id: Value(area['id'] as int),
          name: area['name'] as String,
          description: Value(area['description'] as String?),
        ),
      );
    }
  }

  Future<void> _generateWaiters() async {
    print('Creating waiters...');
    final waiters = [
      {'id': 1, 'firstName': 'Ahmed', 'lastName': 'Hassan', 'areaIds': [1, 2]},
      {'id': 2, 'firstName': 'Fatima', 'lastName': 'Zahra', 'areaIds': [3]},
      {'id': 3, 'firstName': 'Mohammed', 'lastName': 'Ali', 'areaIds': []}, // Serves all areas
      {'id': 4, 'firstName': 'Sara', 'lastName': 'Benali', 'areaIds': [1]},
    ];

    for (var waiter in waiters) {
      await database.into(database.waiters).insert(
        WaitersCompanion.insert(
          id: Value(waiter['id'] as int),
          firstName: waiter['firstName'] as String,
          lastName: Value(waiter['lastName'] as String?),
          isActive: const Value(true),
        ),
      );

      // Insert waiter-area assignments
      final areaIds = waiter['areaIds'] as List<int>;
      for (final areaId in areaIds) {
        await database.into(database.waiterAreas).insert(
          WaiterAreasCompanion.insert(
            waiterId: waiter['id'] as int,
            areaId: areaId,
          ),
        );
      }
    }
  }

  Future<void> _generateCategories() async {
    print('Creating categories...');
    final categories = [
      {
        'id': 1,
        'name': 'Burgers',
        'order': 1,
        'imageUrl': 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400'
      },
      {
        'id': 2,
        'name': 'Pizza',
        'order': 2,
        'imageUrl': 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=400'
      },
      {
        'id': 3,
        'name': 'Drinks',
        'order': 3,
        'imageUrl': 'https://images.unsplash.com/photo-1437418747212-8d9709afab22?w=400'
      },
      {
        'id': 4,
        'name': 'Desserts',
        'order': 4,
        'imageUrl': 'https://images.unsplash.com/photo-1488477181946-6428a0291777?w=400'
      },
      {
        'id': 5,
        'name': 'Salads',
        'order': 5,
        'imageUrl': 'https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=400'
      },
    ];

    for (var cat in categories) {
      await database.into(database.categories).insert(
        CategoriesCompanion.insert(
          id: Value(cat['id'] as int),
          name: cat['name'] as String,
          displayOrder: Value(cat['order'] as int),
          imageUrl: Value(cat['imageUrl'] as String?),
        ),
      );
    }
  }

  Future<void> _generateComponentGroups() async {
    print('Creating component groups...');
    final groups = [
      {'id': 1, 'name': 'Toppings', 'order': 1, 'description': 'Add extra toppings'},
      {'id': 2, 'name': 'Sauces', 'order': 2, 'description': 'Special sauces'},
      {'id': 3, 'name': 'Extras', 'order': 3, 'description': 'Additional items'},
      {'id': 4, 'name': 'Sides', 'order': 4, 'description': 'Side dishes'},
    ];

    for (var group in groups) {
      await database.into(database.componentGroups).insert(
        ComponentGroupsCompanion.insert(
          id: Value(group['id'] as int),
          name: group['name'] as String,
          displayOrder: Value(group['order'] as int),
          description: Value(group['description'] as String?),
        ),
      );
    }
  }

  Future<void> _generateComponents() async {
    print('Creating components...');
    final components = [
      // Toppings (group 1)
      {'id': 1, 'name': 'Extra Cheese', 'price': 1.50, 'groupId': 1},
      {'id': 2, 'name': 'Bacon', 'price': 2.00, 'groupId': 1},
      {'id': 3, 'name': 'Mushrooms', 'price': 1.00, 'groupId': 1},
      {'id': 4, 'name': 'Onions', 'price': 0.50, 'groupId': 1},
      {'id': 5, 'name': 'Tomatoes', 'price': 0.50, 'groupId': 1},
      {'id': 6, 'name': 'Lettuce', 'price': 0.50, 'groupId': 1},

      // Sauces (group 2)
      {'id': 7, 'name': 'Ketchup', 'price': 0.00, 'groupId': 2},
      {'id': 8, 'name': 'Mayonnaise', 'price': 0.00, 'groupId': 2},
      {'id': 9, 'name': 'BBQ Sauce', 'price': 0.50, 'groupId': 2},
      {'id': 10, 'name': 'Hot Sauce', 'price': 0.50, 'groupId': 2},

      // Extras (group 3)
      {'id': 11, 'name': 'Egg', 'price': 1.50, 'groupId': 3},
      {'id': 12, 'name': 'Avocado', 'price': 2.00, 'groupId': 3},
      {'id': 13, 'name': 'Jalapeños', 'price': 1.00, 'groupId': 3},

      // Sides (group 4)
      {'id': 14, 'name': 'French Fries', 'price': 3.00, 'groupId': 4},
      {'id': 15, 'name': 'Onion Rings', 'price': 3.50, 'groupId': 4},
      {'id': 16, 'name': 'Coleslaw', 'price': 2.50, 'groupId': 4},
    ];

    for (var comp in components) {
      await database.into(database.components).insert(
        ComponentsCompanion.insert(
          id: Value(comp['id'] as int),
          name: comp['name'] as String,
          price: Value(comp['price'] as double),
          componentGroupId: Value(comp['groupId'] as int),
        ),
      );
    }
  }

  Future<void> _generateProducts() async {
    print('Creating products...');
    final products = [
      // Burgers (category 1)
      {
        'id': 1,
        'name': 'Classic Burger',
        'price': 8.50,
        'categoryId': 1,
        'stationId': 2,
        'barcode': '1000000001',
        'imageUrl': 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=300',
        'discount': 0.0,
        'tva': 1.70
      },
      {
        'id': 2,
        'name': 'Cheese Burger',
        'price': 10.50,
        'categoryId': 1,
        'stationId': 2,
        'barcode': '1000000002',
        'imageUrl': 'https://images.unsplash.com/photo-1550547660-d9450f859349?w=300',
        'discount': 1.00,
        'tva': 2.10
      },
      {
        'id': 3,
        'name': 'Double Burger',
        'price': 12.50,
        'categoryId': 1,
        'stationId': 2,
        'barcode': '1000000003',
        'imageUrl': 'https://images.unsplash.com/photo-1606755962773-d324e0a13086?w=300',
        'discount': 0.0,
        'tva': 2.50
      },
      {
        'id': 4,
        'name': 'Chicken Burger',
        'price': 9.50,
        'categoryId': 1,
        'stationId': 2,
        'barcode': '1000000004',
        'imageUrl': 'https://images.unsplash.com/photo-1562547687-d607c2c218e0?w=300',
        'discount': 0.50,
        'tva': 1.90
      },

      // Pizza (category 2)
      {
        'id': 5,
        'name': 'Margherita',
        'price': 14.00,
        'categoryId': 2,
        'barcode': '2000000001',
        'imageUrl': 'https://images.unsplash.com/photo-1574071318508-1cdbab80d002?w=300',
        'discount': 0.0,
        'tva': 2.80
      },
      {
        'id': 6,
        'name': 'Pepperoni',
        'price': 16.00,
        'categoryId': 2,
        'barcode': '2000000002',
        'imageUrl': 'https://images.unsplash.com/photo-1628840042765-356cda07504e?w=300',
        'discount': 2.00,
        'tva': 3.20
      },
      {
        'id': 7,
        'name': 'Vegetarian',
        'price': 15.00,
        'categoryId': 2,
        'barcode': '2000000003',
        'imageUrl': 'https://images.unsplash.com/photo-1511689660979-10d2b1aada49?w=300',
        'discount': 0.0,
        'tva': 3.00
      },
      {
        'id': 8,
        'name': 'Four Cheese',
        'price': 17.00,
        'categoryId': 2,
        'barcode': '2000000004',
        'imageUrl': 'https://images.unsplash.com/photo-1571066811602-716837d681de?w=300',
        'discount': 1.50,
        'tva': 3.40
      },

      // Drinks (category 3)
      {
        'id': 9,
        'name': 'Coca Cola',
        'price': 2.50,
        'categoryId': 3,
        'barcode': '3000000001',
        'imageUrl': 'https://images.unsplash.com/photo-1554866585-cd94860890b7?w=300',
        'discount': 0.0,

        'tva': 0.50
      },
      {
        'id': 10,
        'name': 'Orange Juice',
        'price': 3.50,
        'categoryId': 3,
        'barcode': '3000000002',
        'imageUrl': 'https://images.unsplash.com/photo-1600271886742-f049cd451bba?w=300',
        'discount': 0.0,
        'tva': 0.70
      },
      {
        'id': 11,
        'name': 'Water',
        'price': 1.50,
        'categoryId': 3,
        'barcode': '3000000003',
        'imageUrl': 'https://images.unsplash.com/photo-1548839140-29a749e1cf4d?w=300',
        'discount': 0.0,
        'tva': 0.30
      },
      {
        'id': 12,
        'name': 'Coffee',
        'price': 3.00,
        'categoryId': 3,
        'barcode': '3000000004',
        'imageUrl': 'https://images.unsplash.com/photo-1509042239860-f550ce710b93?w=300',
        'discount': 0.0,
        'tva': 0.60
      },

      // Desserts (category 4)
      {
        'id': 13,
        'name': 'Ice Cream',
        'price': 4.50,
        'categoryId': 4,
        'barcode': '4000000001',
        'imageUrl': 'https://images.unsplash.com/photo-1563805042-7684c019e1cb?w=300',
        'discount': 0.0,
        'tva': 0.90
      },
      {
        'id': 14,
        'name': 'Cake Slice',
        'price': 5.50,
        'categoryId': 4,
        'barcode': '4000000002',
        'imageUrl': 'https://images.unsplash.com/photo-1578985545062-69928b1d9587?w=300',
        'discount': 0.50,
        'tva': 1.10
      },
      {
        'id': 15,
        'name': 'Brownie',
        'price': 5.00,
        'categoryId': 4,
        'barcode': '4000000003',
        'imageUrl': 'https://images.unsplash.com/photo-1607920591413-4ec007e70023?w=300',
        'discount': 0.0,
        'tva': 1.00
      },

      // Salads (category 5)
      {
        'id': 16,
        'name': 'Caesar Salad',
        'price': 9.00,
        'categoryId': 5,
        'stationId': 3,
        'barcode': '5000000001',
        'imageUrl': 'https://images.unsplash.com/photo-1546793665-c74683f339c1?w=300',
        'discount': 1.0,
        'tva': 1.80
      },
      {
        'id': 17,
        'name': 'Greek Salad',
        'price': 8.00,
        'categoryId': 5,
        'stationId': 3,
        'barcode': '5000000002',
        'imageUrl': 'https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=300',
        'discount': 0.0,
        'tva': 1.60
      },
      {
        'id': 18,
        'name': 'Garden Salad',
        'price': 7.00,
        'categoryId': 5,
        'stationId': 3,
        'barcode': '5000000003',
        'imageUrl': 'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=300',
        'discount': 12.0,
        'tva': 1.40
      },
    ];

    for (var prod in products) {
      final price = prod['price'] as double;
      final discount = prod['discount'] as double;
      final tva = prod['tva'] as double;

      await database.into(database.products).insert(
        ProductsCompanion.insert(
          id: Value(prod['id'] as int),
          name: prod['name'] as String,
          stationId: Value(prod['stationId'] as int? ?? 1),
          barcode: Value(prod['barcode'] as String?),
          price: price - discount + tva,
          finalPrice: price,
          categoryId: Value(prod['categoryId'] as int),
          imageUrl: Value(prod['imageUrl'] as String?),
          discountAmount: Value(discount),
          tvaAmount: Value(tva),
          // Mark first 3 products as plannable (for demo/testing)
          isPlannable: Value((prod['id'] as int) <= 3),
          planDurationMinutes: Value((prod['id'] as int) <= 3 ? 60 : null),
        ),
      );
    }
  }

  Future<void> _generateProductComponents() async {
    print('Linking products to components...');

    // Burgers (products 1-4) can have all toppings, sauces, extras, and sides
    // Make cheese required (component 1) with min 1, max 3
    // Make sauce required (component 6 - Ketchup) with min 1, max 2
    final burgerComponents = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
    for (int productId = 1; productId <= 4; productId++) {
      for (var componentId in burgerComponents) {
        final isRequired = componentId == 1 || componentId == 6; // Cheese or Ketchup required
        final minQty = isRequired ? 1 : 0;
        final maxQty = componentId == 1 ? 3 : (componentId == 6 ? 2 : 5);

        await database.into(database.productComponents).insert(
          ProductComponentsCompanion.insert(
            productId: productId,
            componentId: componentId,
            defaultPrice: const Value(0.0), // Use component's own price
            isRequired: Value(isRequired),
            minQuantity: Value(minQty),
            maxQuantity: Value(maxQty),
          ),
        );
      }
    }

    // Pizzas (products 5-8) can have toppings and some extras
    // Make cheese required (component 1) with min 1, max 4
    final pizzaComponents = [1, 2, 3, 4, 5, 9, 10, 13];
    for (int productId = 5; productId <= 8; productId++) {
      for (var componentId in pizzaComponents) {
        final isRequired = componentId == 1; // Cheese required for pizza
        final minQty = isRequired ? 1 : 0;
        final maxQty = componentId == 1 ? 4 : 3;

        await database.into(database.productComponents).insert(
          ProductComponentsCompanion.insert(
            productId: productId,
            componentId: componentId,
            defaultPrice: const Value(0.0),
            isRequired: Value(isRequired),
            minQuantity: Value(minQty),
            maxQuantity: Value(maxQty),
          ),
        );
      }
    }

    // Drinks (products 9-12) - no modifications

    // Desserts (products 13-15) can have some extras
    final dessertComponents = [9, 11]; // BBQ Sauce, Egg (just as examples)
    for (int productId = 13; productId <= 15; productId++) {
      for (var componentId in dessertComponents) {
        await database.into(database.productComponents).insert(
          ProductComponentsCompanion.insert(
            productId: productId,
            componentId: componentId,
            defaultPrice: const Value(0.0),
            isRequired: const Value(false),
            minQuantity: const Value(0),
            maxQuantity: const Value(3),
          ),
        );
      }
    }

    // Salads (products 16-18) can have toppings and sauces
    final saladComponents = [1, 3, 4, 5, 6, 7, 8, 11, 12];
    for (int productId = 16; productId <= 18; productId++) {
      for (var componentId in saladComponents) {
        await database.into(database.productComponents).insert(
          ProductComponentsCompanion.insert(
            productId: productId,
            componentId: componentId,
            defaultPrice: const Value(0.0),
            isRequired: const Value(false),
            minQuantity: const Value(0),
            maxQuantity: const Value(5),
          ),
        );
      }
    }
  }

  Future<void> _generateTables() async {
    print('Creating tables...');
    final tables = [
      // Main Hall tables
      {'id': 1, 'name': 'Table 1', 'capacity': 4, 'areaId': 1},
      {'id': 2, 'name': 'Table 2', 'capacity': 4, 'areaId': 1},
      {'id': 3, 'name': 'Table 3', 'capacity': 6, 'areaId': 1},
      {'id': 4, 'name': 'Table 4', 'capacity': 2, 'areaId': 1},
      {'id': 5, 'name': 'Table 5', 'capacity': 4, 'areaId': 1},

      // Terrace tables
      {'id': 6, 'name': 'Table 6', 'capacity': 4, 'areaId': 2},
      {'id': 7, 'name': 'Table 7', 'capacity': 6, 'areaId': 2},
      {'id': 8, 'name': 'Table 8', 'capacity': 2, 'areaId': 2},

      // VIP tables
      {'id': 9, 'name': 'VIP 1', 'capacity': 8, 'areaId': 3},
      {'id': 10, 'name': 'VIP 2', 'capacity': 6, 'areaId': 3},
    ];

    for (var table in tables) {
      await database.into(database.areaTables).insert(
        AreaTablesCompanion.insert(
          id: Value(table['id'] as int),
          name: table['name'] as String,
          capacity: Value(table['capacity'] as int),
          areaId: Value(table['areaId'] as int),
        ),
      );
    }
  }

  Future<void> _generateCustomers() async {
    print('Creating customers...');
    final customers = [
      {'id': 1, 'firstName': 'Ahmed', 'lastName': 'Benali', 'phone': '0555123456'},
      {'id': 2, 'firstName': 'Fatima', 'lastName': 'Cherif', 'phone': '0666234567'},
      {'id': 3, 'firstName': 'Karim', 'lastName': 'Mansouri', 'phone': '0777345678'},
    ];

    for (var customer in customers) {
      await database.into(database.customers).insert(
        CustomersCompanion.insert(
          id: Value(customer['id'] as int),
          firstName: customer['firstName'] as String,
          lastName: customer['lastName'] as String,
          phone: Value(customer['phone'] as String?),
          isSynced: const Value(true), // Sample data is considered synced
        ),
      );
    }
  }

  Future<void> _generateCommercials() async {
    print('Creating commercials...');
    final commercials = [
      {'id': 1, 'firstName': 'Mohamed', 'lastName': 'Alami', 'cin': '123456789'},
      {'id': 2, 'firstName': 'Amina', 'lastName': 'Belkacem', 'cin': '987654321'},
    ];

    for (var commercial in commercials) {
      await database.into(database.commercials).insert(
        CommercialsCompanion.insert(
          id: Value(commercial['id'] as int),
          firstName: commercial['firstName'] as String,
          lastName: commercial['lastName'] as String,
          cin: commercial['cin'] as String,
        ),
      );
    }

  }

  Future<void> _generateStations() async {
    final stations = [
      {'id': 1, 'name': 'all', 'description': 'default station'},
      {'id': 2, 'name': 'burgers', 'description': 'for burgers'},
      {'id': 3, 'name': 'salads', 'description': 'for salads'},
    ];

    for (var station in stations) {
      await database.into(database.stations).insert(
        StationsCompanion.insert(
          id: Value(station['id'] as int),
          name: station['name'] as String,
          description: Value(station['description'] as String),
        ),
      );
    }
  }
}

