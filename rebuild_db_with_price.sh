#!/bin/bash
# Rebuild database schema after adding price field to OrderProductComponents

cd /home/artecrea/StudioProjects/posecrea
echo "Building database schema..."
flutter pub run build_runner build --delete-conflicting-outputs

echo "Database schema rebuild complete!"
