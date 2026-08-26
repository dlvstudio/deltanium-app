# Deltanium Blockchain Review and Proposal Summary

## Part 1: Current Flow Review

### 1. Registration
- **Flow:** Client creates a key pair → signs data → sends to API → stored in `users.json`
- **Data:** PublicKey, Email, FullName, Signature, Timestamp
- **Already present:** Signature and Timestamp (ready for blockchain)

### 2. Login
- **Flow:** Every request uses authentication headers (`X-User-PubKey`, `X-Timestamp`, `X-Signature`)
- **No session:** Each request must be signed again
- **Blockchain fit:** Signature-based auth is already in place

### 3. Follow / Unfollow
- **Flow:** Client signs the follow action → sends to API → stored in `user_follows.json`
- **Data:** FollowerPublicKey, FollowingPublicKey, Signature, Timestamp
- **Already present:** Signature and Timestamp

### 4. Create Post
- **Flow:**
  - Upload image (if any) → encrypt → upload metadata + blocks
  - Create post content → encrypt → upload
  - May be public, encrypted (ECIES), or PRE (followers)
- **Data:** FileMetadata with `type="post"`, EncryptedKey, OwnerPubKey, ShareType
- **Storage:** Store nodes (off-chain); only metadata on-chain

### 5. React (Like / Comment)
- **Reaction:**
  - File with `type="react"`, `parentFileId`, `kind`
  - Public or encrypted
- **Comment:**
  - File with `type="comment"`, `parentFileId`
  - `shareType`: `"author"` or `"public"`
  - May include attached images
- **Data:** FileMetadata with type and parentFileId

### 6. Node Authentication
- **Store nodes:** Own key pair, register with the API using a voucher
- **API nodes:** No separate node authentication yet (only user signature verification)

## Part 2: Proposed Blockchain Solution

### High-level architecture

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
│  5 node types:                         │
│                                         │
│  1. Block Creator Nodes                 │
│     ├─ Create blocks                   │
│     ├─ Validate blocks                 │
│     └─ Must stake D coins              │
│                                         │
│  2. User Nodes                          │
│     ├─ Create transactions             │
│     ├─ Upload files, create content    │
│     └─ Like, love, donate, transfer    │
│                                         │
│  3. Content Store Nodes                │
│     ├─ Store encrypted files           │
│     └─ Authenticate file delivery      │
│                                         │
│  4. Inspector Nodes                     │
│     ├─ Audit and verify blocks         │
│     └─ Mark invalid blocks, penalties  │
│                                         │
│  5. Router Nodes                        │
│     ├─ Route files to Content Store    │
│     └─ Optimize content delivery       │
│                                         │
│  P2P Network (Blockchain Layer)        │
│  ├─ Transaction propagation            │
│  ├─ Block propagation                  │
│  └─ Chain sync                         │
└─────────────────────────────────────────┘
```

### Transaction types

1. **UserRegistration:** Register a new user
2. **Follow/Unfollow:** Follow or unfollow users
3. **CreatePost:** Create a post (reference only; content off-chain)
4. **React:** Like/react to a post
5. **Comment:** Comment on a post (may include images)
6. **NodeRegistration:** Register a store/API node
7. **StorageOperation:** Store-node operations

### Consensus (per deltanium-core README)

**Central coordination with Block Creator selection**
- Central node (deltanium.com) manages and authorizes nodes
- Central node selects which Block Creator produces the next block
- The selected Block Creator must produce the block within a time limit
- If it misses the window → penalty (lost stake)
- Block Creator nodes must stake D coins
- Inspector nodes audit blocks and impose penalties

### State management

**On-chain (blockchain):**
- User registry
- Follow relationships
- Post references (postId → storageNodeId, fileId)
- Reaction/comment references
- Node registry (5 node types)
- D coin balances and transaction history

**Off-chain (Content Store nodes):**
- Actual file content (encrypted, split into chunks)
- File metadata (encrypted)
- Chunk data
- Merkle tree of chunks

### Benefits

1. **Decentralization:** Not dependent on a single API node
2. **Immutability:** Transactions cannot be edited or deleted
3. **Transparency:** Every node can verify state
4. **Resilience:** The network keeps running if some nodes go down
5. **Auditability:** Full history of every action
6. **Trust:** No need to trust a central authority for ledger state

### Privacy

- **Zero-knowledge:** Keep the PRE mechanism (Umbral)
- **On-chain references only:** Do not store content
- **Encrypted content:** Still encrypted on Content Store nodes
- **Double encryption:** Even Content Store nodes cannot read content
- **Re-encryption verification:** Inspector nodes verify content transfers

## Part 3: Implementation Strategy

### Phase 1: Transaction layer (2–3 weeks)
- [ ] Define transaction types
- [ ] Implement transaction signing/verification
- [ ] Convert existing actions into transactions
- [ ] Store transactions locally

### Phase 2: Block layer (2–3 weeks)
- [ ] Implement block structure
- [ ] Implement Merkle tree
- [ ] Implement block creation
- [ ] Implement block validation

### Phase 3: Network layer (3–4 weeks)
- [ ] Implement P2P protocol
- [ ] Implement transaction propagation
- [ ] Implement block propagation
- [ ] Implement sync

### Phase 4: Consensus (2–3 weeks)
- [ ] Implement validator selection
- [ ] Implement block creation schedule
- [ ] Implement fork resolution
- [ ] Implement finality

### Phase 5: Migration (2–3 weeks)
- [ ] Migrate existing data
- [ ] Dual-mode operation
- [ ] Gradual migration
- [ ] Full blockchain mode

**Estimated total: 11–16 weeks**

## Part 4: Technical Details

### Transaction structure

Each transaction has:
- `txId`: Transaction hash
- `type`: Transaction type
- `timestamp`: Unix timestamp
- `from`: Creator public key
- `to`: Recipient public key (if any)
- `data`: Type-specific payload
- `signature`: Transaction signature
- `nonce`: Prevents duplicate transactions

### Block structure

Each block has:
- `blockId`: Block hash
- `previousBlockId`: Previous block hash
- `timestamp`: Unix timestamp
- `merkleRoot`: Merkle root of transactions
- `transactions`: Transaction list
- `miner`: Public key of the validator that created the block
- `nonce`: Nonce to meet difficulty
- `difficulty`: Required leading zeros

### Node types (per deltanium-core README)

1. **User nodes:**
   - Keys: User mnemonic/key pair
   - Role: Create transactions, upload files, interact with content
   - Storage: Light client (headers only) or full node

2. **Block Creator nodes:**
   - Keys: Node mnemonic/key pair
   - Role: Create and validate blocks
   - Requirements: Authenticated by the Central Node, must stake D coins
   - Storage: Full blockchain state

3. **Content Store nodes:**
   - Keys: Node mnemonic/key pair
   - Role: Storage provider
   - Requirements: Authenticated by the Central Node
   - Storage: Full blockchain state + encrypted file storage

4. **Inspector nodes:**
   - Keys: Node mnemonic/key pair
   - Role: Audit and verify blocks
   - Storage: Full blockchain state

5. **Router nodes:**
   - Keys: Node mnemonic/key pair
   - Role: Route files to Content Store nodes
   - Storage: Network topology, routing tables

## Part 5: Migration Path

### Step 1: Dual mode
- Current system keeps running
- Add a parallel blockchain layer
- Each action produces both an API call and a transaction

### Step 2: Gradual migration
- Migrate existing data to the blockchain
- Users can opt into blockchain mode
- API nodes serve both old and new data

### Step 3: Full blockchain
- Turn off API-only mode
- Blockchain mode only
- All nodes participate in consensus

## Part 6: Next Steps

### Immediate:
1. Review and approve the proposal
2. Set up the development environment
3. Create the project structure
4. Implement the transaction layer

### Short term (1–2 months):
- Implement core blockchain functionality
- Test with a small network
- Optimize performance

### Medium term (3–4 months):
- Implement the P2P network
- Implement consensus
- Deploy a testnet

### Long term (5–6 months):
- Migrate existing data
- Launch mainnet
- Full blockchain mode

## References

1. **BLOCKCHAIN_PROPOSAL.md:** Detailed blockchain proposal
2. **BLOCKCHAIN_IMPLEMENTATION.md:** Code examples and implementation details

## Questions & Answers

### Q: Will the blockchain slow the system down?
**A:** With central coordination and Block Creator selection, performance should stay acceptable. Content remains off-chain (only references on-chain). Router nodes optimize delivery.

### Q: Is privacy preserved?
**A:** Yes. On-chain storage is references only; content stays encrypted off-chain. Zero-knowledge features (PRE) remain.

### Q: Do users need to run a full node?
**A:** No. Users can run light clients (headers only). Full nodes are for store/API nodes.

### Q: How is existing data migrated?
**A:** Create transactions for existing data and apply them to the chain. Migration can be gradual.

### Q: How are validators selected?
**A:** The Central Node (deltanium.com) selects which Block Creator produces the next block. Block Creators must be authenticated and must stake D coins. Missing the time window incurs a penalty.

---

This document was produced from codebase analysis and blockchain design notes.
