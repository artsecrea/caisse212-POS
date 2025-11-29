# Quick Start Guide - POS System

## 🚀 Quick Setup (5 minutes)

### Step 1: Install Dependencies
```bash
cd /home/arecrea/prj/posecrea
chmod +x setup.sh
./setup.sh
```

Or manually:
```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

### Step 2: Add Sample Data

Add this code to your `main.dart` (temporary, just for testing):

```dart
import 'utils/sample_data_generator.dart';

// Inside main() function, after WidgetsFlutterBinding.ensureInitialized();
final database = AppDatabase();
final generator = SampleDataGenerator(database);
  
// Check if database is empty
final users = await database.select(database.users).get();
if (users.isEmpty) {
  await generator.generateAll();
  print('Sample data generated!');
}
```

### Step 3: Run the App
```bash
flutter run
```

### Step 4: Login
Use these credentials:
- Username: `admin`
- Password: `admin123`

---

## 📱 How to Use

### Main Screen Layout

```
┌─────────────────────────────────────────────────────────┐
│  [Logo] POS System    [Status] [Network] [Update] [User]│  ← Top Bar
├──────────────────────────────────┬──────────────────────┤
│  [ All ] [ Burgers ] [ Pizza ]   │   CURRENT ORDER      │
│  ← Category Tabs →               │                      │
├──────────────────────────────────┤   [Select Table]     │
│                                  │   [Select Customer]  │
│  ┌──────┐  ┌──────┐  ┌──────┐  │   [Select Commercial]│
│  │ Prod │  │ Prod │  │ Prod │  │                      │
│  │  1   │  │  2   │  │  3   │  │   Order Items:       │
│  └──────┘  └──────┘  └──────┘  │   • Burger x2        │
│                                  │   • Pizza x1         │
│  ┌──────┐  ┌──────┐  ┌──────┐  │                      │
│  │ Prod │  │ Prod │  │ Prod │  │   Subtotal: 450 DZD  │
│  │  4   │  │  5   │  │  6   │  │   Tax: 0 DZD         │
│  └──────┘  └──────┘  └──────┘  │   Total: 450 DZD     │
│                                  │                      │
│          Product Grid            │   [Hold] [Print]     │
│                                  │   [  Proceed  ]      │
└──────────────────────────────────┴──────────────────────┘
```

### Actions

1. **Select Category**: Click category chips to filter products
2. **Add Product**:
   - **Tap**: Quick add to order
   - **Long Press**: Customize with components
3. **Modify Order**:
   - Use +/- buttons to change quantity
   - Click X to remove item
4. **Select Table**: Required for dine-in orders
5. **Add Customer** (Optional): Link customer to order
6. **Add Commercial** (Optional): Link salesperson to order
7. **Complete Order**:
   - **Hold**: Save for later
   - **Print**: Print receipt
   - **Proceed**: Complete and save order

---

## 🗄️ Database Schema

### Core Tables
- **Users**: Authentication and user management
- **Categories**: Product categories
- **Products**: Menu items
- **Components**: Product modifiers (extras, toppings)
- **Orders**: Customer orders
- **OrderProducts**: Products in orders
- **OrderProductComponents**: Component modifications
- **AreaTables**: Restaurant tables
- **Customers**: Customer information
- **Commercials**: Sales representatives

---

## 🔧 Configuration

### Change API URL
Edit `lib/services/auth_service.dart`:
```dart
_dio.options.baseUrl = 'https://your-api-url.com/api';
```

### Change Theme Color
Edit `lib/main.dart`:
```dart
colorScheme: ColorScheme.fromSeed(
  seedColor: Colors.deepOrange, // Change this
  brightness: Brightness.light,
),
```

---

## 🐛 Troubleshooting

### Build Errors
```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

### Database Issues
Delete the app and reinstall to reset database:
```bash
flutter clean
flutter run
```

### Package Conflicts
```bash
flutter pub upgrade
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs
```

---

## 📝 Next Steps

1. **Implement API Integration**:
   - Update `AuthService` with your backend API
   - Implement data sync endpoints

2. **Add Printing**:
   - Configure thermal printer
   - Customize receipt template

3. **KDS Integration**:
   - Connect to Kitchen Display System
   - Implement order routing by station

4. **Settings Screen**:
   - Theme customization
   - Font size adjustment
   - Printer configuration

5. **Reports**:
   - Daily sales reports
   - Product performance
   - Cash session management

---

## 🤝 Support

For issues or questions:
1. Check the `IMPLEMENTATION_README.md` file
2. Review error logs: `flutter logs`
3. Create an issue in the repository

---

## 📦 Project Structure

```
lib/
├── core/               # Enums and constants
├── data/
│   └── database/       # Drift database
├── domain/
│   └── models/         # Business models
├── presentation/       # UI screens & widgets
├── providers/          # Riverpod state management
├── services/           # API & external services
├── utils/              # Helper functions
└── main.dart           # App entry point
```

---

Happy coding! 🎉

