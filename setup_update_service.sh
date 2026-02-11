#!/bin/bash
# Quick Setup Script for Update Service

echo "🚀 Setting up Update Service..."

# Step 1: Create Android FileProvider directory
echo "📁 Creating Android FileProvider directory..."
mkdir -p android/app/src/main/res/xml

# Step 2: Create file_paths.xml
echo "📝 Creating file_paths.xml..."
cat > android/app/src/main/res/xml/file_paths.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <external-path name="external_files" path="."/>
    <external-cache-path name="external_cache" path="."/>
</paths>
EOF

# Step 3: Install dependencies
echo "📦 Installing dependencies..."
flutter pub get

echo ""
echo "✅ Setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Implement your update API in lib/services/update_service.dart"
echo "2. Add update check to your login screen"
echo "3. Test the update flow"
echo ""
echo "📚 Documentation:"
echo "- Full guide: UPDATE_SERVICE_README.md"
echo "- Installation: UPDATE_INSTALLATION.md"
echo "- Summary: UPDATE_IMPLEMENTATION_SUMMARY.md"
echo ""
echo "🎉 Ready to implement updates!"
