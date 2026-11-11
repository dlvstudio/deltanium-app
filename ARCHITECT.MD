# Deltanium System Architecture

> Tài liệu mô tả kiến trúc tổng thể của hệ sinh thái Deltanium - mạng xã hội phi tập trung với mã hóa đầu cuối.

## 1. Tổng quan hệ thống

Deltanium là hệ sinh thái blockchain với nhiều loại node chuyên biệt, cho phép người dùng đăng ký, lưu trữ nội dung mã hóa, chia sẻ bài đăng và tương tác xã hội.

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

## 2. Các thành phần chính

### 2.1 Deltanium App (Flutter)

| Thành phần | Mô tả | Công nghệ |
|------------|-------|-----------|
| **Client chính** | Ứng dụng cross-platform (iOS, Android, macOS, Web) | Flutter, Dart |
| **Trạng thái** | StatefulWidget + Singleton services | Provider (dự kiến) |
| **Crypto** | ECIES, ký số, mnemonic BIP39 | dart crypto, bip39 |
| **PRE** | Proxy Re-Encryption cho followers | FFI → Rust (Umbral) |

**Cấu trúc thư mục:**
```
lib/
├── app/           # Router, GoRouter
├── config/        # constants.dart, theme.dart
├── data/          # models, mock
├── features/      # auth, feed, posts, profile, messages, create_post...
├── services/      # auth_service, post_service, crypto_service, pre_service...
└── widgets/       # components tái sử dụng
```

### 2.2 Deltanium API (Central API)

| Thành phần | Mô tả | Port mặc định |
|------------|-------|---------------|
| **User Registration** | Đăng ký, verify, profile | - |
| **Social Graph** | Follow/unfollow, following, followers | - |
| **Store Node Discovery** | Danh sách storage nodes | - |
| **PRE Rekey Management** | Upload/fetch rekeys, PoP | - |
| **Stored File Index** | Index file trên các node | - |
| **Blocker Selection** | Chọn Block Creator xử lý tx và ký quyết định | - |

**Endpoints chính:**
- `POST /api/user/register` - Đăng ký với signature
- `GET /api/user/profile/{publicKey}`
- `GET /api/user/following`, `GET /api/user/followers`
- `POST /api/user/follow`, `POST /api/user/unfollow`
- `GET /api/storenode/list` - Danh sách store nodes
- `POST /api/policy/upload-rekeys-batch`, `POST /api/policy/fetch-rekey` (signed)
- `POST /api/policy/validate-token` - Store gọi với `X-Internal-Token`
- `POST /api/storedfile/register` - đăng ký 1 placement (signed, owner)
- `POST /api/storedfile/register-replicas` - N-of-M: cùng `fileId` trên nhiều `storeNodeId` (signed)
- `POST /api/tx/submit` - queue tx (signed; caller = `From`)
- `GET /api/tx/pull` - Blocker kéo tx (bắt buộc `X-Internal-Token`)

**Lưu trữ:**
- Mặc định production/local: **MySQL** (`Storage:Provider=MySql`, connection qua User Secrets / `ConnectionStrings:Default`)
- Fallback JSON (dev): `users.json`, `nodes.json`, `stored_files.json`, … — **không commit** secrets
- Secrets ngoài repo: `CENTRAL_PUBLIC_KEY` / `CENTRAL_PRIVATE_KEY` hoặc `~/.deltanium/central_keys.json`; voucher Store/Blocker qua env / user-secrets (`STORE_VOUCHER`, `VOUCHER`)
- Internal service token: `INTERNAL_API_TOKEN` / `InternalApi:Token`

### 2.3 Deltanium Store (Storage Node)

| Thành phần | Mô tả | Port mặc định |
|------------|-------|---------------|
| **File Storage** | Upload metadata, blocks; download | 5000/5001 |
| **Post Feed** | Timeline, following-feed, followers-feed | - |
| **Central API Client** | Following list; `validate-token` kèm `X-Internal-Token` | - |
| **Đăng ký node** | Voucher one-shot (atomic consume trên API) | env `STORE_VOUCHER` |

**Endpoints chính:**
- `POST /api/file/upload-metadata-raw` - Metadata (post/file)
- `POST /api/file/upload-file-block-raw` - Nội dung mã hóa
- `GET /api/post/followers-feed` - Feed cho followers (PRE/ECIES)
- `GET /api/post/timeline` - Bài của user
- `GET /api/file/block/{blockId}` - Tải block

> N-of-M: cùng ciphertext/`fileId` có thể nằm trên nhiều Store node; App upload song song theo `REPLICATION_FACTOR`.

### 2.4 Deltanium Core

| Thành phần | Mô tả |
|------------|-------|
| **Umbral PRE** | Proxy Re-Encryption (Rust) |
| **C-ABI / FFI** | `native/umbral_pre/` - bindings cho .NET và Flutter |
| **Policy Tags** | `followers:YYYY` (epoch-based) |

### 2.5 Chat (1-1, E2E)

| Chế độ | Cơ chế |
|--------|--------|
| **Online** | WebRTC P2P; Central = presence + signaling (`/api/chat/online*`, `/api/chat/signaling/*`) |
| **Offline** | Mỗi tin = 1 file mã hóa trên Store; Central chỉ index metadata (`/api/chat/message`) |

- Auth: `SignatureAuthHelper` (cùng format chữ ký như Policy/StoredFile)
- IDOR: chỉ **participant** của conversation được đọc/ghi message; sender luôn = caller đã ký
- Offline upload: App chọn N Store nodes (`REPLICATION_FACTOR`) qua `FileUploadService` (full replicas)
- Chi tiết thiết kế: `CHAT.md`

### 2.6 Deltanium User (.NET) — archived

- Legacy CLI/demos (CryptographyService, FileService, RequestSigner, PRE Umbral)
- Public repo archived: [deltanium-user](https://github.com/dlvstudio/deltanium-user)
- End-user client is **deltanium-app** (Flutter)

### 2.7 Deltanium Block Creator

- MVP: Transaction pool, block creation, validation
- Giao tiếp với Central Coordinator (deltanium.com)
- Block structure, Merkle root, signing
- Nhận tx trực tiếp từ App sau khi được Central API chọn
- Trước khi nhận tx, Blocker hỏi Central API; chỉ chấp nhận nếu quyết định trả về xác nhận chọn và có chữ ký hợp lệ

---

## 3. Luồng kết nối chi tiết

### 3.1 App → API → Store

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  LUỒNG ĐĂNG KÝ & ĐĂNG NHẬP                                                       │
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
    │  Lưu mnemonic, pubkey      │                         │
    │  (SharedPreferences)       │                         │
    │                            │                         │
    │  GET /api/storenode/list   │                         │
    │ ─────────────────────────▶│                         │
    │  [nodes]                   │                         │
    │ ◀─────────────────────────│                         │
```

### 3.2 Luồng tạo bài đăng (Post)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  LUỒNG TẠO BÀI ĐĂNG (Public / Followers / Private)                               │
└─────────────────────────────────────────────────────────────────────────────────┘

  [App - CreatePostScreen]
    │
    │  1. PostService.createPost()
    │     - Tạo JSON nội dung
    │     - FileCryptoService.encryptAndSplitFile() hoặc createPublicFile()
    │       • ECIES(K, pkAuthor) + PRE encapsulateWithTag (nếu followers)
    │     - Trả về metadataEntries + blocks
    │
    │  2. FileUploadService.uploadEncryptedFile()
    │     - GET api/storenode/list → chọn N node (N = REPLICATION_FACTOR, mặc định 2)
    │     - Với mỗi Store node (primary + replicas):
    │         • POST /api/file/upload-metadata-raw
    │         • POST /api/file/upload-file-block-raw
    │     - Signed: POST /api/storedfile/register-replicas
    │         { fileId, ownerPublicKey, storeNodeIds[], fileHash, fileSize }
    │
    ▼
  [Store Node 1..N]  ◀─── cùng metadata + blocks (encrypted)
    │
    ▼
  [Central API] - index N hàng StoredFile (cùng fileId, khác storeNodeId)
    │
    │  3. Rekey Sync (nếu followers)
    │     RekeySyncService.syncFollowersAndGenerateRekeys()
    │     - GET /api/user/new-followers
    │     - Generate rk(A→B) locally (PRE FFI)
    │     - POST /api/policy/upload-rekeys-batch (signed)
    │
    ▼
  [Central API] - lưu rekeys (MySQL / JSON)
```

### 3.2.1 Phân tán nội dung: N-of-M (MVP)

| Khái niệm | Hiện tại |
|-----------|----------|
| **Mô hình** | Full replica trên N Store node (không DHT / không erasure coding) |
| **Orchestrator** | App chọn node từ `storenode/list`; Central API chỉ **index** placement |
| **Factor** | `AppConstants.replicationFactor` / `--dart-define=REPLICATION_FACTOR=` (default **2**) |
| **Index** | Nhiều bản ghi `StoredFile` cùng `FileId`, khác `StoreNodeId` |
| **Đọc** | Client có thể lấy bất kỳ node nào đang giữ file (discovery qua API) |
| **Khác DHT** | Không peer discovery / không shard chunk giữa node — đủ cho MVP, dễ audit |

```
[App] ──encrypt──▶ ciphertext (fileId)
         │
         ├── upload ──▶ Store A
         ├── upload ──▶ Store B   (N = replicationFactor)
         └── signed register-replicas ──▶ Central API index
```


### 3.3 Luồng đọc feed (Following)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  LUỒNG ĐỌC FOLLOWING FEED                                                        │
└─────────────────────────────────────────────────────────────────────────────────┘

  [App - FollowingFeedService]
    │
    │  1. GET api/storenode/list  → danh sách endpoints
    │
    │  2. Với mỗi Store Node:
    │     GET {endpoint}/api/post/followers-feed
    │     Headers: X-User-PubKey, X-Timestamp, X-Signature
    │
    ▼
  [Store Node]
    │  - Gọi Central API: GET /api/user/following?userPubKey=...
    │  - Lọc posts có ownerPubKey trong following
    │  - Trả về posts (metadata + PRE fields nếu có)
    │
    ▼
  [App]
    │  3. Với mỗi post:
    │     - Public: tải block, parse JSON
    │     - ECIES: decrypt với sk_user
    │     - PRE: PreService.fetchTransformToken() → requestProxyReencrypt()
    │            → decapsulateAndRecoverKey() → decrypt blocks
    │
    ▼
  [Hiển thị FollowingPost]
```

### 3.4 Sơ đồ tổng thể kết nối

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
             │   GET storenode/list              │   POST upload-*-raw        │
             │   POST storedfile/register-replicas│  GET post/followers-feed  │
             │   GET user/*, policy/* (signed)   │   GET file/block/*         │
             │   POST /api/tx/submit (signed)    │                            │
             │                                   │   POST StorageOperation     │
             │                                   │   + contract → Block Creator│
             │                                   │   Blocker → API: decision   │
             │                                   │   Blocker pull: X-Internal-Token │
             └───────────────────────────────────┴────────────────────────────┘

### 3.5 Luồng Tx trực tiếp tới Block Creator (luồng mới)

```
[Store] ── POST StorageOperation + Contract ──▶ [Blocker]
  │                                             │
  │                                             ├─ POST /api/blockcreatornode/decision (Central API)
  │                                             │    ↳ nhận decision + signature
  │                                             ├─ verify selection + verify contract signature
  │                                             └─ accept tx → mempool
  │
  └─ (Central API chọn blocker + ký decision; tx pull dùng InternalApi token)
```

---

## 4. Mô hình bảo mật

### 4.1 Xác thực request (`SignatureAuthHelper`)

- **Format ký:** `METHOD + path+query + TIMESTAMP + sha256hex(body)` (POST/PUT/PATCH)
- **Headers:** `X-User-PubKey`, `X-Timestamp`, `X-Signature`
- **Replay:** Timestamp trong cửa sổ **5 phút**
- **Áp dụng:** Policy upload-rekey(s), StoredFile register / register-replicas, Tx submit, …
- **User đã đăng ký:** hầu hết endpoint yêu cầu pubkey đã có trong registry (tx submit có thể nới cho đăng ký mới)

### 4.1.1 Internal service token

- Header: `X-Internal-Token`
- Config: `InternalApi:Token` hoặc env `INTERNAL_API_TOKEN`
- Dùng cho: `GET /api/tx/pull`, `POST /api/policy/validate-token` (Store → API)

### 4.1.2 Voucher đăng ký node (atomic)

- Store / Block Creator đăng ký bằng voucher **one-shot**
- API: `TryMarkVoucherUsedAsync` — MySQL `UPDATE … WHERE Used=0` (chỉ 1 winner)
- Không hard-code voucher trong `appsettings` đã commit; dùng env / user-secrets

### 4.1.3 CORS

- Production: chỉ origin trong `Cors:AllowedOrigins` (fail-closed nếu trống)
- Development: có thể `AllowAnyOrigin` khi chưa cấu hình

### 4.2 Blocker Selection Decision (Payload + Signature)

**Purpose:** Central API trả về quyết định chọn Block Creator cho một tx; Blocker chỉ nhận tx nếu xác minh chữ ký hợp lệ và mình là người được chọn.

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

### 4.3 Mã hóa nội dung

| Loại | Cơ chế | Áp dụng |
|------|--------|---------|
| Public | Không mã hóa | shareType=public |
| Me/Private | ECIES(K, pkOwner) | shareType=me |
| Followers (ECIES) | encryptedKey per recipient | shareType=followers (Option 1) |
| Followers (PRE) | encapsulateWithTag + rekey | shareType=followers (Option 2) |

### 4.4 PRE (Option 2 - Delegated)

- Author tạo rekey rk(A→B) client-side
- Upload batch lên Central API (signed)
- Follower: PoP (sign nonce) → fetch rekey → client re-encrypt → decapsulate
- Store validate PRE token qua Central với `X-Internal-Token`

---

## 5. Cấu hình mặc định

| Service | URL/Port / ghi chú |
|---------|----------|
| Central API | http://localhost:5002 — MySQL + `INTERNAL_API_TOKEN` |
| Store Node | http://localhost:5000 hoặc 5001 — `STORE_VOUCHER`, `InternalApi:Token` |
| Block Creator | mặc định ~5003 — `VOUCHER`, `INTERNAL_API_TOKEN` |
| App API Base | `CENTRAL_API_BASE=http://127.0.0.1:5002/api` |
| Replication | `REPLICATION_FACTOR` (default 2) |

---

## 6. Dependency Graph (tóm tắt)

```
deltanium-app
  ├── Central API (HTTP) - registry, index N-of-M, policy, tx submit
  ├── Store Nodes × N (HTTP) - full replicas
  └── deltanium-core/native (Umbral PRE FFI)

deltanium-store
  ├── Central API (HTTP) - following, validate-token (+ InternalApi)
  └── Local / MySQL metadata + file blobs

deltanium-api
  ├── MySQL (preferred) / JSON fallback
  └── Secrets: env + ~/.deltanium (không commit)

deltanium-blocker
  ├── Central API - decision, registration, tx pull (+ InternalApi)
  └── MySQL / JSON mempool & blocks
```

---

*Cập nhật: P0 secrets / P1 auth+voucher+CORS+InternalApi / P2 N-of-M replication (App + StoredFile index). Nguồn: deltanium-api, deltanium-app, deltanium-store, deltanium-core, deltanium-blocker.*
