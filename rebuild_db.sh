#!/bin/bash
# Simple rebuild database script

echo "Rebuilding database code..."
dart run build_runner build --delete-conflicting-outputs

echo ""
echo "Done! Now launch the app and use Demo Mode to regenerate the database."

