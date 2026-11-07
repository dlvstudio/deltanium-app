# Đề Xuất Chuyển Đổi Deltanium Thành Blockchain

## 1. Rà Soát Các Luồng Hiện Tại

### 1.1. Đăng Ký (Registration)

**Luồng hiện tại:**
- Client tạo mnemonic và key pair (secp256k1) local
- Client ký dữ liệu: `email:fullName:dateOfBirth:timestamp`
- Gửi request với signature đến API `/api/user/register`
- API verify signature và lưu user vào `users.json`
- Lưu `Signature` và `RegistrationTimestamp` cho blockchain operations

**Dữ liệu được lưu:**
- PublicKey (identity)
- Email, FullName, DateOfBirth, Bio, AvatarUrl
- Signature (chữ ký đăng ký)
- RegistrationTimestamp

### 1.2. Đăng Nhập (Login)

**Luồng hiện tại:**
- Client không có endpoint đăng nhập riêng
- Sử dụng authentication headers cho mọi request:
  - `X-User-PubKey`: Public key của user
  - `X-Timestamp`: Unix timestamp
  - `X-Signature`: Signature của `method + path + timestamp + bodyHash`
- API verify signature và kiểm tra user đã đăng ký

**Vấn đề:** Không có session, mỗi request đều phải ký

### 1.3. Follow/Unfollow

**Luồng hiện tại:**
- Client tạo follow action: `{"action":"follow","follower":"...","following":"...","timestamp":"..."}`
- Ký action này với private key
- Gửi đến `/api/user/follow` với:
  - SignedData (JSON của action)
  - Signature (chữ ký của SignedData)
  - Timestamp
- API verify signature và lưu vào `user_follows.json`
- Lưu `Signature` và `Timestamp` của follow action

**Dữ liệu được lưu:**
- FollowerPublicKey
- FollowingPublicKey
- Timestamp
- Signature

### 1.4. Viết Bài (Create Post)

**Luồng hiện tại:**
1. **Post với ảnh:**
   - Upload ảnh lên store node (encrypted với ECIES hoặc PRE)
   - Tạo post content (JSON) với metadata về ảnh
   - Encrypt post content
   - Upload metadata và blocks lên store node
   - Post có thể là:
     - `encryptedType: "public"` - không mã hóa
     - `encryptedType: "encrypted"` - mã hóa với ECIES
     - `shareType: "followers"` - chia sẻ cho followers (dùng PRE)

2. **Post text-only:**
   - Tương tự nhưng không có ảnh đính kèm

**Dữ liệu được lưu:**
- FileMetadata với `type: "post"`
- EncryptedKey (ECIES hoặc PRE capsule)
- OwnerPubKey (author)
- EncryptedType, ShareType
- PolicyTag, CapsuleFor, PolicyScheme (cho PRE)

### 1.5. React (Like/Comment)

**Luồng hiện tại:**
1. **Reaction:**
   - Tạo file với `type: "react"`, `parentFileId: postFileId`, `kind: "like|love|laugh|wow|sad|angry"`
   - Public reaction: `isPublic: true`, không mã hóa
   - Encrypted reaction: mã hóa với ECIES cho post owner
   - Upload metadata và block0 lên store node

2. **Comment:**
   - Tạo file với `type: "comment"`, `parentFileId: postFileId`
   - `shareType: "author"` (chỉ author xem) hoặc `"public"` (mọi người xem)
   - Comment có thể có ảnh đính kèm (relatedFiles)
   - Upload metadata và blocks lên store node

**Dữ liệu được lưu:**
- FileMetadata với `type: "react"` hoặc `"comment"`
- ParentFileId (link đến post)
- OwnerPubKey (người react/comment)
- EncryptedKey (nếu encrypted)
- ShareType, EncryptedType

### 1.6. Node Authentication

**Store Nodes:**
- Mỗi store node có mnemonic và key pair riêng
- Đăng ký với API bằng voucher
- Lưu PublicKey và Endpoint vào `nodes.json`
- Store nodes có thể authenticate requests với key của chúng

**API Nodes:**
- Hiện tại chưa có authentication riêng cho API nodes
- API nodes chỉ verify user signatures

## 2. Đề Xuất Giải Pháp Blockchain

### 2.1. Kiến Trúc Tổng Quan (Theo README của deltanium-core)

```
┌─────────────────────────────────────────────────────────────┐
│                    DELTANIUM BLOCKCHAIN                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │     Central Coordination Node (deltanium.com)        │   │
│  │  - Node Registry & Authentication                   │   │
│  │  - Block Creation Scheduler                         │   │
│  │  - Health Monitoring                                │   │
│  └───────────────────┬─────────────────────────────────┘   │
│                      │                                       │
│  ┌───────────────────┼─────────────────────────────────┐   │
│  │                   │                                   │   │
│  │  ┌──────────────┐│┌──────────────┐┌──────────────┐  │   │
│  │  │Block Creator │││Content Store││  Inspector  │  │   │
│  │  │    Nodes     │││    Nodes    ││   Nodes     │  │   │
│  │  └──────┬───────┘│└──────┬──────┘└──────┬───────┘  │   │
│  │         │        │       │              │           │   │
│  │  ┌──────▼──────┐ │ ┌────▼──────┐      │           │   │
│  │  │   Router    │ │ │   User     │      │           │   │
│  │  │   Nodes     │ │ │   Nodes    │      │           │   │
│  │  └─────────────┘ │ └────────────┘      │           │   │
│  │                   │                      │           │   │
│  └───────────────────┼──────────────────────┘           │   │
│                      │                                    │   │
│              ┌────────▼────────┐                          │   │
│              │  P2P Network    │                          │   │
│              │  (Blockchain)   │                          │   │
│              └─────────────────┘                          │   │
│                                                           │   │
│  5 Loại Node:                                             │   │
│  1. Block Creator Nodes: Tạo blocks, validate blocks     │   │
│  2. User Nodes: Tạo transactions, interact với content  │   │
│  3. Content Store Nodes: Lưu trữ encrypted content      │   │
│  4. Inspector Nodes: Audit và verify blocks             │   │
│  5. Router Nodes: Route files đến Content Store nodes   │   │
└───────────────────────────────────────────────────────────┘
```

### 2.2. Transaction Types

Mọi hành động đều là transaction:

#### 2.2.1. UserRegistration Transaction
```json
{
  "type": "user_registration",
  "timestamp": 1234567890,
  "from": "user_public_key",
  "data": {
    "email": "user@example.com",
    "fullName": "User Name",
    "dateOfBirth": "1990-01-01",
    "bio": "...",
    "avatarUrl": "..."
  },
  "signature": "signature_of_data"
}
```

#### 2.2.2. Follow Transaction
```json
{
  "type": "follow",
  "timestamp": 1234567890,
  "from": "follower_public_key",
  "to": "following_public_key",
  "signature": "signature_of_follow_action"
}
```

#### 2.2.3. Unfollow Transaction
```json
{
  "type": "unfollow",
  "timestamp": 1234567890,
  "from": "follower_public_key",
  "to": "unfollowing_public_key",
  "signature": "signature_of_unfollow_action"
}
```

#### 2.2.4. CreatePost Transaction
```json
{
  "type": "create_post",
  "timestamp": 1234567890,
  "from": "author_public_key",
  "data": {
    "postId": "unique_post_id",
    "encryptedType": "public|encrypted",
    "shareType": "me|followers|specific",
    "storageNodeId": "store_node_public_key",
    "fileId": "file_id_on_storage",
    "firstBlockId": "block_id",
    "encryptedKey": "base64_encrypted_key",
    "policyTag": "followers:2025", // optional for PRE
    "tags": ["tag1", "tag2"]
  },
  "signature": "signature_of_post_data"
}
```

#### 2.2.5. React Transaction
```json
{
  "type": "react",
  "timestamp": 1234567890,
  "from": "reactor_public_key",
  "to": "post_author_public_key",
  "data": {
    "postFileId": "post_file_id",
    "kind": "like|love|laugh|wow|sad|angry",
    "storageNodeId": "store_node_public_key",
    "reactionFileId": "reaction_file_id",
    "isPublic": true,
    "encryptedKey": "base64_encrypted_key" // if not public
  },
  "signature": "signature_of_reaction_data"
}
```

#### 2.2.6. Comment Transaction
```json
{
  "type": "comment",
  "timestamp": 1234567890,
  "from": "commenter_public_key",
  "to": "post_author_public_key",
  "data": {
    "postFileId": "post_file_id",
    "commentFileId": "comment_file_id",
    "shareType": "author|public",
    "storageNodeId": "store_node_public_key",
    "firstBlockId": "block_id",
    "encryptedKey": "base64_encrypted_key", // if not public
    "relatedFiles": ["file_id_1", "file_id_2"] // attached images
  },
  "signature": "signature_of_comment_data"
}
```

#### 2.2.7. NodeRegistration Transaction
```json
{
  "type": "node_registration",
  "timestamp": 1234567890,
  "from": "node_public_key",
  "data": {
    "nodeType": "block_creator|content_store|inspector|router",
    "endpoint": "https://node.example.com",
    "voucher": "voucher_code", // for initial registration
    "stake": 1000000 // D coins staked (for Block Creator nodes)
  },
  "signature": "signature_of_node_data"
}
```

#### 2.2.8. StorageOperation Transaction (luồng mới)
```json
{
  "type": "storage_operation",
  "timestamp": 1234567890,
  "from": "content_store_node_public_key",
  "data": {
    "operation": "store_file|delete_file|update_metadata",
    "fileId": "file_id",
    "ownerPubKey": "file_owner_public_key",
    "metadataHash": "hash_of_metadata",
    "storageFee": 100, // D coins paid for storage
    "contract": { ... } // signed StorageContract (App + Store)
  },
  "signature": "signature_of_operation_data"
}
```

#### 2.2.9. Transfer Transaction (D Coin)
```json
{
  "type": "transfer",
  "timestamp": 1234567890,
  "from": "sender_public_key",
  "to": "receiver_public_key",
  "data": {
    "amount": 1000, // D coins
    "fee": 10 // Transaction fee to Block Creator
  },
  "signature": "signature_of_transfer_data"
}
```

#### 2.2.10. Donate Transaction
```json
{
  "type": "donate",
  "timestamp": 1234567890,
  "from": "donor_public_key",
  "to": "content_owner_public_key",
  "data": {
    "contentId": "post_file_id",
    "amount": 500, // D coins
    "fee": 5 // Transaction fee to Block Creator
  },
  "signature": "signature_of_donate_data"
}
```

### 2.3. Block Structure

```json
{
  "blockId": "hash_of_block",
  "previousBlockId": "hash_of_previous_block",
  "timestamp": 1234567890,
  "merkleRoot": "merkle_root_of_transactions",
  "transactions": [
    {
      "txId": "hash_of_transaction",
      "type": "user_registration",
      "timestamp": 1234567890,
      "from": "user_public_key",
      "data": {...},
      "signature": "signature"
    },
    ...
  ],
  "miner": "node_public_key_that_mined_block",
  "nonce": 12345,
  "difficulty": 4
}
```

### 2.4. Consensus Mechanism (Theo README của deltanium-core)

**Central Coordination với Block Creator Selection**

#### Central Coordination
- Central node (deltanium.com) quản lý và authorize các nodes
- Nodes phải được central node authenticate để tạo blocks hoặc store content
- Central node có các chức năng:
  - Authentication Authority: Xác thực nodes
  - Node Registry: Quản lý danh sách nodes
  - Block Creation Scheduler: Chọn Block Creator cho block tiếp theo
  - Health Monitoring: Monitor health của nodes

#### Transaction Processing
- Transactions được broadcast đến tất cả Block Creator nodes
- Central node chọn Block Creator nào sẽ tạo block tiếp theo
- Block Creator được chọn phải tạo block trong thời gian giới hạn
- Nếu không tạo block kịp thời → bị penalty (mất tiền đặt cọc)

#### Block Validation
- Blocks phải được tạo bởi authorized nodes
- Tất cả transactions trong block phải valid
- Block Creator nodes validate blocks mới và signal acceptance
- Nếu invalid, nodes report đến central node và Inspector nodes

#### Inspection Process
- Inspector nodes nhận blocks mới
- Chờ Block Creator validations
- Nếu có reports về issues, re-validate block
- Có thể request block cancellation nếu invalid
- Periodically perform random block audits

### 2.5. State Management

**Global State (Blockchain):**
- User registry (public keys, basic info)
- Follow relationships
- Post references (postId -> storageNodeId, fileId)
- Reaction references
- Comment references
- Node registry (all 5 node types)
- D coin balances (UTXO hoặc Account model)
- Transaction history

**Local State (Content Store Nodes):**
- Actual file content (encrypted)
- File metadata (encrypted)
- Chunks data (files được split thành chunks)
- Merkle tree của chunks

**Local State (Router Nodes):**
- Network topology
- Content Store node availability
- Routing tables
- Performance metrics

**State Transition:**
```
State(t+1) = State(t) + Apply(Block(t+1))
```

### 2.6. Implementation Strategy

#### Phase 1: Transaction Layer
1. Định nghĩa transaction types
2. Implement transaction signing/verification
3. Convert existing actions thành transactions
4. Store transactions locally trước khi broadcast

#### Phase 2: Block Layer
1. Implement block structure
2. Implement Merkle tree for transactions
3. Implement block creation (mining/validation)
4. Implement block validation

#### Phase 3: Network Layer
1. Implement P2P protocol (libp2p hoặc custom)
2. Implement transaction propagation
3. Implement block propagation
4. Implement sync mechanism

#### Phase 4: Consensus
1. Implement validator selection
2. Implement block creation schedule
3. Implement fork resolution
4. Implement finality mechanism

#### Phase 5: Migration
1. Migrate existing data to blockchain
2. Dual-mode operation (old + new)
3. Gradual migration
4. Full blockchain mode

### 2.7. Node Types và Roles (Theo README của deltanium-core)

#### 2.7.1. User Nodes
- **Keys:** User's mnemonic/key pair
- **Role:** Tạo transactions, interact với content
- **Storage:** Local blockchain state (light client hoặc full node)
- **Capabilities:**
  - Create transactions (registration, follow, post, react, comment, transfer, donate)
  - Upload files và create content
  - Perform actions on content (like, love, donate)
  - Transfer D coins to other users
  - Query blockchain state
  - Sync với network

#### 2.7.2. Block Creator Nodes
- **Keys:** Node's mnemonic/key pair (đăng ký với Central Node)
- **Role:** Tạo blocks, validate blocks
- **Storage:** Full blockchain state
- **Requirements:**
  - Phải được Central Node authenticate
  - Phải stake D coins (bị penalty nếu không tạo block kịp thời)
- **Capabilities:**
  - Process transactions và add vào blockchain
  - Validate blocks created by other nodes
  - Receive transaction fees
  - Maintain transaction pool

#### 2.7.3. Content Store Nodes
- **Keys:** Node's mnemonic/key pair (đăng ký với Central Node)
- **Role:** Storage provider
- **Storage:** Full blockchain state + encrypted file storage
- **Requirements:**
  - Phải được Central Node authenticate
- **Capabilities:**
  - Store content, files, images, videos (encrypted)
  - Authenticate file delivery với key pair
  - Receive storage fees
  - Serve file requests

#### 2.7.4. Inspector Nodes
- **Keys:** Node's mnemonic/key pair (đăng ký với Central Node)
- **Role:** Audit và verify blocks
- **Storage:** Full blockchain state
- **Capabilities:**
  - Audit và verify blocks
  - Mark invalid blocks và impose penalties
  - Randomly check blocks for compliance
  - Request block cancellation nếu invalid

#### 2.7.5. Router Nodes
- **Keys:** Node's mnemonic/key pair (đăng ký với Central Node)
- **Role:** Route files đến Content Store nodes
- **Storage:** Network topology, routing tables
- **Capabilities:**
  - Determine which Content Store node sẽ store uploaded files
  - Direct file retrieval requests đến appropriate Content Store nodes
  - Optimize content delivery based on availability và performance

### 2.8. Security Considerations

#### 2.8.1. Transaction Security
- Mọi transaction phải có signature từ private key
- Verify signature trước khi accept transaction
- Timestamp validation (prevent replay attacks)
- Nonce mechanism (prevent duplicate transactions)

#### 2.8.2. Block Security
- Block hash phải match difficulty
- Merkle root validation
- Previous block hash validation
- Transaction order validation

#### 2.8.3. Network Security
- P2P encryption (TLS/SSL)
- Node authentication
- Sybil attack prevention (node registration với voucher)
- DDoS protection

### 2.9. Privacy Considerations

#### 2.9.1. On-Chain Data
- **Public:** Transaction types, timestamps, public keys
- **Encrypted:** User data (email, fullName, etc.) có thể hash
- **Off-chain:** Actual content (posts, comments, files)

#### 2.9.2. Zero-Knowledge Features
- Giữ nguyên zero-knowledge sharing (PRE với Umbral)
- Blockchain chỉ lưu references, không lưu content
- Content vẫn encrypted trên Content Store nodes
- Even Content Store nodes cannot read content (double encryption)
- Only owner và authorized users có thể access content

#### 2.9.3. Content Encryption
- Files được split thành chunks và encrypt
- Unique content ID cho mỗi chunk
- File ID được tạo bằng Merkle tree của chunk IDs
- Content được double-encrypted cho transmission

### 2.10. Performance Optimization

#### 2.10.1. Light Clients
- Users có thể chạy light clients (chỉ headers)
- Full nodes (Block Creator, Content Store, Inspector) lưu full state
- Merkle proofs cho state queries

#### 2.10.2. Content Distribution
- Files được distributed across multiple Content Store nodes
- Router nodes optimize content delivery
- P2P direct transfer capabilities cho speed
- Multi-source downloading based on network conditions
- CDN integration cho content distribution

#### 2.10.3. Caching
- Cache frequent queries
- Index popular data
- Router nodes cache routing decisions

#### 2.10.4. Transfer Optimization
- Shipper nodes maintain logs for 2 months for auditing
- Encrypted verification process ensures content integrity
- Re-encrypted content verification ensures delivery integrity

### 2.11. Migration Path

#### Step 1: Dual Mode
- Hệ thống hiện tại vẫn hoạt động
- Thêm blockchain layer song song
- Mỗi action tạo cả API call và transaction

#### Step 2: Gradual Migration
- Migrate existing data to blockchain
- Users có thể chọn blockchain mode
- API nodes serve cả old và new data

#### Step 3: Full Blockchain
- Tắt API mode
- Chỉ blockchain mode
- All nodes participate in consensus

### 2.12. Example Flow: Create Post với Blockchain

```
1. User tạo post content
   ↓
2. Split file thành chunks và encrypt
   ↓
3. Generate unique content ID cho mỗi chunk
   ↓
4. Create file ID bằng Merkle tree của chunk IDs
   ↓
5. Send request đến Router nodes
   ↓
6. User signs upload request
   ↓
7. Content Store nodes sign để accept storage responsibility
   ↓
8. User approves specific Content Store nodes
   ↓
9. Content chunks transmitted đến approved nodes
   ↓
10. User tạo CreatePost transaction:
    {
      type: "create_post",
      from: user_public_key,
      data: {
        postId: "...",
        storageNodeId: content_store_node_public_key,
        fileId: "...",
        firstBlockId: "...",
        encryptedType: "encrypted",
        shareType: "followers",
        storageFee: 100 // D coins
      },
      signature: sign(data)
    }
    ↓
11. Broadcast transaction to all Block Creator nodes
    ↓
12. Central Node selects Block Creator để tạo block
    ↓
13. Selected Block Creator validates và includes transaction
    ↓
14. Block Creator creates block và broadcasts
    ↓
15. Block Creator nodes validate block
    ↓
16. Inspector nodes audit block (randomly)
    ↓
17. Block added to chain
    ↓
18. State updated: postId -> storageNodeId, fileId
```

### 2.13. Benefits của Blockchain Approach

1. **Decentralization:** Không phụ thuộc vào single node (trừ Central Coordinator)
2. **Immutability:** Transactions không thể sửa/xóa
3. **Transparency:** Mọi node có thể verify state
4. **Resilience:** Network vẫn hoạt động nếu một số nodes down
5. **Auditability:** Full history của mọi action
6. **Trust:** Central Coordinator quản lý nhưng blockchain vẫn transparent
7. **Incentives:** Transaction fees và storage fees incentivize nodes
8. **Security:** Inspector nodes audit blocks, penalties cho bad actors
9. **Scalability:** Router nodes optimize content delivery
10. **Privacy:** Content encrypted, even storage nodes cannot read

### 2.14. Challenges và Solutions

#### Challenge 1: Scalability
- **Problem:** Blockchain có thể chậm với nhiều transactions
- **Solution:** 
  - Fast block time (5-10s)
  - Batch transactions
  - Off-chain content (chỉ references on-chain)

#### Challenge 2: Storage
- **Problem:** Full blockchain state lớn
- **Solution:**
  - Light clients cho users
  - Full nodes chỉ cho store/API nodes
  - Pruning old data (nếu cần)

#### Challenge 3: Privacy
- **Problem:** Blockchain public, nhưng cần privacy
- **Solution:**
  - Chỉ lưu references on-chain
  - Content encrypted off-chain
  - Zero-knowledge proofs (PRE)

#### Challenge 4: User Experience
- **Problem:** Blockchain có thể phức tạp cho users
- **Solution:**
  - Abstract blockchain complexity
  - Fast confirmation (5-10s)
  - Good error handling

## 3. Technical Implementation Details

### 3.1. Transaction Pool

Mỗi node maintain một transaction pool:
- Pending transactions chờ được include vào block
- Validate transactions trước khi add vào pool
- Remove transactions sau khi included trong block
- Prioritize transactions (fees, timestamp)

### 3.2. Block Creation

1. Validator collects transactions từ pool
2. Validate tất cả transactions
3. Create Merkle tree
4. Calculate block hash với difficulty
5. Sign block với validator's key
6. Broadcast block to network

### 3.3. Fork Resolution

- Longest chain rule
- Nếu có fork, chọn chain có nhiều blocks hơn
- Reorg nếu cần (revert transactions)

### 3.4. Sync Mechanism

- New nodes request blocks từ genesis
- Existing nodes sync missing blocks
- State sync (nếu cần)

## 3.15 Implementation Status (Hiện trạng)

Tài liệu chi tiết đánh giá và lộ trình: **BLOCKCHAIN_PLAN.md**.

**Đã có (MVP/prototype):**
- **Block Creator:** Block creation loop, mempool (mempool.json), chain state (blocks.json). Central API ký decision (tx) và block-slot; Blocker verify với Central pubkey.
- **Transaction types:** Blocker chấp nhận đủ 10 loại (UserRegistration → Donate). **App** gửi **Follow, Unfollow**. **Store** gửi **StorageOperation** (contract envelope: hash + appSignature + storageNodeSignature + content) cho post, react, comment, chat_message.
- **Storage contract:** App ↔ Store ký hợp đồng (V1 message / V2 contract hash); Store submit một StorageOperation tx; Blocker validate contract hash và chữ ký.
- **Central API:** User registration, follow graph, store/block creator node registry, voucher, PRE rekey; decision + block-slot (chọn blocker ngẫu nhiên, ký SHA256 message).

**Chưa có / Khác proposal:**
- **UserRegistration tx:** App chỉ gọi API đăng ký, chưa gửi tx UserRegistration lên chain.
- **CreatePost tx:** Chỉ có StorageOperation từ Store (có fileId, contract); không có tx CreatePost riêng từ App (postId, fileId, storageNodeId).
- **State từ chain:** API/Store vẫn là source of truth (users.json, user_follows.json); chưa có **Blockchain Indexer** rebuild state từ blocks.
- **Persistence:** JSON (users, blocks, mempool); chưa DB.
- **P2P / Gossip:** Chưa; chỉ HTTP qua Central.
- **Consensus:** Chọn blocker ngẫu nhiên; chưa PoA/PoS.
- **Inspector, Router nodes:** Chưa triển khai.
- **D-Coin, Transfer, Donate:** Schema có; chưa balance, reward distribution, ví.

**Kết luận:** Lộ trình chuyển đổi đã đạt **MVP** (storage + follow on-chain, block creation với Central coordination). Chưa hoàn thành đầy đủ: state từ chain (indexer), P2P, consensus thật, kinh tế D-Coin. Chi tiết còn thiếu và roadmap: **BLOCKCHAIN_PLAN.md**.

## 4. Next Steps

1. ~~**Prototype:** Implement basic blockchain với 1-2 transaction types~~ → **Done (MVP):** StorageOperation, Follow/Unfollow, blocks + Central decision/slot.
2. **State & persistence:** Blockchain Indexer rebuild state từ blocks; thay JSON bằng DB (Phase 1 trong BLOCKCHAIN_PLAN.md).
3. **Test:** Test với small network (nhiều blockers, store).
4. **Decentralization:** P2P gossip, consensus xác định (PoA/round-robin) — Phase 2.
5. **Economy & security:** D-Coin, fee distribution, Transfer/Donate; secure wallet; audit — Phase 3.
6. **Optional:** App gửi UserRegistration tx sau đăng ký; gửi CreatePost tx (reference) sau khi Store nhận file.
7. **Deploy / Migrate / Launch:** Testnet → migrate data → mainnet.

## 5. References

- Bitcoin: UTXO model, Proof of Work
- Ethereum: Account model, Smart contracts
- Hyperledger Fabric: Permissioned blockchain
- IPFS: Distributed file storage
- libp2p: P2P networking

