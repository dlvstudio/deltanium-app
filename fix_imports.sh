#!/bin/bash

# Fix imports for AppLogger

files=(
"lib/app/router.dart"
"lib/features/posts/screens/my_posts_screen.dart"
"lib/features/posts/screens/following_posts_screen.dart"
"lib/features/posts/screens/public_posts_screen.dart"
"lib/features/posts/widgets/optimized_post_list.dart"
"lib/features/auth/screens/login_screen.dart"
"lib/features/create_post/screens/create_post_screen.dart"
"lib/features/file_manager/screens/secure_file_upload_screen.dart"
"lib/features/file_manager/file_upload_service.dart"
"lib/features/feed/widgets/lazy_image_widget.dart"
"lib/features/feed/widgets/simple_image_widget.dart"
"lib/features/feed/widgets/related_files_widget.dart"
"lib/screens/login/login_screen.dart"
"lib/data/mock/mock_data.dart"
"lib/data/mock/mock_auth_service.dart"
"lib/services/following_feed_service.dart"
"lib/services/ecies_service.dart"
"lib/services/file_crypto_service.dart"
"lib/services/crypto_service.dart"
"lib/services/image_download_service.dart"
"lib/services/auth_service.dart"
"lib/services/request_signer.dart"
"lib/services/user_discovery_service.dart"
"lib/services/post_service.dart"
"lib/services/user_service.dart"
"lib/services/image_cache_service.dart"
)

for file in "${files[@]}"; do
    # Check if AppLogger import already exists
    if ! grep -q "import 'package:deltanium_app/services/app_logger.dart';" "$file"; then
        echo "Adding import to: $file"
        # Add import after the first import or at the beginning
        if grep -q "^import " "$file"; then
            # Insert after the last import before any blank line
            awk '/^import / {imports = imports $0 "\n"; next} !found && imports {print imports "import '\''package:deltanium_app/services/app_logger.dart'\'';\n"; found=1} {print}' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        else
            # No imports, add at the top
            echo "import 'package:deltanium_app/services/app_logger.dart';" | cat - "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        fi
        echo "  ✓ Import added"
    else
        echo "Skipping $file (import already exists)"
    fi
done

echo ""
echo "Done! All imports fixed."



