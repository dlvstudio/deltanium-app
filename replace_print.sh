#!/bin/bash

# Script to replace all print() with AppLogger.log() in Dart files
# Excludes app_logger.dart itself and test files

find lib -name "*.dart" ! -name "app_logger.dart" ! -path "*/test/*" | while read file; do
    # Check if file contains print(
    if grep -q "print(" "$file"; then
        echo "Processing: $file"
        
        # Check if AppLogger import already exists
        if ! grep -q "import 'package:deltanium_app/services/app_logger.dart';" "$file"; then
            # Add import after the first import statement
            sed -i '' "1,/^import /a\\
import 'package:deltanium_app/services/app_logger.dart';
" "$file"
        fi
        
        # Replace print( with AppLogger.log(
        # But keep // ignore: avoid_print lines
        sed -i '' 's/^\([[:space:]]*\)print(/\1AppLogger.log(/g' "$file"
        
        echo "  ✓ Updated $file"
    fi
done

echo ""
echo "Done! All print() replaced with AppLogger.log()"



