# Deltanium Mobile App

A responsive, cross-platform social media application built with Flutter for the Deltanium blockchain network. This app provides a modern, Twitter-like interface for interacting with the decentralized Deltanium social network.

![Deltanium App](https://via.placeholder.com/800x400?text=Deltanium+App)

## Project Status

**Current Phase**: Development / MVP (Not Production Ready)

The Deltanium ecosystem is currently a high-quality prototype demonstrating advanced features like Proxy Re-Encryption (PRE) and decentralized storage. However, several infrastructure components (Database persistence, P2P networking, Consensus) are in MVP stage.

See [BLOCKCHAIN_PLAN.md](BLOCKCHAIN_PLAN.md) for the detailed production readiness assessment and roadmap.

## Features

- **User Registration & Login**
  - Register with email, full name, date of birth, bio, avatar URL, and password.
  - Generates a cryptographic key pair and mnemonic (recovery phrase) on registration.
  - Signs registration data client-side before sending to the backend.
  - Locally saves user credentials (email, mnemonic, public key) for quick login.
  - Login with mock accounts or any locally saved user.

- **Social Network**
  - Twitter-like timeline for viewing posts
  - Ability to create text and media posts
  - Like, comment, and repost functionality
  - User profiles with stats and activity history

- **UI/UX**
  - Modern, clean interface with Twitter-inspired design
  - Dark theme optimized for all devices
  - Fully responsive layout (mobile, tablet, desktop)
  - Native-feeling interactions and animations

- **Blockchain Integration**
  - Content verification through blockchain
  - Decentralized content storage
  - End-to-end encryption for private content
  - Transparent content attribution and ownership
  - Storage contracts: App and Store sign a contract (hash or message); Store submits a single `StorageOperation` tx with the contract in **envelope format** (`hash`, `appSignature`, `storageNodeSignature`, `content`). Contract **content** is dynamic; only `appPublicKey` and `storageNodePublicKey` are required for chain validation. See [BLOCKCHAIN_PLAN.md](BLOCKCHAIN_PLAN.md) for envelope spec, V1/V2 signing, and Blocker behaviour.
  - **Central API** selects a blocker: for each request (decision to accept a tx or block-slot to create a block), Central takes the list of active block creator nodes and **randomly selects one node**; only the selected node receives `selected`/`granted` and the signature. The Blocker must store the Central API public key (in `node_info.json` or env) and verify the signature (signed over the SHA256 of the message). Details: [BLOCKCHAIN_PLAN.md](BLOCKCHAIN_PLAN.md) — sections "How Central API selects a blocker", "Decision Format", "Block-slot and block signatures".

- **Proxy Re-Encryption (PRE)**
  - Hybrid approach for followers-only sharing:
    - Posts/media carry BOTH `encryptedKey` (ECIES for author) AND `encapsulatedForRecipient` (PRE capsule for followers)
    - Authors decrypt directly via ECIES; followers use PRE client-transform + decapsulation
  - Policy-based sharing with tags (e.g., `followers:2025`) and `policyScheme = CPRE`
  - Delegated rekey generation (Option 3): author generates `rk(A→B)` locally and uploads to Central API
  - Rekey sync is triggered after successful login/registration
  - Client-side capsule transform and decapsulation using native Umbral PRE (FFI)

- **Storage Node Integration**
  - Discovers available storage nodes via the central API (`GET /api/storenode/list`).
  - Selects a node when creating a post.
  - Uploads encrypted post metadata (per recipient for followers/private) and encrypted content blocks to the selected node.

## Responsive Design

The app features a fully responsive design that adapts to different screen sizes:

- **Mobile View**: Optimized for phones with a streamlined interface
- **Tablet View**: Enhanced layout with more content visible at once
- **Desktop View**: Three-column layout similar to Twitter web interface:
  - Left column: Navigation menu
  - Center column: Content feed (tweets/posts)
  - Right column: Search, trending topics, and suggested users

## Registration & Login Flow

1. **Registration**
   - Fill in the registration form.
   - The app generates a mnemonic and key pair locally (bip39 + client-side crypto).
   - The app signs the registration data with the generated private key and sends all required fields to `/api/user/register`.
   - On success, the app displays the mnemonic and public key for the user to save.
   - The user can save their credentials locally for quick login.

2. **Login**
   - Enter email and password, or tap a test/local user card for instant login.
   - Local users are shown with a "Local" badge and can be logged in with one tap.

## Post Creation Flow

1. Compose text/media and choose share type (public/followers/private).
2. The app prepares encrypted content and per-recipient metadata (for followers/private).
   - Followers-only (PRE hybrid):
     - `encryptedKey = ECIES(K, pkAuthor)` (author’s direct access)
     - `encapsulatedForRecipient = PRE.encapsulateWithTag(K, pkAuthor, tag)` (one capsule reused by all followers)
     - `ownerPubKey`, `policyTag`, `capsuleFor = "tag"`, `policyScheme = "CPRE"`
3. The app fetches available storage nodes (`GET /api/storenode/list`) and selects one.
4. The app uploads:
   - Encrypted metadata (JSON) describing the post and access parameters.
   - Encrypted content blocks (raw binary) to the selected storage node.
5. Followers with access fetch and decrypt posts from storage nodes.

## Local User Storage

- Saved users are stored locally (using `SharedPreferences`).
- You can view and log in with any saved user from the login screen.

## Getting Started

### Prerequisites

- Flutter SDK (3.0+ recommended)
- Dart SDK
- Android Studio / VS Code
- Rust toolchain (for building native PRE library)
- macOS: Xcode Command Line Tools

### Setup

1. **Clone and install dependencies:**
   ```bash
   git clone <your-repo-url>
   cd deltanium-app
   flutter pub get
   ```

2. **Build native Umbral PRE library (for Proxy Re-Encryption):**
   
   **For macOS:**
   ```bash
   cd ../deltanium-core/native/umbral_pre
   cargo build --release --target x86_64-apple-darwin
   
   # Copy to app bundle and sign
   cp target/x86_64-apple-darwin/release/libumbral_pre.dylib \
      ../../deltanium-app/build/macos/Build/Products/Debug/deltanium_app.app/Contents/Frameworks/
   
   codesign --force --deep --sign - \
      ../../deltanium-app/build/macos/Build/Products/Debug/deltanium_app.app/Contents/Frameworks/libumbral_pre.dylib
   ```
   
   **For iOS:**
   ```bash
   # Install cargo-lipo if not already installed
   cargo install cargo-lipo
   
   # Build for iOS
   cargo lipo --release
   
   # Add the resulting .a file to Xcode project
   # In Xcode: Runner → Build Phases → Link Binary With Libraries
   # Add: target/universal/release/libumbral_pre.a
   ```
   
   **For Android:**
   ```bash
   # Install cargo-ndk if not already installed
   cargo install cargo-ndk
   
   # Build for Android targets
   cargo ndk -t armeabi-v7a -t arm64-v8a -t x86 -t x86_64 build --release
   
   # Copy .so files to jniLibs
   mkdir -p ../../deltanium-app/android/app/src/main/jniLibs/{armeabi-v7a,arm64-v8a,x86,x86_64}
   cp target/armv7-linux-androideabi/release/libumbral_pre.so \
      ../../deltanium-app/android/app/src/main/jniLibs/armeabi-v7a/
   cp target/aarch64-linux-android/release/libumbral_pre.so \
      ../../deltanium-app/android/app/src/main/jniLibs/arm64-v8a/
   cp target/i686-linux-android/release/libumbral_pre.so \
      ../../deltanium-app/android/app/src/main/jniLibs/x86/
   cp target/x86_64-linux-android/release/libumbral_pre.so \
      ../../deltanium-app/android/app/src/main/jniLibs/x86_64/
   ```

3. **Run the app:**
   ```bash
   cd ../../deltanium-app
   
   # For macOS
   flutter run -d macos
   
   # For iOS
   flutter run -d ios
   
   # For Android
   flutter run -d android
   
   # For web (PRE features will be limited)
   flutter run -d chrome --dart-define=ENV=dev --web-port=6868 --web-browser-flag "--disable-web-security"
   ```

### Troubleshooting

#### Error: "Failed to load dynamic library libumbral_pre.dylib"

This error occurs when the native Umbral PRE library is not found or not properly signed.

**Error Message Example:**
```
Failed to load dynamic library '/Users/.../libumbral_pre.dylib': dlopen(...): tried: '...' (no such file)
```

**Root Causes:**
1. Library file not copied to app bundle
2. Library not signed (required on macOS)
3. Library path incorrect after `flutter clean` or rebuild

**Solution for macOS:**

1. **Build the library (if not already built):**
   ```bash
   cd ../deltanium-core/native/umbral_pre
   cargo build --release --target x86_64-apple-darwin
   ```

2. **Copy to the app bundle:**
   ```bash
   # Ensure the Frameworks directory exists
   mkdir -p ../../deltanium-app/build/macos/Build/Products/Debug/deltanium_app.app/Contents/Frameworks/
   
   # Copy the library
   cp target/x86_64-apple-darwin/release/libumbral_pre.dylib \
      ../../deltanium-app/build/macos/Build/Products/Debug/deltanium_app.app/Contents/Frameworks/
   ```

3. **Ad-hoc sign the library (required on macOS):**
   ```bash
   codesign --force --deep --sign - \
      ../../deltanium-app/build/macos/Build/Products/Debug/deltanium_app.app/Contents/Frameworks/libumbral_pre.dylib
   ```

4. **Verify the library:**
   ```bash
   file ../../deltanium-app/build/macos/Build/Products/Debug/deltanium_app.app/Contents/Frameworks/libumbral_pre.dylib
   # Should output: Mach-O 64-bit dynamically linked shared library x86_64
   
   # Check file size (should be ~880KB)
   ls -lh ../../deltanium-app/build/macos/Build/Products/Debug/deltanium_app.app/Contents/Frameworks/libumbral_pre.dylib
   ```

5. **Restart the app** (do not rebuild, just restart the running instance)

**Important Notes:**
- ⚠️ **Every time you run `flutter clean` or rebuild the app from scratch, you need to repeat steps 2-3 above.**
- The library loader (`pre_ffi.dart`) will try two paths:
  1. Direct load: `libumbral_pre.dylib` (from system/library paths)
  2. Fallback: `@executable_path/../Frameworks/libumbral_pre.dylib` (from app bundle)
- If both paths fail, the improved error handler will show detailed instructions on how to fix the issue, including:
  - Which paths were tried
  - Whether the file exists
  - Exact commands to run to fix the problem
- The library must be signed with `codesign` for macOS security requirements.
- The error handler checks file existence before attempting to load, providing clearer error messages.

**Quick Fix Script:**
You can create a helper script to automate the copy and sign process:
```bash
#!/bin/bash
# fix_pre_lib.sh - Quick fix for libumbral_pre.dylib on macOS

LIB_SRC="../deltanium-core/native/umbral_pre/target/x86_64-apple-darwin/release/libumbral_pre.dylib"
LIB_DST="build/macos/Build/Products/Debug/deltanium_app.app/Contents/Frameworks/libumbral_pre.dylib"

# Create directory if it doesn't exist
mkdir -p "$(dirname "$LIB_DST")"

# Copy library
cp "$LIB_SRC" "$LIB_DST"

# Sign library
codesign --force --deep --sign - "$LIB_DST"

echo "✅ Library copied and signed successfully!"
echo "   Location: $LIB_DST"
```

#### Error: "CodeSign failed with a nonzero exit code"

This occurs when the library is not signed or the signature is invalid.

**Solution:**
Run the ad-hoc signing command:
```bash
codesign --force --deep --sign - \
   build/macos/Build/Products/Debug/deltanium_app.app/Contents/Frameworks/libumbral_pre.dylib
```

#### PRE Posts Not Showing in Following Tab

If posts shared with followers using PRE (Option 2) don't appear:

1. **Check if ownerPubKey is in metadata:** New posts should include `ownerPubKey` in metadata entry.
2. **Old posts:** The app automatically extracts `ownerPubKey` from the PRE bundle for backward compatibility.
3. **Check logs:** Look in `appLogs/app-YYYYMMDD.log` for PRE-related errors.

#### Followers Can See Posts But Images Fail to Decrypt

If images under posts fail with ECIES auth errors on follower accounts:

- Ensure media metadata includes PRE fields: `ownerPubKey`, `policyTag`, `capsuleFor = tag`, `encapsulatedForRecipient`
- Confirm Central API has a stored rekey for `(author → follower, tag)`
- App will fetch nonce, sign PoP, fetch rekey, client-transform capsule, then decapsulate

### PRE Hybrid Encryption (Delegated Rekey Generation)

- Author encrypts symmetric key K:
  - ECIES: `encryptedKey = ECIES(K, pkAuthor)`
  - PRE: `encapsulatedForRecipient = EncapsulateWithTag(pkAuthor, tag, K)`
- Attached media inherit the same fields and behavior as posts
- Follower decryption:
  1) Fetch `rk(A→B)` from Central API (PoP required)
  2) `capsuleForB = reencrypt(capsuleForA, rk)` (client-side)
  3) `K = decapsulateForRecipient(capsuleForB, skB, tag)`
  4) Decrypt AES-GCM/CBC content with K

### Rekey Sync on Login

- After login/registration, the app calls `RekeySyncService.syncFollowersAndGenerateRekeys`:
  - Fetches new followers without rekeys
  - Generates `rk(A→B)` locally via Umbral PRE FFI using `skAuthor` derived from mnemonic
  - Uploads in batch to Central API

### Data Fields (posts and attached media)

- `encryptedKey`: base64 ECIES of K for `pkAuthor` (always present)
- `encapsulatedForRecipient`: base64 PRE capsule of K for `pkAuthor` and `policyTag` (followers-only)
- `ownerPubKey`: hex author public key (followers-only)
- `policyTag`: e.g., `followers:2025` (followers-only)
- `capsuleFor`: `tag` (followers-only)
- `policyScheme`: `CPRE` (followers-only)

#### Logs Not Appearing

App logs are written to `deltanium-app/appLogs/app-YYYYMMDD.log` in debug mode.

- **Location:** `<project-root>/appLogs/app-20251021.log`
- **Format:** `HH:mm:ss.fff <message>`
- **Note:** Logs are only written in debug mode (sandbox disabled)

## API & Node Endpoints

- Central API default base URL: `http://localhost:5002`
- Storage node endpoints are discovered from the central API via `GET /api/storenode/list` (local store often runs at `http://localhost:5001`).

## Development Architecture

### Directory Structure

```
lib/
├── app/                  # Application setup and routing
├── config/               # App configuration and themes
├── data/                 # Data layer
│   ├── mock/            # Mock data for development
│   ├── models/          # Data models
│   └── services/        # API services
├── features/             # Feature modules
│   ├── auth/            # Authentication
│   ├── create_post/     # Post creation with PRE option
│   ├── feed/            # Feed widgets
│   ├── posts/           # Post screens (my posts, following, public)
│   ├── profile/         # User profile
│   └── ...              # Other features
├── screens/              # Legacy UI screens
├── services/             # Core services
│   ├── auth_service.dart          # Authentication
│   ├── crypto_service.dart        # Cryptography (ECIES, signing)
│   ├── file_crypto_service.dart   # File encryption/decryption
│   ├── post_service.dart          # Post creation
│   ├── pre_service.dart           # PRE operations (FFI)
│   ├── pre_ffi.dart               # FFI bindings for Umbral PRE
│   ├── following_feed_service.dart # Feed loading with PRE support
│   └── app_logger.dart            # File-based logging
└── widgets/              # Reusable UI components

native/ (in deltanium-core)
└── umbral_pre/           # Rust Umbral PRE library
    ├── src/lib.rs        # C-ABI wrapper for Flutter FFI
    └── Cargo.toml        # Rust dependencies
```

### Mock Data

The app currently uses mock data for development purposes, simulating the backend API. This includes:

- User profiles with mock blockchain identities
- Posts/tweets with engagement metrics
- Comments and interactions
- Notifications and trending topics

### State Management

The app uses a combination of:
- StatefulWidget for simple state
- Singleton services for global access to data (e.g., AuthService, PostService)
- Provider is included and planned for wider use (not yet pervasive)

## Usage

### Testing Accounts

For testing purposes, you can use any of these mock accounts:

- **John Doe**: john@example.com
- **Alice**: alice@example.com
- **Bob**: bob@example.com

Or register a new account and save it locally.

### App Navigation

- Home screen: View the main timeline/feed
- Search: Find users and content
- Notifications: View interactions with your content
- Profile: View and edit your profile

## Future Plans

- Integration with the actual Deltanium blockchain backend
- Wallet functionality for cryptocurrency transactions
- Direct messaging with end-to-end encryption
- Enhanced media sharing capabilities
- Push notifications

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- Flutter team for the amazing framework
- Twitter for UI/UX inspiration
- Blockchain community for decentralization concepts
