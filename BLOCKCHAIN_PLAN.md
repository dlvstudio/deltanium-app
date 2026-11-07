# Blockchain Plan

This document summarizes what already exists and what remains to be built
to reach the end-to-end blockchain flow described in the proposal.

## Current Sources of Truth
- `BLOCKCHAIN_PROPOSAL.md`: canonical architecture + flow + transaction schema.
- `BLOCKCHAIN_IMPLEMENTATION.md`: implementation notes (partial).
- `BLOCK_CREATOR_NODE_DETAILS.md`: block creator flow details.
- `../deltanium-core/README.md`: network architecture, consensus, PRE support.
- `../deltanium-store/README.md`: off-chain storage + PRE/ECIES flows.
- `../deltanium-api/README.md`: central API flows (users, nodes, rekeys).
- `../deltanium-blocker/README.md`: blocker MVP flow + constraints.

## What Already Exists (Implemented)
### App (`deltanium-app`)
- Local keypair + mnemonic generation, signed registration.
- Encrypted content upload to Store (raw metadata + blocks).
- PRE hybrid flow on client (Umbral PRE via FFI).
- Storage node discovery via Central API.
- **Social Actions (React/Comment):** Đã hoàn thành tích luồng StorageContract đầy đủ. App thực hiện thương lượng phí (`prepare...WithStorageCost`), hiển thị popup xác nhận (`ConfirmStorageCostDialog`), ký hợp đồng, và sau đó Store tự động submit `StorageOperation` lên blockchain. Luồng này thay thế việc gọi `submitTx` trực tiếp từ App, đảm bảo Store được thanh toán và giao dịch được xác thực.✅

### Central API (`deltanium-api`)
- User registration + follow graph.
- Store node registration + voucher validation.
- Stored file indexing endpoints.
- PRE rekey upload/fetch (Option 3).
- Blocker selection and authorization signing (no tx relay).

### Store Node (`deltanium-store`)
- Encrypted file metadata + block upload APIs.
- Followers feed + PRE capsule fields.
- Signature verification middleware (for legacy endpoints).
- **Social query APIs:** `GetReactions`, `RemoveReaction`, `GetComments`, `DeleteComment`, `GetUserPosts` hoạt động dựa trên metadata lưu trữ local tại Store (off-chain, không đối chiếu blockchain).

### Block Creator Node (`deltanium-blocker`)
- Block creation loop with coordinator slot check.
- Basic validation + in-memory chain state.
- Persistence to `blocks.json` (recent addition).
- Voucher-based registration with Central API.
- Direct tx intake from app + mempool persistence (`mempool.json`).
- Tx signature verification on blocker before mempool accept.
- **Kiến trúc Web API Core:** Chuyển đổi hoàn toàn sang kiến trúc ASP.NET Core Web API chuẩn với Controllers, Dependency Injection và Middleware.
- **Hệ thống Logging chi tiết:** Tích hợp Serilog để ghi log ra console và file log (`blocker-YYYYMMDD.log`) với mức độ chi tiết cao hơn, bao gồm cả lỗi và cảnh báo.
- **Xử lý lỗi toàn cục:** Triển khai `ExceptionHandlingMiddleware` để bắt và ghi log mọi ngoại lệ chưa được xử lý, trả về phản hồi lỗi JSON tiêu chuẩn.
- **Dịch vụ xác thực giao dịch:** Di chuyển logic xác thực `StorageOperation` và xây dựng thông điệp hợp đồng vào `TransactionValidationService` để tách biệt trách nhiệm.
- **Hỗ trợ Fee thập phân:** Cập nhật `BlockerTxRequest` để nhận `Fee` dưới dạng `string` và `Transaction` để lưu `Fee` dưới dạng `decimal`, cùng với logic parse/validation trong `TxController`.

### Core (`deltanium-core`)
- Core cryptography + PRE library (native `umbral_pre`).
- Supporting types/tools used by app/API.

### App tx submission (MVP wiring)
- App sends signed tx directly to selected Block Creator.
- **Tx types App actually submits:** `Follow`, `Unfollow` only (via `user_discovery_service.dart` → `BlockchainTxService.submitTx`). Fee as string (F10) ✅
- **Not sent by App:** `UserRegistration` (registration chỉ gọi Central API, không gửi tx lên Blocker), `CreatePost` (chỉ upload lên Store → Store gửi StorageOperation; không có tx CreatePost riêng với postId/fileId/storageNodeId như trong proposal).

### Store tx submission (Current)
- **Contract Negotiation:**
  1. App requests contract terms (files, duration).
  2. Store returns proposal with calculated fee.
  3. User confirms fee in App UI.
  4. App signs contract proposal.
  5. Store validates App signature and co-signs with Node key.
- **Blockchain Submission:**
  - Store submits a single `StorageOperation` tx (containing the fully signed StorageContract) to the selected Block Creator.
  - The Block Creator validates both signatures (App and Store) on the contract before inclusion.
  - App does **not** call `SubmitBlockchainTransactionAsync` or `/api/tx/submit` directly.
- **Định dạng TotalFee chuẩn xác:** Đã sửa lỗi trong `BlockchainService.cs` để đảm bảo `totalFee` và `fee` trong transaction body được định dạng chính xác thành chuỗi "F10" (`0.0000000000`) bằng `CultureInfo.InvariantCulture`, giải quyết vấn đề chữ ký và deserialization.
- **Hỗ trợ React/Comment:** Đã mở rộng `FileController` trong Store để chấp nhận và submit blockchain cho các loại file "react" và "comment" thông qua `StorageOperation`.✅

## ✅ Bugs Fixed
### Bug 1: Fee type mismatch (App ↔ Blocker)
- **Status:** Resolved ✅
- **Fix:** Cập nhật `blockchain_tx_service.dart` gửi `fee` là `string`.

### Bug 2: Comment (public) thiếu gọi `submitTx`
- **Status:** Resolved ✅
- **Fix:** (Đã thay thế bằng luồng StorageContract đồng nhất, Store tự submit tx).

### Bug 3: Store Filter Skip React/Comment
- **Status:** Resolved ✅
- **Fix:** Loại bỏ filter `type == 'post'` trong `FileController.TrySubmitStorageContractAsync`, cho phép submit StorageOperation cho cả React và Comment.

### Bug 4 (đã xử lý): Block slot authorization mock
- **Trước:** `CentralCoordinatorClient` dùng mock (không gọi Central API), trả về `central-signed(auth:...)` giả.
- **Hiện tại:** Blocker gọi thật `POST /api/blockcreatornode/block-slot`; Central chọn ngẫu nhiên một blocker từ danh sách active, ký payload (SHA256 của message), trả về signature + centralPublicKey. Blocker verify chữ ký với trusted Central pubkey và chỉ tạo block khi `granted == true`.

### Luồng hiện tại (truy vết chi tiết)
```
Follow/Unfollow (App → Blocker):
1. App: UserDiscoveryService.followUser() / unfollowUser()
   ├─ POST /api/user/follow hoặc /api/user/unfollow → Central API ✅
   └─ BlockchainTxService.submitTx(type: 'Follow'|'Unfollow', fee: 1) → Blocker ✅
       └─ Blocker: TxController → Decision → Verify signature → mempool → block

Post / React / Comment / Chat (Store → Blocker, StorageOperation):
1. App upload metadata + blocks lên Store; App ký contract, Store co-sign.
2. Store: FileController.TrySubmitStorageContractAsync() → BlockchainService.SubmitStorageOperationAsync()
   ├─ fee = contract.TotalFee.ToString("F10") ✅
   ├─ POST /api/tx/submit → Blocker
   ├─ Blocker: TxController → Decision → ValidateStorageOperation (contract hash + signatures) → mempool
   └─ NodeHost.RunBlockCreationLoop() → RequestBlockSlot (Central) → BuildBlock → Validate → AddBlock → blocks.json ✅
```

## Đánh giá lộ trình chuyển đổi Blockchain (Rà soát)

**Kết luận:** Lộ trình đã hoàn thành **MVP/prototype** cho luồng chính (storage contract → block). **Chưa hoàn thành** chuyển đổi đầy đủ thành hệ thống blockchain có state từ chain; còn thiếu indexer, P2P, consensus thật, và kinh tế D-Coin.

### Đã triển khai (theo proposal)

| Hạng mục | Proposal | Hiện trạng |
|----------|----------|------------|
| Transaction types (schema) | 2.2.1–2.2.10 | Blocker chấp nhận đủ 10 loại; App chỉ gửi Follow/Unfollow; Store gửi StorageOperation (post/react/comment/chat). |
| Block structure + Merkle | 2.3 | BlockBuilder + BlockValidator, NodeState (blocks.json). |
| Central coordination | 2.4 | Central API: decision (tx) + block-slot (ký SHA256), Blocker verify với Central pubkey. |
| Storage contract on-chain | 2.2.8, envelope | Store submit StorageOperation với contract (hash + appSignature + storageNodeSignature + content); Blocker validate envelope. |
| Post/React/Comment on-chain | StorageOperation | Post, react, comment, chat_message đều qua StorageContract → StorageOperation → blocks. |
| Follow/Unfollow on-chain | 2.2.2, 2.2.3 | App gửi Follow/Unfollow tx sau khi API thành công. |
| Node registry (Block Creator) | 2.2.7, 2.7.2 | Central: blockcreator_nodes.json, voucher, decision + block-slot. |
| Content Store (Store node) | 2.7.3 | Store: upload encrypted, StorageOperation với contract. |

### Chưa triển khai / Khác biệt so với proposal

| Hạng mục | Ghi chú |
|----------|--------|
| **UserRegistration tx** | Proposal: user_registration tx on-chain. Hiện tại: App chỉ gọi API `/api/user/register`; không gửi UserRegistration tx lên Blocker. |
| **CreatePost tx** | Proposal: create_post tx với postId, fileId, storageNodeId. Hiện tại: chỉ có StorageOperation (Store gửi) chứa contract + fileId; không có tx CreatePost riêng từ App. |
| **State từ blockchain** | Proposal: global state (user registry, follow, post refs) từ chain. Hiện tại: API/Store vẫn là source of truth (users.json, user_follows.json, metadata local); **không có indexer** rebuild state từ blocks. |
| **Persistence** | Tất cả service dùng JSON (users, blocks, mempool). Chưa chuyển sang DB. |
| **P2P / Gossip** | Chưa có; chỉ HTTP qua Central. |
| **Consensus** | Central chọn blocker **ngẫu nhiên**; chưa PoA/PoS hoặc round-robin xác định. |
| **Inspector / Router nodes** | Proposal có 5 loại node; chỉ Block Creator + Content Store (Store) đang dùng; Inspector, Router chưa có. |
| **D-Coin, Transfer, Donate** | Schema có; chưa có balance state, reward distribution, hay ví. |

### Tóm tắt: Còn thiếu cần làm

1. **Phase 1 (Ground truth):** Blockchain Indexer rebuild state từ blocks; thay JSON bằng DB; semantic validation (user đã đăng ký, postFileId tồn tại...).
2. **Phase 2 (Mạng):** P2P gossip (tx + block propagation); consensus xác định (PoA/round-robin); node discovery.
3. **Phase 3 (Kinh tế & bảo mật):** D-Coin, fee distribution, Transfer/Donate; secure wallet; audit PRE/signing.
4. **Tùy chọn:** App gửi UserRegistration tx sau khi đăng ký API; gửi CreatePost tx (reference) sau khi Store đã nhận file — để chain có đầy đủ audit trail theo proposal.

---

## Production Readiness Assessment (Current Status: MVP/Prototype)

Based on a comprehensive analysis of the current ecosystem, the following critical gaps must be addressed before production deployment:

### 🚩 Critical Gaps

1.  **Persistence Layer**: 
    - **Current**: Services (`api`, `blocker`, `store`) use JSON files (`users.json`, `blocks.json`).
    - **Requirement**: Migrate to a robust database (e.g., PostgreSQL or MongoDB) for ACID compliance and performance.
2.  **Consensus Mechanism**:
    - **Current**: Leader selection is randomized or placeholder in the coordinator.
    - **Requirement**: Implement a deterministic consensus protocol (e.g., PoA or PoS).
3.  **P2P Networking**:
    - **Current**: Point-to-point HTTP communication via coordinator.
    - **Requirement**: Implement gossip protocols (e.g., `libp2p`) for cross-node transaction and block propagation.
4.  **State Reconciliation (Indexer)**:
    - **Current**: Authoritative state is maintained in API local storage, not derived from blockchain.
    - **Requirement**: Build an indexer to rebuild the social graph from the transaction ledger.
5.  **Economic Model Integration**:
    - **Current**: Fees are calculated but not linked to a functional coin economy.
    - **Requirement**: Automate reward distribution and integrate `Transfer`/`Donate` transactions.

---

## 🗺️ Production Roadmap

### Phase 1: Infrastructure Robustness
- [ ] Replace JSON storage with an indexed database in all backend services.
- [ ] Implement a **Blockchain Indexer** to reconstruct state from block history.
- [ ] Implement **Semantic Validation** in Blocker nodes (e.g., checking user balances).

### Phase 2: Decentralization
- [ ] Implement **P2P Gossip** for transaction and block propagation.
- [ ] Replace the central coordinator with a **Decentralized Consensus** mechanism.
- [ ] Enable dynamic **Node Discovery** via P2P.

### Phase 3: Final Security & Economy
- [ ] Implement secure wallet storage (Keychain/Keystore) in the app.
- [ ] Integrate **D-Coin Rewards** and fee distribution automation.
- [ ] Full security audit of PRE and cryptographic signing implementations.

---

## Storage Contract Flow (new)

To ensure Storage Nodes are paid and committed before uploads, introduce a signed Storage Contract between App (file owner) and Storage Node. Key points:

- App and Storage Node negotiate terms (startDate, endDate or open-ended, totalFileSize, totalFee, fileIds).
- **Sign on contract hash (current):** Both parties sign the **contract hash** instead of a compact message. A canonical representation of the contract (content fields only, no signatures) is hashed with SHA-256 and encoded as lowercase hex; that string is what App and Store sign. The contract object carries `contractHash`, `appSignature`, and `storageNodeSignature`. The field `messageToSign` is deprecated and kept only for backward compatibility with older transactions.
  - Contract is created off-chain between the App and Storage Node; registering the contract in Central API is optional and not required. The authoritative proof of the contract is the jointly-signed contract object (with `contractHash` and both signatures) that travels with the `StorageOperation` transaction.
  - App uploads files only after the contract is signed by both parties.
  - Storage Node creates the `StorageOperation` transaction (not the App). The `StorageOperation` must include `contractId` and carry the full contract object (including `contractHash`, `appSignature`, `storageNodeSignature`), `fileIds`, `blockId` (storage locator), fee amount. The App must cosign (cosignature field) to prove acceptance.
  - Block Creator (blocker) validates `StorageOperation` by recomputing the contract hash from the contract payload, ensuring it matches `contractHash`, and verifying both signatures against `contractHash`; it also confirms fee equals `contract.totalFee` and `fileSize`/`fileIds` fit within contract terms. Blockers MUST NOT assume the contract is stored in Central API and therefore should rely on the signed proof supplied in the tx rather than querying a central contract index.

This flow ensures Storage Nodes are active participants (they create the storage tx), contracts are provable on-chain, and fee distribution follows the contract.

### Storage Contract: Sign on Contract Hash (spec)

- **Goal:** Sign the hash of the contract instead of a hand-built message, so schema changes and formatting stay consistent across App, Store, and Blocker.
- **Canonical contract (for hashing):** Only content fields, alphabetical key order, no whitespace. Fields: `appPublicKey`, `contractId`, `contractType`, `createdAtUnix`, `endDateUnix` (omit if OpenEnded; when present use number), `fileIds` (array, sorted alphabetically), `startDateUnix`, `status`, `storageNodePublicKey`, `totalFee` (string, F10 e.g. `"0.0000000000"`), `totalFileSize`. Exclude `messageToSign`, `contractHash`, `appSignature`, `storageNodeSignature`.
- **Hash:** `contractHash = toLowerCase(hex(SHA256(utf8(canonicalJson))))`. All three sides (App, Store, Blocker) use the same canonical JSON and encoding.
- **Signing:** App and Store each sign the string `contractHash`; Blocker verifies that the payload’s `contractHash` matches the recomputed hash and verifies App (and optionally Store) signature over `contractHash`.
- **Backward compatibility:** Transactions that only have `messageToSign` (no `contractHash`) can be validated with the legacy path (build message, verify signature on message) until deprecated.

### Contract signing versions (V1 vs V2)

Two contract-signing versions are supported so that blocks can be created while V2 canonical hash is aligned across App/Store/Blocker:

- **V1 (sign message):** App and Store sign the **message** string (`TimeFixed|start|end|appPubKey|storagePubKey|totalFee F10|totalFileSize` or `OpenEnded|...`). Blocker validates using the legacy path (build message from contract, verify signature on message). **Default in App** so that new posts create blocks. Request: `messageToSign` + `appSignature` + `signingVersion: 1`.
- **V2 (sign contract hash):** App and Store sign the **contract hash** (SHA-256 of canonical JSON). Blocker validates by recomputing hash and verifying signatures. Use when canonical hash is fixed across all three. Request: `appSignature` + `signingVersion: 2` (Store computes hash and verifies).

App uses V1 by default (`StorageContractService.defaultSigningVersion = 1`). To use V2, call `approveAndSignContract(..., signingVersion: 2)`.

### Contract envelope format (StorageOperation tx payload)

When Store submits a `StorageOperation` to the Blocker, the contract is sent in **envelope** form so the Blocker does not depend on a fixed contract schema:

- **Envelope shape:** `{ hash, appSignature, storageNodeSignature, content }`
  - `hash`: SHA-256 (hex) of canonical JSON of `content` (Store and App use the same canonical serialization).
  - `appSignature` / `storageNodeSignature`: Signatures over the string `hash` (not over the raw content).
  - `content`: **Dynamic** JSON object; schema is defined by Store/App. Blocker only requires two fields for verification: `appPublicKey` and `storageNodePublicKey`. All other fields (e.g. `status`, `startDateUnix`, `endDateUnix`, `contractType`, `totalFee`, custom fields) are opaque to the Blocker.
- **Blocker validation (envelope path):** Verifies that both parties signed the received `hash`; checks `req.From` / `req.To` match `content.appPublicKey` / `content.storageNodePublicKey`. Blocker does **not** validate `status`, `startDateUnix`, `endDateUnix`, or `contractType`; contract “validity window” and business rules are enforced by Store/App when creating and signing.

### Blocker: local dev and logging

- **USE_LOCAL_DECISION:** If the Central Decision API is unavailable, set env `USE_LOCAL_DECISION=true` so the Blocker accepts transactions without a decision and continues running (registration failure is logged as warning instead of exiting). Use for local/dev when Central API is not running.
- **Mempool logging:** When a transaction is added to the mempool, Blocker logs `[MEMPOOL] Added tx {TxId}, pool size={Count}` and `Accepted transaction {TxId} of type {Type}`. Log files: `deltanium-blocker/logs/blockerYYYYMMDD.log`.
- **Timestamp / fee:** Blocker accepts `timestamp` as number or string (JSON) and uses a fallback to current time if missing/invalid; `fee` is parsed as string (e.g. F10) to avoid precision issues.

## Chosen Architecture (Current)
- **Tx ingestion:** App submits signed tx directly to selected Block Creator. Store submits `StorageOperation` tx separately.
- **Mempool:** Stored in Block Creator node (`mempool.json`).
- **Selection check:** Blocker asks Central API if it is selected for the tx; API returns a signed decision.
- **Acceptance rule:** Blocker accepts tx only when the signed decision confirms selection.
- **Relay:** No tx relay; Central API only selects blocker and signs the authorization.
- **Persistence:** JSON files (`blocks.json`, `mempool.json`, `transactions.json`).
- **Tx types:** All proposal types accepted (UserRegistration → Donate).

## How Central API selects a blocker
- **Data source:** Central API lấy danh sách **active** block creator nodes từ storage (`GetActiveBlockCreatorNodesAsync()`).
- **Decision (nhận tx):** `POST /api/blockcreatornode/decision` — chọn **một** blocker ngẫu nhiên: `selected = nodes[new Random().Next(nodes.Count)]`; `selected == true` chỉ khi `request.BlockerPubKey` trùng `selected.PublicKey`. Mỗi request chọn lại ngẫu nhiên.
- **Block-slot (tạo block):** `POST /api/blockcreatornode/block-slot` — cùng cơ chế: chọn một node ngẫu nhiên từ danh sách active; `granted == true` chỉ khi `request.BlockerPubKey` trùng node được chọn. Blocker chỉ tạo block khi nhận được `granted == true` và verify chữ ký thành công.
- **Tương lai:** Có thể thay random bằng consensus (ví dụ PoA / round-robin) — xem Phase 2 trong Roadmap.

## Decision Format (Selection Signature)
- **Payload:** `txId`, `blockerPubKey`, `selected`, `issuedAt`, `expiresAt`, `nonce`
- **Message (plain text):** `DECISION|txId|blockerPubKey|selected|issuedAt|expiresAt|nonce`
- **Signing:** Central API **ký vào hash** (SHA256 của message), không ký raw message. `KeyService.SignDecision(message)` → SHA256(message) → ECDSA sign hash → Base64(DER). Blocker verify bằng cách hash lại message và verify chữ ký với hash đó (`SignatureVerifier.Verify`).
- **Verify:** time window valid, `selected == true`, pubkey matches, signature valid. **Blocker must** lưu Central API public key (`CENTRAL_API_PUBLIC_KEY` env, hoặc `node_info.json` / fetch từ `GET /api/blockcreatornode/decision-key`) và verify decision bằng trusted key đó.

## Block-slot and block signatures
- **Block slot:** Blocker gọi `POST /api/blockcreatornode/block-slot` với `blockerPubKey`. Central ký message `BLOCK_SLOT|blockerPubKey|issuedAt|expiresAt|nonce|granted` (ký SHA256 của message, cùng cách decision). Blocker verify chữ ký với trusted Central pubkey và chỉ tạo block khi `granted == true`.
- **Block:** Mỗi block gồm: `CentralAuthorizationSignature` (chữ ký Central từ block-slot response), `CentralApiPublicKey` (pubkey Central đã ký slot, lưu trong block để biết ai ủy quyền), `CreatorSignature` (Blocker ký ECDSA lên block id = SHA256(`previousId:height:timestamp:merkleRoot:creatorPublicKey`)), và `Version` (phiên bản block format, ví dụ `"1.0.0"`, đọc từ Blocker config `BlockVersion` trong appsettings). BlockValidator verify CreatorSignature với CreatorPublicKey.
- **Blocker config:** Central API URL lưu trong `appsettings.json` (`CentralApiUrl`, ví dụ `http://localhost:5002`) hoặc env `CENTRAL_API_URL`. Central API public key lưu trong `node_info.json` (`CentralApiPublicKey`) hoặc env `CENTRAL_API_PUBLIC_KEY`. Block version trong appsettings `BlockVersion` (ví dụ `"1.0.0"`).

## Optional Enhancements
- Real cryptographic signing + validation in all layers.
- Metrics/health endpoints for nodes.
- Automated PRE library build/packaging for app targets.

## Gap vs Common Blockchain Architectures
### Bitcoin-like (PoW, UTXO)
- Missing PoW, difficulty adjustment, UTXO model, P2P gossip, and fork resolution.
- Current system only has basic blocks + txs without UTXO validation rules.

### Ethereum-like (Account/State)
- Missing deterministic state transition, nonce, gas/fee model, receipts/logs, and state trie/DB.
- Tx schema exists, but no canonical state reducer or execution engine.

### PoA / PoS (Permissioned)
- Coordinator exists (leader selection), but no validator set management, slashing/penalties, or finality rules.
- No multi-node consensus or quorum validation.

### Hyperledger-style (Ordering + Endorsement)
- Central API can act as ordering/relay, but no endorsement policies, commit phase, or chaincode/state DB.

### Event-log + Off-chain Storage
- Off-chain content storage is implemented, but missing canonical on-chain indexing and data availability rules.

## Review: App ↔ Store ↔ Blocker Flow (Current vs Plan)
### Log file locations
Các file log mới cùng nằm trong các folder sau (theo từng service):
- **App:** `deltanium-app/appLogs/app-YYYYMMDD.log`
- **Store:** `deltanium-store/logs/store-YYYYMMDD.log`
- **Blocker:** `deltanium-blocker/logs/blockerYYYYMMDD.log` (hoặc `blocker-YYYYMMDD.log`)

Khi truy vết lỗi (ví dụ block chưa tạo, StorageOperation, contract signing) mở đúng ngày trong từng folder tương ứng.
### Observations (What Works Now)
- App → Store upload flow works end-to-end (metadata + blocks).
- Store submits `StorageOperation` to Blocker with `totalFee` formatted as F10 string.
- Blocker now runs as Web API Core with structured logging and global exception handling.
- Blocker accepts `fee` as string and converts to `decimal` for internal use.
- Store retries `StorageOperation` submission with backoff on transient failures.
- App surfaces blockchain submission failures to the user after upload.
- Blocker exposes `/health` and `/metrics` endpoints for basic monitoring.
- Added a basic serialization test for `BlockerTxRequest` fee handling.### Remaining Gaps / Improvements
#### Schema Consistency
- **Unify tx schema types:** `fee` should be consistently a string (F10) in all JSON payloads; internal models should use `decimal` but be derived from the string to avoid precision drift.
- **Contract schema alignment:** ensure `StorageContract` fields are stringified consistently (`startDateUnix`, `endDateUnix`, `totalFileSize`, `totalFee`) across app/store/blocker.
- **Sign payload alignment:** verify the app/store/blocker use identical formatting (especially for decimals and ordering) to prevent signature mismatches.

#### Blocker Reliability
- **Expand metrics:** include mempool size and block height counters.
- **Add request logging** for `/api/tx/submit` (sanitized) to improve traceability.

#### Store Improvements
- **Circuit breaker** or fallback when blocker is unavailable.

#### App Improvements
- **Retry strategy** when store reports tx submission failure.

#### Tests / Validation
- [x] Chat Integration (File-based)
  - Uses `StorageContract` for session-based message bundles.
  - Recorded as `StorageOperation` on-chain.
  - Integrated with `ChatService` and `FileController`.
- [x] Blocker: envelope validation and dynamic content (see `deltanium-blocker.Tests`: `TransactionValidationServiceTests`, `BlockerTxRequestTests`).
- Add integration test covering: App → Store → Blocker with `fee` as F10 string.
- Add serialization tests for `StorageContract` + `StorageOperation` messageToSign consistency.

## Proposed Roadmap for Full Blockchain Social Network

### Phase 0: Bug Fixes & Architecture Alignment ✅ Hoàn thành
1. Fix fee type mismatch trong `BlockchainTxService` (App → Blocker). ✅
2. Tích hợp luồng StorageContract cho React/Comment (App ↔ Store). ✅
3. Thêm fee confirmation popup cho React/Comment UI. ✅
4. Verify React/Comment thông qua `StorageOperation` xuất hiện trong `blocks.json`. ✅
5. Luồng hiện tại: Follow/Unfollow (App → Blocker); Post/React/Comment/Chat (Store → Blocker qua StorageOperation). ✅

### Phase 1: State Reconciliation (Ground Truth)
1. **Blockchain Indexer/Reducer:** Service quét blocks mới và apply transaction vào database local.
2. **Deep Validation:** Blocker kiểm tra semantic (postFileId tồn tại, user đã đăng ký...).

### Phase 2: Decentralized Network
1. **P2P Gossip:** Propagation cho transactions và blocks giữa các Blockers.
2. **Multi-Blocker Consensus:** Chuyển từ random sang PoA (Proof of Authority).### Phase 3: Incentive & Economy
1. **D-Coin Integration:** Kết nối `Transfer` và `Donate` transactions.
2. **Fee Distribution:** Thưởng phí transaction cho Blockers và phí lưu trữ cho Store nodes.