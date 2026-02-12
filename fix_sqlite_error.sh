#!/bin/bash

echo "=== Fixing SQLite3 External Function Errors ==="
echo ""

# Navigate to project directory
cd /home/artecrea/StudioProjects/posecrea

echo "1. Cleaning Flutter build cache..."
flutter clean

echo ""
echo "2. Removing pub cache for sqlite3..."
rm -rf ~/.pub-cache/hosted/pub.dev/sqlite3-*

echo ""
echo "3. Removing pubspec.lock to force dependency resolution..."
rm -f pubspec.lock

echo ""
echo "4. Getting Flutter dependencies..."
flutter pub get

echo ""
echo "5. Running build_runner to regenerate code..."
flutter pub run build_runner build --delete-conflicting-outputs

echo ""
echo "=== Fix Complete ==="
echo "Try running your app now with: flutter run"

