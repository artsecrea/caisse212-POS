#!/bin/bash

# POS System Setup Script

echo "========================================="
echo "   POS System - Setup Script"
echo "========================================="
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null
then
    echo "❌ Flutter is not installed. Please install Flutter first."
    echo "Visit: https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "✅ Flutter is installed"
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting Flutter dependencies..."
flutter pub get

if [ $? -ne 0 ]; then
    echo "❌ Failed to get dependencies"
    exit 1
fi

echo "✅ Dependencies installed"
echo ""

# Run code generation
echo "🔧 Running code generation for Drift database..."
flutter pub run build_runner build --delete-conflicting-outputs

if [ $? -ne 0 ]; then
    echo "❌ Code generation failed"
    exit 1
fi

echo "✅ Code generation complete"
echo ""

# Check for errors
echo "🔍 Checking for compilation errors..."
flutter analyze

echo ""
echo "========================================="
echo "   Setup Complete!"
echo "========================================="
echo ""
echo "To run the app:"
echo "  flutter run"
echo ""
echo "To run on a specific device:"
echo "  flutter devices        # List available devices"
echo "  flutter run -d <device-id>"
echo ""
echo "First time login credentials:"
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo "Note: You need to populate the database with sample data."
echo "You can do this by calling SampleDataGenerator in your code."
echo ""

