# Deltanium System Architecture

> Document describing the overall architecture of the Deltanium ecosystem — a decentralized social network with end-to-end encryption.

## 1. System overview

Deltanium is a blockchain ecosystem with multiple specialized node types, allowing users to register, store encrypted content, share posts, and interact socially.

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                           DELTANIUM ECOSYSTEM                                            │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│   ┌──────────────┐     ┌──────────────────┐     ┌──────────────┐     ┌──────────────┐  │
│   │  Deltanium   │     │   Deltanium      │     │  Deltanium   │     │  Deltanium   │  │
│   │    App       │────▶│      API         │◀────│    Store     │     │   Block      │  │
│   │  (Flutter)   │     │  (Central API)   │     │   (Node)     │     │  Creator     │  │
│   └──────────────┘     └────────┬─────────┘     └──────────────┘     └──────────────┘  │
│          │                      │                        │                    │         │
│          │                      │                        │                    │         │
│          │                      ▼                        │                    │         │
│          │              ┌──────────────┐                 │                    │         │
│          │              │  Deltanium   │                 │                    │         │
│          └─────────────▶│    Core      │◀────────────────┴────────────────────┘         │
│                         │ (Umbral PRE) │                                                 │
│                         └──────────────┘                                                 │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

## 2. Main components

### 2.1 Deltanium App (Flutter)

| Component | Description | Technology |
|-----------|-------------|------------|
| **Main client** | Cross-platform application (iOS, Android, macOS, Web) | Flutter, Dart |
| **State** | StatefulWidget + Singleton services | Provider (planned) |
| **Crypto** | ECIES, digital signatures, BIP39 mnemonic | dart crypto, bip39 |
| **PRE** | Proxy Re-Encryption for followers | FFI → Rust (Umbral) |

**Directory structure:**
```
lib/
├── app/           # Router, GoRouter
├── config/        # constants.dart, theme.dart
├── data/          # models, mock
├── features/      # auth, feed, posts, profile, messages, create_post...
├── services/      # auth_service, post_service, crypto_service, pre_service...
└── widgets/       # reusable components
```

### 2.2 Deltanium API (Central API)

| Component | Description | Default port |
|-----------|-------------|--------------|
| **User Registration** | Registration, verify, profile | - |
| **Social Graph** | Follow/unfollow, following, followers | - |
| **Store Node Discovery** | List of storage nodes | - |
| **PRE Rekey Management** | Upload/fetch rekeys, PoP | - |
| **Stored File Index** | Index of files on nodes | - |
| **Blocker Selection** | Select the Block Creator that processes the tx and signs the decision | - |

**Main endpoints:**
- `POST /api/user/register` - Register with signature
- `GET /api/user/profile/{publicKey}`
- `GET /api/user/following`, `GET /api/user/followers`
- `POST /api/user/follow`, `POST /api/user/unfollow`
- `GET /api/storenode/list` - List of store nodes
- `POST /api/policy/upload-rekeys-batch`, `POST /api/policy/fetch-rekey`
- `POST /api/storedfile/register`

**Storage (file-based):**
- `users.json`, `user_follows.json`, `nodes.json`, `vouchers.json`, `stored_files.json`, `user_rekeys.json`

### 2.3 Deltanium Store (Storage Node)

| Component | Description | Default port |
|-----------|-------------|--------------|
| **File Storage** | Upload metadata, blocks; download | 5000/5001 |
| **Post Feed** | Timeline, following-feed, followers-feed | - |
| **Central API Client** | Get following list, validate PRE token | - |

**Main endpoints:**
- `POST /api/file/upload-metadata-raw` - Metadata (post/file)
- `POST /api/file/upload-file-block-raw` - Encrypted content
- `GET /api/post/followers-feed` - Feed for followers (PRE/ECIES)
- `GET /api/post/timeline` - User's posts
- `GET /api/file/block/{blockId}` - Download block

### 2.4 Deltanium Core

| Component | Description |
|-----------|-------------|
| **Umbral PRE** | Proxy Re-Encryption (Rust) |
| **C-ABI / FFI** | `native/umbral_pre/` - bindings for .NET and Flutter |
| **Policy Tags** | `followers:YYYY` (epoch-based) |

### 2.5 Deltanium User (.NET)

- Client library: CryptographyService, FileService, RequestSigner
- Demo: upload/download, file sharing, PRE Umbral
- Used for CLI/desktop workflows

### 2.6 Deltanium Block Creator

- MVP: Transaction pool, block creation, validation
- Communicates with the Central Coordinator (deltanium.com)
- Block structure, Merkle root, signing
- Receives tx directly from the App after being selected by the Central API
- Before accepting a tx, the Blocker asks the Central API; it only accepts if the returned decision confirms selection and has a valid signature

---

## 3. Detailed connection flows

### 3.1 App → API → Store

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  REGISTRATION & LOGIN FLOW                                                       │
└─────────────────────────────────────────────────────────────────────────────────┘

  [App]                    [Central API]                [Store]
    │                            │                         │
    │  POST /api/user/register   │                         │
    │  (signature, email, ...)   │                         │
    │ ─────────────────────────▶│                         │
    │                            │                         │
    │  200 OK                    │                         │
    │ ◀─────────────────────────│                         │
    │                            │                         │
    │  Save mnemonic, pubkey     │                         │
    │  (SharedPreferences)       │                         │
    │                            │                         │
    │  GET /api/storenode/list   │                         │
    │ ─────────────────────────▶│                         │
    │  [nodes]                   │                         │
    │ ◀─────────────────────────│                         │
```

### 3.2 Post creation flow (Post)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  POST CREATION FLOW (Public / Followers / Private)                               │
└─────────────────────────────────────────────────────────────────────────────────┘

  [App - CreatePostScreen]
    │
    │  1. PostService.createPost()
    │     - Create content JSON
    │     - FileCryptoService.encryptAndSplitFile() or createPublicFile()
    │       • ECIES(K, pkAuthor) + PRE encapsulateWithTag (if followers)
    │     - Return metadataEntries + blocks
    │
    │  2. FileUploadService.uploadEncryptedFile()
    │     - Select a node from api/storenode/list
    │     - Upload each metadata entry → POST /api/file/upload-metadata-raw
    │     - Upload each block → POST /api/file/upload-file-block-raw
    │
    ▼
  [Store Node]  ◀─── metadata + blocks (encrypted)
    │
    │  3. Register the file with the Central API
    │     POST /api/storedfile/register
    │
    ▼
  [Central API]
    │
    │  4. Rekey Sync (if followers)
    │     RekeySyncService.syncFollowersAndGenerateRekeys()
    │     - GET /api/user/new-followers
    │     - Generate rk(A→B) locally (PRE FFI)
    │     - POST /api/policy/upload-rekeys-batch
    │
    ▼
  [Central API] - store user_rekeys.json
```

### 3.3 Following feed read flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  FOLLOWING FEED READ FLOW                                                        │
└─────────────────────────────────────────────────────────────────────────────────┘

  [App - FollowingFeedService]
    │
    │  1. GET api/storenode/list  → list of endpoints
    │
    │  2. For each Store Node:
    │     GET {endpoint}/api/post/followers-feed
    │     Headers: X-User-PubKey, X-Timestamp, X-Signature
    │
    ▼
  [Store Node]
    │  - Call Central API: GET /api/user/following?userPubKey=...
    │  - Filter posts whose ownerPubKey is in following
    │  - Return posts (metadata + PRE fields if present)
    │
    ▼
  [App]
    │  3. For each post:
    │     - Public: download block, parse JSON
    │     - ECIES: decrypt with sk_user
    │     - PRE: PreService.fetchTransformToken() → requestProxyReencrypt()
    │            → decapsulateAndRecoverKey() → decrypt blocks
    │
    ▼
  [Display FollowingPost]
```

### 3.4 Overall connection diagram

```
                          ┌─────────────────────────────────────────────┐
                          │           Central API (localhost:5002)       │
                          │  - User, Follow, StoredFile, Policy, Store  │
                          └───────────────┬─────────────────────────────┘
                                          │
              ┌───────────────────────────┼───────────────────────────┐
              │                           │                           │
              ▼                           ▼                           ▼
┌─────────────────────────┐  ┌─────────────────────────┐  ┌─────────────────────────┐
│   Deltanium App         │  │   Deltanium Store       │  │   Deltanium Store       │
│   (Flutter)             │  │   Node 1 (:5000/5001)   │  │   Node N (...)          │
│                         │  │                         │  │                         │
│ - AuthService           │  │ - FileController        │  │ - CentralApiService     │
│ - UserService           │  │ - PostController        │  │ - FileStorageService    │
│ - PostService           │  │ - CentralApiService     │  │                         │
│ - FileUploadService     │  └───────────▲─────────────┘  └───────────▲─────────────┘
│ - FollowingFeedService  │              │                            │
│ - RekeySyncService      │              │   Upload metadata/blocks   │
│ - UserDiscoveryService  │              │   GET followers-feed       │
│ - StorageContractService│              │                            │
└────────────┬────────────┘              │                            │
             │                           │                            │
             │   GET storenode/list      │   POST upload-*-raw        │
             │   POST storedfile/register│   GET post/followers-feed  │
             │   GET user/*, policy/*    │   GET file/block/*         │
             │   (no direct tx submit)   │                            │
             │                           │   POST StorageOperation     │
             │                           │   + contract → Block Creator│
             │                           │   Blocker → API: decision   │
             └───────────────────────────┴────────────────────────────┘

### 3.5 Direct Tx flow to Block Creator (new flow)

```
[Store] ── POST StorageOperation + Contract ──▶ [Blocker]
  │                                             │
  │                                             ├─ POST /api/blockcreatornode/decision (Central API)
  │                                             │    ↳ receive decision + signature
  │                                             ├─ verify selection + verify contract signature
  │                                             └─ accept tx → mempool.json
  │
  └─ (Central API only selects the blocker + signs the decision)
```
```

---

## 4. Security model

### 4.1 Request authentication

- **Signing format:** `METHOD + PATH + TIMESTAMP + SHA256(body)`
- **Headers:** `X-User-PubKey`, `X-Timestamp`, `X-Signature`
- **Replay:** Timestamp within a 5-minute window

### 4.2 Blocker Selection Decision (Payload + Signature)

**Purpose:** The Central API returns a decision selecting a Block Creator for a tx; the Blocker only accepts the tx if it verifies a valid signature and that it is the selected party.

**Decision payload (JSON):**
```
{
  "txId": "<txId>",
  "blockerPubKey": "<blockerPubKey>",
  "selected": true,
  "issuedAt": 1730000000,
  "expiresAt": 1730000060,
  "nonce": "<random>"
}
```

**String to sign (Central API):**
```
DECISION|<txId>|<blockerPubKey>|<selected>|<issuedAt>|<expiresAt>|<nonce>
```

**Decision response (API → Blocker):**
```
{
  "decision": { ...payload above... },
  "signature": "<base64 ECDSA signature>"
}
```

**Verification (Blocker):**
1) `now` must be within `[issuedAt, expiresAt]`  
2) `selected == true`  
3) `blockerPubKey` matches own public key  
4) Verify `signature` using Central API public key over the exact string above  
5) If all pass → accept tx into mempool

### 4.2 Content encryption

| Type | Mechanism | Applied to |
|------|-----------|------------|
| Public | No encryption | shareType=public |
| Me/Private | ECIES(K, pkOwner) | shareType=me |
| Followers (ECIES) | encryptedKey per recipient | shareType=followers (Option 1) |
| Followers (PRE) | encapsulateWithTag + rekey | shareType=followers (Option 2) |

### 4.3 PRE (Option 2 - Delegated)

- Author creates rekey rk(A→B) client-side
- Upload batch to the Central API
- Follower: PoP (sign nonce) → fetch rekey → client re-encrypt → decapsulate

---

## 5. Default configuration

| Service | URL/Port |
|---------|----------|
| Central API | http://localhost:5002 |
| Store Node | http://localhost:5000 or 5001 |
| App API Base | CENTRAL_API_BASE=http://127.0.0.1:5002/api |

---

## 6. Dependency Graph (summary)

```
deltanium-app
  ├── Central API (HTTP) - selection + signing
  ├── Store Nodes (HTTP) - discovered via API
  ├── Block Creator (HTTP) - direct tx submit
  └── deltanium-core/native (Umbral PRE FFI)

deltanium-store
  ├── Central API (HTTP) - following, user info, PRE token
  └── Local file storage

deltanium-api
  └── File-based JSON storage

deltanium-blocker
  └── Central Coordinator (deltanium.com)
```

---

*This document was produced from source-code analysis of deltanium-api, deltanium-app, deltanium-store, deltanium-core, deltanium-user, and deltanium-blocker.*
