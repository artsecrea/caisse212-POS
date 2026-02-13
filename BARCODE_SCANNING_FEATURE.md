# Barcode Scanning Feature Implementation

## Overview
Implemented barcode scanning functionality to automatically load orders when their barcode is scanned after login.

## Changes Made

### 1. Fixed Barcode Printing Issue
**Problem**: Barcodes were printing numbers instead of actual alphanumeric codes.

**Solution**: Changed from Code 128 to Code 39 format and properly converted strings to code units:
- Changed `Barcode.code128(orderCode.codeUnits)` to `Barcode.code39(orderCode.codeUnits)`
- Code 39 is more reliable for alphanumeric codes with barcode scanners
- Added text label above barcode for better readability

**Files Modified**:
- `lib/services/printing_service.dart`
  - Updated `printOrderReceipt()` method
  - Updated `printKdsTicket()` method  
  - Updated `printTicketReceipt()` method

### 2. Added Configurable Text Size for Printers
**Feature**: Users can now configure print text size (Normal/Large/Extra Large)

**Implementation**:
- Added `textSize` field to `PrinterConfig` class (1=Normal, 2=Large, 3=Extra Large)
- Added `setTextSize()` method to `PrintingService`
- Added `_resolveTextSize()` and `_resolveHeaderSize()` helper methods
- Updated all print methods to use configured text sizes dynamically
- Added UI control in `PrintersManagementScreen` with segmented button selector

**Files Modified**:
- `lib/services/printing_service.dart`
- `lib/presentation/widgets/printers_management_screen.dart`

### 3. Implemented Automatic Barcode Scanning
**Feature**: USB/Wireless barcode scanners automatically load orders after login

**Implementation**:
- Created `BarcodeScannerService` class to handle keyboard input from barcode scanners
- Added barcode scanner provider in `database_providers.dart`
- Integrated scanner into `MainScreen` with Focus widget and keyboard event handling
- Added `getOrderByCode()` method to `OrderRepository`
- When a barcode is scanned:
  - Automatically searches for order by code
  - Loads the order if found
  - Shows success/error notification to user

**Files Created**:
- `lib/services/barcode_scanner_service.dart`

**Files Modified**:
- `lib/providers/database_providers.dart` - Added barcode scanner provider
- `lib/providers/order_provider.dart` - Added `getOrderByCode()` method
- `lib/presentation/main_screen/main_screen.dart` - Integrated barcode scanning
- `pubspec.yaml` - Added `flutter_barcode_listener: ^0.1.5` package

## How It Works

### Barcode Scanning Flow:
1. User logs into the application
2. Main screen initializes and requests keyboard focus
3. When user scans a barcode (scanner acts as keyboard input):
   - BarcodeScannerService captures keyboard events
   - Accumulates characters until Enter key is pressed
   - Emits the complete barcode string
4. MainScreen receives the barcode
5. Searches database for order with matching code
6. Loads order into current order state if found
7. Shows notification to user

### Barcode Format:
- Using Code 39 format for better scanner compatibility
- Supports alphanumeric codes (letters and numbers)
- Order codes are automatically generated as 8-character uppercase strings (e.g., "A1B2C3D4")

## Testing

To test barcode scanning:
1. Log into the application
2. Use a USB/Wireless barcode scanner
3. Scan a printed order barcode
4. The order should automatically load

To test barcode printing:
1. Create an order
2. Click "Print" button
3. The receipt will include a Code 39 barcode above the order code text
4. Scan the printed barcode to verify it works correctly

## Configuration

### Text Size Configuration:
1. Navigate to **Printers** from dropdown menu
2. Under **Printer Settings**, select text size:
   - **Normal**: Standard size text
   - **Large**: Increased text size for better readability
   - **Extra Large**: Maximum text size

### Barcode Scanner Setup:
- No configuration needed
- Works with any USB or wireless barcode scanner that emulates keyboard input
- Scanner must be configured to send "Enter" key after barcode data

## Notes

- Barcode scanning is automatically enabled when MainScreen loads
- The scanner maintains focus to capture all keyboard events
- Debounce timer (100ms) ensures complete barcode capture
- Code 39 format chosen for wide compatibility with standard barcode scanners
- Text size affects all printed receipts, KDS tickets, and payment tickets
