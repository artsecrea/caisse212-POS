#!/bin/bash

# Script to run Drift build_runner and generate database code
# This will fix all PendingSyncOperation errors

echo "=================================================="
echo "Running Drift Build Runner"
echo "=================================================="
echo ""
echo "This will generate the missing database code for:"
echo "  - PendingSyncOperation class"
echo "  - PendingSyncOperationsCompanion class"
echo "  - database.pendingSyncOperations accessor"
echo ""
echo "Starting build..."
echo ""

cd /home/artecrea/StudioProjects/posecrea

# Run build_runner
flutter pub run build_runner build --delete-conflicting-outputs

if [ $? -eq 0 ]; then
    echo ""
    echo "=================================================="
    echo "✅ BUILD SUCCESSFUL!"
    echo "=================================================="
    echo ""
    echo "All errors should now be resolved."
    echo "The following files were generated:"
    echo "  - lib/data/database/app_database.g.dart"
    echo ""
    echo "You can now:"
    echo "  1. Restart your IDE/analyzer"
    echo "  2. Test the offline sync system"
    echo "  3. Delete paid items (will queue offline)"
    echo ""
else
    echo ""
    echo "=================================================="
    echo "❌ BUILD FAILED"
    echo "=================================================="
    echo ""
    echo "Please check the error messages above."
    echo ""
fi

