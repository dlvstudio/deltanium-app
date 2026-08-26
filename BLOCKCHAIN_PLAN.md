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
- **Social Actions (React/Comment):** The full StorageContract flow has been completed. The app negotiates the fee (`prepare...WithStorageCost`), shows a confirmation popup (`ConfirmStorageCostDialog`), signs the contract, and then the Store automatically submits a `StorageOperation` to the blockchain. This flow replaces calling `submitTx` directly from the App, ensuring the Store is paid and the transaction is authenticated.✅

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
- **Social query APIs:** `GetReactions`, `RemoveReaction`, `GetComments`, `DeleteComment`, `GetUserPosts` operate based on metadata stored locally at the Store (off-chain, not cross-checked against the blockchain).

### Block Creator Node (`deltanium-blocker`)
- Block creation loop with coordinator slot check.
- Basic validation + in-memory chain state.
- Persistence to `blocks.json` (recent addition).
- Voucher-based registration with Central API.
- Direct tx intake from app + mempool persistence (`mempool.json`).
- Tx signature verification on blocker before mempool accept.
- **Web API Core architecture:** Fully converted to a standard ASP.NET Core Web API architecture with Controllers, Dependency Injection, and Middleware.
- **Detailed logging system:** Serilog integrated to write logs to the console and log files (`blocker-YYYYMMDD.log`) with a higher level of detail, including errors and warnings.
- **Global error handling:** `ExceptionHandlingMiddleware` implemented to catch and log all unhandled exceptions and return a standard JSON error response.
- **Transaction validation service:** `StorageOperation` validation logic and contract message construction moved into `TransactionValidationService` to separate responsibilities.
- **Decimal fee support:** `BlockerTxRequest` updated to accept `Fee` as a `string` and `Transaction` to store `Fee` as a `decimal`, along with parse/validation logic in `TxController`.

### Core (`deltanium-core`)
- Core cryptography + PRE library (native `umbral_pre`).
- Supporting types/tools used by app/API.

### App tx submission (MVP wiring)
- App sends signed tx directly to selected Block Creator.
- **Tx types App actually submits:** `Follow`, `Unfollow` only (via `user_discovery_service.dart` → `BlockchainTxService.submitTx`). Fee as string (F10) ✅
- **Not sent by App:** `UserRegistration` (registration only calls the Central API, does not send a tx to the Blocker), `CreatePost` (only uploads to the Store → Store sends StorageOperation; there is no separate CreatePost tx with postId/fileId/storageNodeId as in the proposal).

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
- **Accurate TotalFee formatting:** A bug in `BlockchainService.cs` was fixed to ensure `totalFee` and `fee` in the transaction body are formatted exactly as an "F10" string (`0.0000000000`) using `CultureInfo.InvariantCulture`, resolving signature and deserialization issues.
- **React/Comment support:** `FileController` in the Store was extended to accept and submit blockchain transactions for "react" and "comment" file types via `StorageOperation`.✅

## ✅ Bugs Fixed
### Bug 1: Fee type mismatch (App ↔ Blocker)
- **Status:** Resolved ✅
- **Fix:** Updated `blockchain_tx_service.dart` to send `fee` as a `string`.

### Bug 2: Comment (public) missing `submitTx` call
- **Status:** Resolved ✅
- **Fix:** (Replaced by the unified StorageContract flow; Store submits the tx itself).

### Bug 3: Store Filter Skip React/Comment
- **Status:** Resolved ✅
- **Fix:** Removed the `type == 'post'` filter in `FileController.TrySubmitStorageContractAsync`, allowing StorageOperation submission for both React and Comment.

### Bug 4 (resolved): Block slot authorization mock
- **Before:** `CentralCoordinatorClient` used a mock (did not call the Central API) and returned a fake `central-signed(auth:...)`.
- **Current:** The Blocker calls the real `POST /api/blockcreatornode/block-slot`; Central randomly selects one blocker from the active list, signs the payload (SHA256 of the message), and returns the signature + centralPublicKey. The Blocker verifies the signature with the trusted Central pubkey and only creates a block when `granted == true`.

### Current flow (detailed trace)
```
Follow/Unfollow (App → Blocker):
1. App: UserDiscoveryService.followUser() / unfollowUser()
   ├─ POST /api/user/follow or /api/user/unfollow → Central API ✅
   └─ BlockchainTxService.submitTx(type: 'Follow'|'Unfollow', fee: 1) → Blocker ✅
       └─ Blocker: TxController → Decision → Verify signature → mempool → block

Post / React / Comment / Chat (Store → Blocker, StorageOperation):
1. App uploads metadata + blocks to Store; App signs the contract, Store co-signs.
2. Store: FileController.TrySubmitStorageContractAsync() → BlockchainService.SubmitStorageOperationAsync()
   ├─ fee = contract.TotalFee.ToString("F10") ✅
   ├─ POST /api/tx/submit → Blocker
   ├─ Blocker: TxController → Decision → ValidateStorageOperation (contract hash + signatures) → mempool
   └─ NodeHost.RunBlockCreationLoop() → RequestBlockSlot (Central) → BuildBlock → Validate → AddBlock → blocks.json ✅
```

## Blockchain Migration Roadmap Assessment (Review)

**Conclusion:** The roadmap has completed the **MVP/prototype** for the main flow (storage contract → block). The full conversion to a blockchain system whose state comes from the chain is **not complete**; indexer, P2P, real consensus, and D-Coin economics are still missing.

### Implemented (per the proposal)

| Item | Proposal | Current status |
|------|----------|----------------|
| Transaction types (schema) | 2.2.1–2.2.10 | Blocker accepts all 10 types; App only sends Follow/Unfollow; Store sends StorageOperation (post/react/comment/chat). |
| Block structure + Merkle | 2.3 | BlockBuilder + BlockValidator, NodeState (blocks.json). |
| Central coordination | 2.4 | Central API: decision (tx) + block-slot (signs SHA256), Blocker verifies with Central pubkey. |
| Storage contract on-chain | 2.2.8, envelope | Store submits StorageOperation with the contract (hash + appSignature + storageNodeSignature + content); Blocker validates the envelope. |
| Post/React/Comment on-chain | StorageOperation | Post, react, comment, chat_message all go through StorageContract → StorageOperation → blocks. |
| Follow/Unfollow on-chain | 2.2.2, 2.2.3 | App sends Follow/Unfollow tx after the API succeeds. |
| Node registry (Block Creator) | 2.2.7, 2.7.2 | Central: blockcreator_nodes.json, voucher, decision + block-slot. |
| Content Store (Store node) | 2.7.3 | Store: encrypted upload, StorageOperation with contract. |

### Not implemented / Differences from the proposal

| Item | Notes |
|------|-------|
| **UserRegistration tx** | Proposal: user_registration tx on-chain. Current: App only calls `/api/user/register`; does not send a UserRegistration tx to the Blocker. |
| **CreatePost tx** | Proposal: create_post tx with postId, fileId, storageNodeId. Current: only StorageOperation (sent by Store) containing the contract + fileId; no separate CreatePost tx from the App. |
| **State from the blockchain** | Proposal: global state (user registry, follow, post refs) from the chain. Current: API/Store remain the source of truth (users.json, user_follows.json, local metadata); **there is no indexer** that rebuilds state from blocks. |
| **Persistence** | All services use JSON (users, blocks, mempool). Not yet migrated to a DB. |
| **P2P / Gossip** | Not present; HTTP via Central only. |
| **Consensus** | Central selects a blocker **at random**; no deterministic PoA/PoS or round-robin yet. |
| **Inspector / Router nodes** | Proposal has 5 node types; only Block Creator + Content Store (Store) are in use; Inspector and Router do not exist yet. |
| **D-Coin, Transfer, Donate** | Schema exists; no balance state, reward distribution, or wallet yet. |

### Summary: Remaining work

1. **Phase 1 (Ground truth):** Blockchain Indexer rebuilds state from blocks; replace JSON with a DB; semantic validation (user is registered, postFileId exists...).
2. **Phase 2 (Network):** P2P gossip (tx + block propagation); deterministic consensus (PoA/round-robin); node discovery.
3. **Phase 3 (Economy & security):** D-Coin, fee distribution, Transfer/Donate; secure wallet; audit PRE/signing.
4. **Optional:** App sends a UserRegistration tx after API registration; sends a CreatePost tx (reference) after the Store has received the file — so the chain has a complete audit trail per the proposal.

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
- **Data source:** Central API gets the list of **active** block creator nodes from storage (`GetActiveBlockCreatorNodesAsync()`).
- **Decision (receive tx):** `POST /api/blockcreatornode/decision` — randomly selects **one** blocker: `selected = nodes[new Random().Next(nodes.Count)]`; `selected == true` only when `request.BlockerPubKey` matches `selected.PublicKey`. Each request selects again at random.
- **Block-slot (create block):** `POST /api/blockcreatornode/block-slot` — same mechanism: randomly select one node from the active list; `granted == true` only when `request.BlockerPubKey` matches the chosen node. The Blocker only creates a block when it receives `granted == true` and signature verification succeeds.
- **Future:** Random selection can be replaced with consensus (for example PoA / round-robin) — see Phase 2 in the Roadmap.

## Decision Format (Selection Signature)
- **Payload:** `txId`, `blockerPubKey`, `selected`, `issuedAt`, `expiresAt`, `nonce`
- **Message (plain text):** `DECISION|txId|blockerPubKey|selected|issuedAt|expiresAt|nonce`
- **Signing:** Central API **signs the hash** (SHA256 of the message), not the raw message. `KeyService.SignDecision(message)` → SHA256(message) → ECDSA sign hash → Base64(DER). The Blocker verifies by hashing the message again and verifying the signature against that hash (`SignatureVerifier.Verify`).
- **Verify:** time window valid, `selected == true`, pubkey matches, signature valid. **Blocker must** store the Central API public key (`CENTRAL_API_PUBLIC_KEY` env, or `node_info.json` / fetch from `GET /api/blockcreatornode/decision-key`) and verify the decision with that trusted key.

## Block-slot and block signatures
- **Block slot:** The Blocker calls `POST /api/blockcreatornode/block-slot` with `blockerPubKey`. Central signs the message `BLOCK_SLOT|blockerPubKey|issuedAt|expiresAt|nonce|granted` (signs the SHA256 of the message, same as decision). The Blocker verifies the signature with the trusted Central pubkey and only creates a block when `granted == true`.
- **Block:** Each block includes: `CentralAuthorizationSignature` (Central signature from the block-slot response), `CentralApiPublicKey` (the Central pubkey that signed the slot, stored in the block to record who authorized it), `CreatorSignature` (Blocker ECDSA-signs the block id = SHA256(`previousId:height:timestamp:merkleRoot:creatorPublicKey`)), and `Version` (block format version, for example `"1.0.0"`, read from Blocker config `BlockVersion` in appsettings). BlockValidator verifies CreatorSignature with CreatorPublicKey.
- **Blocker config:** Central API URL is stored in `appsettings.json` (`CentralApiUrl`, for example `http://localhost:5002`) or env `CENTRAL_API_URL`. Central API public key is stored in `node_info.json` (`CentralApiPublicKey`) or env `CENTRAL_API_PUBLIC_KEY`. Block version is in appsettings `BlockVersion` (for example `"1.0.0"`).

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
The new log files are in the following folders (per service):
- **App:** `deltanium-app/appLogs/app-YYYYMMDD.log`
- **Store:** `deltanium-store/logs/store-YYYYMMDD.log`
- **Blocker:** `deltanium-blocker/logs/blockerYYYYMMDD.log` (or `blocker-YYYYMMDD.log`)

When tracing errors (for example a block not created, StorageOperation, contract signing), open the matching date in each corresponding folder.
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

### Phase 0: Bug Fixes & Architecture Alignment ✅ Completed
1. Fix fee type mismatch in `BlockchainTxService` (App → Blocker). ✅
2. Integrate the StorageContract flow for React/Comment (App ↔ Store). ✅
3. Add a fee confirmation popup for the React/Comment UI. ✅
4. Verify React/Comment via `StorageOperation` appear in `blocks.json`. ✅
5. Current flow: Follow/Unfollow (App → Blocker); Post/React/Comment/Chat (Store → Blocker via StorageOperation). ✅

### Phase 1: State Reconciliation (Ground Truth)
1. **Blockchain Indexer/Reducer:** A service that scans new blocks and applies transactions to a local database.
2. **Deep Validation:** The Blocker checks semantics (postFileId exists, user is registered...).

### Phase 2: Decentralized Network
1. **P2P Gossip:** Propagation of transactions and blocks among Blockers.
2. **Multi-Blocker Consensus:** Move from random selection to PoA (Proof of Authority).
### Phase 3: Incentive & Economy
1. **D-Coin Integration:** Connect `Transfer` and `Donate` transactions.
2. **Fee Distribution:** Reward transaction fees to Blockers and storage fees to Store nodes.
