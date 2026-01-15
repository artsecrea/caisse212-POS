#!/bin/bash
# Quick Fix Script for ProductComponents Errors
# Fixes both: Null Check Error + Type Mismatch Error

echo "================================================"
echo "ProductComponents Error Fix Script"
echo "Fixes: Null Check + Type Mismatch Errors"
echo "================================================"
echo ""
echo "✅ Type mismatch fix: Already applied (code-level)"
echo "⚙️  Null check fix: Requires database regeneration"
echo ""
echo "Step 1/3: Regenerating database code..."
dart run build_runner build --delete-conflicting-outputs

if [ $? -eq 0 ]; then
    echo "✅ Database code regenerated successfully!"
else
    echo "❌ Failed to regenerate database code!"
    echo "Please run manually: dart run build_runner build --delete-conflicting-outputs"
    exit 1
fi

echo ""
echo "Step 2/3: Finding database file..."
DB_PATH=""

# Common locations for Linux
POSSIBLE_PATHS=(
    "$HOME/.local/share/posecrea/"
    "$HOME/.local/share/com.example.posecrea/"
    "./build/"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -d "$path" ]; then
        DB_FILES=$(find "$path" -name "*.db" 2>/dev/null)
        if [ ! -z "$DB_FILES" ]; then
            DB_PATH="$path"
            echo "Found database at: $DB_PATH"
            break
        fi
    fi
done

if [ ! -z "$DB_PATH" ]; then
    echo ""
    read -p "Do you want to delete the old database? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f $DB_PATH/*.db
        echo "✅ Old database deleted!"
        echo ""
        echo "Step 3/3: Database cleared successfully!"
        echo ""
        echo "================================================"
        echo "✅ FIX COMPLETE!"
        echo "================================================"
        echo ""
        echo "Next steps:"
        echo "1. Launch the app"
        echo "2. Click 'Demo Mode' on the tenant login screen"
        echo "3. This will regenerate the database with correct data"
        echo ""
    else
        echo "⚠️  Database not deleted. You can do this manually or use Demo Mode."
    fi
else
    echo "ℹ️  Database not found (might not exist yet)"
    echo ""
    echo "Step 3/3: No database to delete"
    echo ""
    echo "================================================"
    echo "✅ CODE GENERATION COMPLETE!"
    echo "================================================"
    echo ""
    echo "Next steps:"
    echo "1. Launch the app"
    echo "2. Use 'Demo Mode' to generate database with correct data"
    echo ""
fi

echo "For more details, see: PRODUCTCOMPONENTS_NULL_FIX.md"

