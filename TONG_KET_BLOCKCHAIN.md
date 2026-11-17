# Tóm Tắt Rà Soát và Đề Xuất Blockchain cho Deltanium

## 📋 Phần 1: Rà Soát Các Luồng Hiện Tại

### 1. Đăng Ký (Registration)
- **Luồng:** Client tạo key pair → Ký dữ liệu → Gửi API → Lưu vào `users.json`
- **Dữ liệu:** PublicKey, Email, FullName, Signature, Timestamp
- **Đã có sẵn:** Signature và Timestamp (sẵn sàng cho blockchain)

### 2. Đăng Nhập (Login)
- **Luồng:** Mỗi request đều có authentication headers (X-User-PubKey, X-Timestamp, X-Signature)
- **Không có session:** Mỗi request phải ký lại
- **Phù hợp blockchain:** Đã có cơ chế signature-based auth

### 3. Follow/Unfollow
- **Luồng:** Client ký follow action → Gửi API → Lưu vào `user_follows.json`
- **Dữ liệu:** FollowerPublicKey, FollowingPublicKey, Signature, Timestamp
- **Đã có sẵn:** Signature và Timestamp

### 4. Viết Bài (Create Post)
- **Luồng phức tạp:**
  - Upload ảnh (nếu có) → Encrypt → Upload metadata + blocks
  - Tạo post content → Encrypt → Upload
  - Có thể là: public, encrypted (ECIES), hoặc PRE (cho followers)
- **Dữ liệu:** FileMetadata với type="post", EncryptedKey, OwnerPubKey, ShareType
- **Lưu trữ:** Trên store nodes (off-chain), chỉ metadata on-chain

### 5. React (Like/Comment)
- **Reaction:**
  - Tạo file type="react" với parentFileId, kind
  - Public hoặc encrypted
- **Comment:**
  - Tạo file type="comment" với parentFileId
  - shareType: "author" hoặc "public"
  - Có thể có ảnh đính kèm
- **Dữ liệu:** FileMetadata với type và parentFileId

### 6. Node Authentication
- **Store Nodes:** Có key pair riêng, đăng ký với API bằng voucher
- **API Nodes:** Chưa có authentication riêng (chỉ verify user signatures)

## 🚀 Phần 2: Đề Xuất Giải Pháp Blockchain

### Kiến Trúc Tổng Quan

```
┌─────────────────────────────────────────┐
│      DELTANIUM BLOCKCHAIN NETWORK       │
├─────────────────────────────────────────┤
│                                         │
│  Central Coordination Node             │
│  (deltanium.com)                       │
│  ├─ Node Registry & Authentication     │
│  ├─ Block Creation Scheduler           │
│  └─ Health Monitoring                  │
│                                         │
│  5 Loại Node:                           │
│                                         │
│  1. Block Creator Nodes                 │
│     ├─ Tạo blocks                     │
│     ├─ Validate blocks                 │
│     └─ Phải stake D coins              │
│                                         │
│  2. User Nodes                          │
│     ├─ Tạo transactions                │
│     ├─ Upload files, create content     │
│     └─ Like, love, donate, transfer     │
│                                         │
│  3. Content Store Nodes                │
│     ├─ Store encrypted files           │
│     └─ Authenticate file delivery      │
│                                         │
│  4. Inspector Nodes                     │
│     ├─ Audit và verify blocks          │
│     └─ Mark invalid blocks, penalties  │
│                                         │
│  5. Router Nodes                        │
│     ├─ Route files đến Content Store   │
│     └─ Optimize content delivery        │
│                                         │
│  P2P Network (Blockchain Layer)        │
│  ├─ Transaction propagation            │
│  ├─ Block propagation                  │
│  └─ Chain sync                         │
└─────────────────────────────────────────┘
```

### Các Loại Transaction

1. **UserRegistration:** Đăng ký user mới
2. **Follow/Unfollow:** Follow/unfollow users
3. **CreatePost:** Tạo bài viết (chỉ lưu reference, content off-chain)
4. **React:** Like/react bài viết
5. **Comment:** Comment bài viết (có thể có ảnh)
6. **NodeRegistration:** Đăng ký store/API node
7. **StorageOperation:** Operations của store nodes

### Consensus Mechanism (Theo README của deltanium-core)

**Central Coordination với Block Creator Selection**
- Central node (deltanium.com) quản lý và authorize nodes
- Central node chọn Block Creator nào sẽ tạo block tiếp theo
- Block Creator được chọn phải tạo block trong thời gian giới hạn
- Nếu không tạo block kịp thời → bị penalty (mất tiền stake)
- Block Creator nodes phải stake D coins
- Inspector nodes audit blocks và impose penalties

### State Management

**On-Chain (Blockchain):**
- User registry
- Follow relationships
- Post references (postId → storageNodeId, fileId)
- Reaction/Comment references
- Node registry (5 loại node)
- D coin balances và transaction history

**Off-Chain (Content Store Nodes):**
- Actual file content (encrypted, split thành chunks)
- File metadata (encrypted)
- Chunks data
- Merkle tree của chunks

### Lợi Ích

1. ✅ **Decentralization:** Không phụ thuộc single API node
2. ✅ **Immutability:** Transactions không thể sửa/xóa
3. ✅ **Transparency:** Mọi node verify được state
4. ✅ **Resilience:** Network vẫn hoạt động nếu một số nodes down
5. ✅ **Auditability:** Full history của mọi action
6. ✅ **Trust:** Không cần trust central authority

### Privacy

- ✅ **Zero-Knowledge:** Giữ nguyên PRE mechanism (Umbral)
- ✅ **On-chain chỉ references:** Không lưu content
- ✅ **Content encrypted:** Vẫn encrypted trên Content Store nodes
- ✅ **Double encryption:** Even Content Store nodes cannot read content
- ✅ **Re-encryption verification:** Inspector nodes verify content transfers

## 📝 Phần 3: Implementation Strategy

### Phase 1: Transaction Layer (2-3 tuần)
- [ ] Định nghĩa transaction types
- [ ] Implement transaction signing/verification
- [ ] Convert existing actions thành transactions
- [ ] Store transactions locally

### Phase 2: Block Layer (2-3 tuần)
- [ ] Implement block structure
- [ ] Implement Merkle tree
- [ ] Implement block creation
- [ ] Implement block validation

### Phase 3: Network Layer (3-4 tuần)
- [ ] Implement P2P protocol
- [ ] Implement transaction propagation
- [ ] Implement block propagation
- [ ] Implement sync mechanism

### Phase 4: Consensus (2-3 tuần)
- [ ] Implement validator selection
- [ ] Implement block creation schedule
- [ ] Implement fork resolution
- [ ] Implement finality

### Phase 5: Migration (2-3 tuần)
- [ ] Migrate existing data
- [ ] Dual-mode operation
- [ ] Gradual migration
- [ ] Full blockchain mode

**Tổng thời gian ước tính: 11-16 tuần**

## 🔧 Phần 4: Technical Details

### Transaction Structure

Mỗi transaction có:
- `txId`: Hash của transaction
- `type`: Loại transaction
- `timestamp`: Unix timestamp
- `from`: Public key của người tạo
- `to`: Public key của người nhận (nếu có)
- `data`: Dữ liệu transaction-specific
- `signature`: Chữ ký của transaction
- `nonce`: Prevent duplicate transactions

### Block Structure

Mỗi block có:
- `blockId`: Hash của block
- `previousBlockId`: Hash của block trước
- `timestamp`: Unix timestamp
- `merkleRoot`: Merkle root của transactions
- `transactions`: List các transactions
- `miner`: Public key của validator tạo block
- `nonce`: Nonce để meet difficulty
- `difficulty`: Số leading zeros cần thiết

### Node Types (Theo README của deltanium-core)

1. **User Nodes:**
   - Keys: User's mnemonic/key pair
   - Role: Tạo transactions, upload files, interact với content
   - Storage: Light client (chỉ headers) hoặc full node

2. **Block Creator Nodes:**
   - Keys: Node's mnemonic/key pair
   - Role: Tạo blocks, validate blocks
   - Requirements: Phải được Central Node authenticate, phải stake D coins
   - Storage: Full blockchain state

3. **Content Store Nodes:**
   - Keys: Node's mnemonic/key pair
   - Role: Storage provider
   - Requirements: Phải được Central Node authenticate
   - Storage: Full blockchain state + encrypted file storage

4. **Inspector Nodes:**
   - Keys: Node's mnemonic/key pair
   - Role: Audit và verify blocks
   - Storage: Full blockchain state

5. **Router Nodes:**
   - Keys: Node's mnemonic/key pair
   - Role: Route files đến Content Store nodes
   - Storage: Network topology, routing tables

## 📊 Phần 5: Migration Path

### Step 1: Dual Mode
- Hệ thống hiện tại vẫn hoạt động
- Thêm blockchain layer song song
- Mỗi action tạo cả API call và transaction

### Step 2: Gradual Migration
- Migrate existing data to blockchain
- Users có thể chọn blockchain mode
- API nodes serve cả old và new data

### Step 3: Full Blockchain
- Tắt API mode
- Chỉ blockchain mode
- All nodes participate in consensus

## 🎯 Phần 6: Next Steps

### Immediate Actions:
1. ✅ Review và approve proposal
2. ⏳ Setup development environment
3. ⏳ Create project structure
4. ⏳ Implement transaction layer

### Short-term (1-2 tháng):
- Implement core blockchain functionality
- Test với small network
- Optimize performance

### Medium-term (3-4 tháng):
- Implement P2P network
- Implement consensus
- Deploy testnet

### Long-term (5-6 tháng):
- Migrate existing data
- Launch mainnet
- Full blockchain mode

## 📚 Tài Liệu Tham Khảo

1. **BLOCKCHAIN_PROPOSAL.md:** Đề xuất chi tiết về blockchain
2. **BLOCKCHAIN_IMPLEMENTATION.md:** Code examples và implementation details

## ❓ Questions & Answers

### Q: Blockchain có làm chậm hệ thống không?
**A:** Với Central Coordination và Block Creator selection, performance sẽ tốt. Content vẫn off-chain (chỉ references on-chain) nên không ảnh hưởng nhiều. Router nodes optimize content delivery.

### Q: Privacy có được đảm bảo không?
**A:** Có. On-chain chỉ lưu references, content vẫn encrypted off-chain. Giữ nguyên zero-knowledge features (PRE).

### Q: Users có cần chạy full node không?
**A:** Không. Users có thể chạy light clients (chỉ headers). Full nodes chỉ cần cho store/API nodes.

### Q: Làm sao migrate existing data?
**A:** Tạo transactions cho existing data, apply vào blockchain. Có thể làm gradual migration.

### Q: Validators được chọn như thế nào?
**A:** Central Node (deltanium.com) chọn Block Creator nào sẽ tạo block tiếp theo. Block Creator nodes phải được Central Node authenticate và phải stake D coins. Nếu không tạo block kịp thời sẽ bị penalty.

## 📞 Contact

Nếu có câu hỏi hoặc cần clarification, vui lòng liên hệ team development.

---

**Tài liệu này được tạo tự động dựa trên codebase analysis và blockchain best practices.**

