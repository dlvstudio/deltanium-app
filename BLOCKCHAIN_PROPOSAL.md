# Proposal: Migrating Deltanium to a Blockchain

## 1. Review of Current Flows

### 1.1. Registration

**Current flow:**
- Client generates a mnemonic and secp256k1 key pair locally
- Client signs the data: `email:fullName:dateOfBirth:timestamp`
- Sends a signed request to `/api/user/register`
- API verifies the signature and stores the user in `users.json`
- Stores `Signature` and `RegistrationTimestamp` for blockchain operations

**Stored data:**
- PublicKey (identity)
- Email, FullName, DateOfBirth, Bio, AvatarUrl
- Signature (registration signature)
- RegistrationTimestamp

### 1.2. Login

**Current flow:**
- Client has no dedicated login endpoint
- Uses authentication headers on every request:
  - `X-User-PubKey`: User's public key
  - `X-Timestamp`: Unix timestamp
  - `X-Signature`: Signature of `method + path + timestamp + bodyHash`
- API verifies the signature and checks that the user is registered

**Issue:** No session; every request must be signed

### 1.3. Follow/Unfollow

**Current flow:**
- Client creates a follow action: `{"action":"follow","follower":"...","following":"...","timestamp":"..."}`
- Signs this action with the private key
- Sends it to `/api/user/follow` with:
  - SignedData (JSON of the action)
  - Signature (signature of SignedData)
  - Timestamp
- API verifies the signature and stores it in `user_follows.json`
- Stores the follow action's `Signature` and `Timestamp`

**Stored data:**
- FollowerPublicKey
- FollowingPublicKey
- Timestamp
- Signature

### 1.4. Create Post

**Current flow:**
1. **Post with images:**
   - Upload images to a store node (encrypted with ECIES or PRE)
   - Create post content (JSON) with image metadata
   - Encrypt post content
   - Upload metadata and blocks to the store node
   - A post may be:
     - `encryptedType: "public"` — not encrypted
     - `encryptedType: "encrypted"` — encrypted with ECIES
     - `shareType: "followers"` — shared with followers (using PRE)

2. **Text-only post:**
   - Same as above, without attached images

**Stored data:**
- FileMetadata with `type: "post"`
- EncryptedKey (ECIES or PRE capsule)
- OwnerPubKey (author)
- EncryptedType, ShareType
- PolicyTag, CapsuleFor, PolicyScheme (for PRE)

### 1.5. React (Like/Comment)

**Current flow:**
1. **Reaction:**
   - Create a file with `type: "react"`, `parentFileId: postFileId`, `kind: "like|love|laugh|wow|sad|angry"`
   - Public reaction: `isPublic: true`, not encrypted
   - Encrypted reaction: encrypted with ECIES for the post owner
   - Upload metadata and block0 to the store node

2. **Comment:**
   - Create a file with `type: "comment"`, `parentFileId: postFileId`
   - `shareType: "author"` (author only) or `"public"` (visible to everyone)
   - Comments may include attached images (relatedFiles)
   - Upload metadata and blocks to the store node

**Stored data:**
- FileMetadata with `type: "react"` or `"comment"`
- ParentFileId (link to the post)
- OwnerPubKey (the user who reacted/commented)
- EncryptedKey (if encrypted)
- ShareType, EncryptedType

### 1.6. Node Authentication

**Store Nodes:**
- Each store node has its own mnemonic and key pair
- Registers with the API using a voucher
- Stores PublicKey and Endpoint in `nodes.json`
- Store nodes can authenticate requests with their keys

**API Nodes:**
- Currently there is no dedicated authentication for API nodes
- API nodes only verify user signatures

## 2. Proposed Blockchain Solution

### 2.1. Architecture Overview (per the deltanium-core README)

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
│  5 Node Types:                                            │   │
│  1. Block Creator Nodes: Create and validate blocks      │   │
│  2. User Nodes: Create transactions, interact with content│  │
│  3. Content Store Nodes: Store encrypted content         │   │
│  4. Inspector Nodes: Audit and verify blocks             │   │
│  5. Router Nodes: Route files to Content Store nodes     │   │
└───────────────────────────────────────────────────────────┘
```

### 2.2. Transaction Types

Every action is a transaction:

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

#### 2.2.8. StorageOperation Transaction (new flow)
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

### 2.4. Consensus Mechanism (per the deltanium-core README)

**Central Coordination with Block Creator Selection**

#### Central Coordination
- The central node (deltanium.com) manages and authorizes nodes
- Nodes must be authenticated by the central node to create blocks or store content
- The central node provides:
  - Authentication Authority: Authenticates nodes
  - Node Registry: Manages the node list
  - Block Creation Scheduler: Selects the Block Creator for the next block
  - Health Monitoring: Monitors node health

#### Transaction Processing
- Transactions are broadcast to all Block Creator nodes
- The central node selects which Block Creator will create the next block
- The selected Block Creator must create the block within a time limit
- If it fails to create the block in time → penalty (loss of stake)

#### Block Validation
- Blocks must be created by authorized nodes
- All transactions in the block must be valid
- Block Creator nodes validate new blocks and signal acceptance
- If invalid, nodes report to the central node and Inspector nodes

#### Inspection Process
- Inspector nodes receive new blocks
- Wait for Block Creator validations
- If issues are reported, re-validate the block
- May request block cancellation if invalid
- Periodically perform random block audits

### 2.5. State Management

**Global State (Blockchain):**
- User registry (public keys, basic info)
- Follow relationships
- Post references (postId -> storageNodeId, fileId)
- Reaction references
- Comment references
- Node registry (all 5 node types)
- D coin balances (UTXO or Account model)
- Transaction history

**Local State (Content Store Nodes):**
- Actual file content (encrypted)
- File metadata (encrypted)
- Chunk data (files split into chunks)
- Merkle tree of chunks

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
1. Define transaction types
2. Implement transaction signing/verification
3. Convert existing actions into transactions
4. Store transactions locally before broadcast

#### Phase 2: Block Layer
1. Implement block structure
2. Implement Merkle tree for transactions
3. Implement block creation (mining/validation)
4. Implement block validation

#### Phase 3: Network Layer
1. Implement P2P protocol (libp2p or custom)
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

### 2.7. Node Types and Roles (per the deltanium-core README)

#### 2.7.1. User Nodes
- **Keys:** User's mnemonic/key pair
- **Role:** Create transactions, interact with content
- **Storage:** Local blockchain state (light client or full node)
- **Capabilities:**
  - Create transactions (registration, follow, post, react, comment, transfer, donate)
  - Upload files and create content
  - Perform actions on content (like, love, donate)
  - Transfer D coins to other users
  - Query blockchain state
  - Sync with the network

#### 2.7.2. Block Creator Nodes
- **Keys:** Node's mnemonic/key pair (registered with the Central Node)
- **Role:** Create and validate blocks
- **Storage:** Full blockchain state
- **Requirements:**
  - Must be authenticated by the Central Node
  - Must stake D coins (penalized if a block is not created in time)
- **Capabilities:**
  - Process transactions and add them to the blockchain
  - Validate blocks created by other nodes
  - Receive transaction fees
  - Maintain transaction pool

#### 2.7.3. Content Store Nodes
- **Keys:** Node's mnemonic/key pair (registered with the Central Node)
- **Role:** Storage provider
- **Storage:** Full blockchain state + encrypted file storage
- **Requirements:**
  - Must be authenticated by the Central Node
- **Capabilities:**
  - Store content, files, images, videos (encrypted)
  - Authenticate file delivery with the key pair
  - Receive storage fees
  - Serve file requests

#### 2.7.4. Inspector Nodes
- **Keys:** Node's mnemonic/key pair (registered with the Central Node)
- **Role:** Audit and verify blocks
- **Storage:** Full blockchain state
- **Capabilities:**
  - Audit and verify blocks
  - Mark invalid blocks and impose penalties
  - Randomly check blocks for compliance
  - Request block cancellation if invalid

#### 2.7.5. Router Nodes
- **Keys:** Node's mnemonic/key pair (registered with the Central Node)
- **Role:** Route files to Content Store nodes
- **Storage:** Network topology, routing tables
- **Capabilities:**
  - Determine which Content Store node will store uploaded files
  - Direct file retrieval requests to the appropriate Content Store nodes
  - Optimize content delivery based on availability and performance

### 2.8. Security Considerations

#### 2.8.1. Transaction Security
- Every transaction must be signed with a private key
- Verify the signature before accepting the transaction
- Timestamp validation (prevent replay attacks)
- Nonce mechanism (prevent duplicate transactions)

#### 2.8.2. Block Security
- Block hash must match the difficulty
- Merkle root validation
- Previous block hash validation
- Transaction order validation

#### 2.8.3. Network Security
- P2P encryption (TLS/SSL)
- Node authentication
- Sybil attack prevention (node registration with voucher)
- DDoS protection

### 2.9. Privacy Considerations

#### 2.9.1. On-Chain Data
- **Public:** Transaction types, timestamps, public keys
- **Encrypted:** User data (email, fullName, etc.) may be hashed
- **Off-chain:** Actual content (posts, comments, files)

#### 2.9.2. Zero-Knowledge Features
- Preserve zero-knowledge sharing (PRE with Umbral)
- The blockchain stores only references, not content
- Content remains encrypted on Content Store nodes
- Even Content Store nodes cannot read content (double encryption)
- Only the owner and authorized users can access content

#### 2.9.3. Content Encryption
- Files are split into chunks and encrypted
- Unique content ID for each chunk
- File ID is created from a Merkle tree of chunk IDs
- Content is double-encrypted for transmission

### 2.10. Performance Optimization

#### 2.10.1. Light Clients
- Users can run light clients (headers only)
- Full nodes (Block Creator, Content Store, Inspector) store the full state
- Merkle proofs for state queries

#### 2.10.2. Content Distribution
- Files are distributed across multiple Content Store nodes
- Router nodes optimize content delivery
- P2P direct transfer capabilities for speed
- Multi-source downloading based on network conditions
- CDN integration for content distribution

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
- The current system continues to operate
- Add a parallel blockchain layer
- Each action produces both an API call and a transaction

#### Step 2: Gradual Migration
- Migrate existing data to blockchain
- Users can opt into blockchain mode
- API nodes serve both old and new data

#### Step 3: Full Blockchain
- Disable API mode
- Blockchain-only mode
- All nodes participate in consensus

### 2.12. Example Flow: Create Post with Blockchain

```
1. User creates post content
   ↓
2. Split the file into chunks and encrypt
   ↓
3. Generate a unique content ID for each chunk
   ↓
4. Create the file ID from a Merkle tree of chunk IDs
   ↓
5. Send the request to Router nodes
   ↓
6. User signs upload request
   ↓
7. Content Store nodes sign to accept storage responsibility
   ↓
8. User approves specific Content Store nodes
   ↓
9. Content chunks are transmitted to approved nodes
   ↓
10. User creates a CreatePost transaction:
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
12. Central Node selects a Block Creator to create the block
    ↓
13. Selected Block Creator validates and includes the transaction
    ↓
14. Block Creator creates the block and broadcasts it
    ↓
15. Block Creator nodes validate block
    ↓
16. Inspector nodes audit block (randomly)
    ↓
17. Block added to chain
    ↓
18. State updated: postId -> storageNodeId, fileId
```

### 2.13. Benefits of the Blockchain Approach

1. **Decentralization:** Not dependent on a single node (except the Central Coordinator)
2. **Immutability:** Transactions cannot be modified or deleted
3. **Transparency:** Every node can verify state
4. **Resilience:** The network continues to operate if some nodes go down
5. **Auditability:** Full history of every action
6. **Trust:** The Central Coordinator manages the network, but the blockchain remains transparent
7. **Incentives:** Transaction fees and storage fees incentivize nodes
8. **Security:** Inspector nodes audit blocks; penalties for bad actors
9. **Scalability:** Router nodes optimize content delivery
10. **Privacy:** Content encrypted, even storage nodes cannot read

### 2.14. Challenges and Solutions

#### Challenge 1: Scalability
- **Problem:** The blockchain can slow down under high transaction volume
- **Solution:**
  - Fast block time (5-10s)
  - Batch transactions
  - Off-chain content (references only on-chain)

#### Challenge 2: Storage
- **Problem:** Full blockchain state is large
- **Solution:**
  - Light clients for users
  - Full nodes only for store/API nodes
  - Pruning old data (if needed)

#### Challenge 3: Privacy
- **Problem:** The blockchain is public, but privacy is required
- **Solution:**
  - Store only references on-chain
  - Content encrypted off-chain
  - Zero-knowledge proofs (PRE)

#### Challenge 4: User Experience
- **Problem:** Blockchain can be complex for users
- **Solution:**
  - Abstract blockchain complexity
  - Fast confirmation (5-10s)
  - Good error handling

## 3. Technical Implementation Details

### 3.1. Transaction Pool

Each node maintains a transaction pool:
- Pending transactions waiting to be included in a block
- Validate transactions before adding them to the pool
- Remove transactions after they are included in a block
- Prioritize transactions (fees, timestamp)

### 3.2. Block Creation

1. Validator collects transactions from the pool
2. Validate all transactions
3. Create Merkle tree
4. Calculate the block hash with difficulty
5. Sign the block with the validator's key
6. Broadcast block to network

### 3.3. Fork Resolution

- Longest chain rule
- If a fork occurs, choose the chain with more blocks
- Reorg if needed (revert transactions)

### 3.4. Sync Mechanism

- New nodes request blocks from genesis
- Existing nodes sync missing blocks
- State sync (if needed)

## 3.15 Implementation Status (Current State)

Detailed assessment and roadmap: **BLOCKCHAIN_PLAN.md**.

**Already in place (MVP/prototype):**
- **Block Creator:** Block creation loop, mempool (`mempool.json`), chain state (`blocks.json`). Central API signs the decision (tx) and block-slot; Blocker verifies with the Central pubkey.
- **Transaction types:** Blocker accepts all 10 types (UserRegistration → Donate). The **App** submits **Follow** and **Unfollow**. The **Store** submits **StorageOperation** (contract envelope: hash + appSignature + storageNodeSignature + content) for post, react, comment, and chat_message.
- **Storage contract:** App ↔ Store sign a contract (V1 message / V2 contract hash); Store submits a StorageOperation tx; Blocker validates the contract hash and signatures.
- **Central API:** User registration, follow graph, store/block creator node registry, voucher, PRE rekey; decision + block-slot (random blocker selection, signs a SHA256 message).

**Not yet implemented / Differs from the proposal:**
- **UserRegistration tx:** The App only calls the registration API; it does not yet submit a UserRegistration tx to the chain.
- **CreatePost tx:** Only a StorageOperation from Store exists (with fileId, contract); there is no separate CreatePost tx from the App (postId, fileId, storageNodeId).
- **State from chain:** API/Store remain the source of truth (`users.json`, `user_follows.json`); there is no **Blockchain Indexer** to rebuild state from blocks.
- **Persistence:** JSON (users, blocks, mempool); no database yet.
- **P2P / Gossip:** Not yet; HTTP via Central only.
- **Consensus:** Random blocker selection; no PoA/PoS yet.
- **Inspector, Router nodes:** Not implemented.
- **D-Coin, Transfer, Donate:** Schema exists; no balances, reward distribution, or wallet yet.

**Conclusion:** The migration has reached **MVP** (storage + follow on-chain, block creation with Central coordination). Still incomplete: chain-derived state (indexer), P2P, real consensus, and D-Coin economics. Remaining gaps and the roadmap: **BLOCKCHAIN_PLAN.md**.

## 4. Next Steps

1. ~~**Prototype:** Implement a basic blockchain with 1–2 transaction types~~ → **Done (MVP):** StorageOperation, Follow/Unfollow, blocks + Central decision/slot.
2. **State & persistence:** Blockchain Indexer rebuilds state from blocks; replace JSON with a database (Phase 1 in BLOCKCHAIN_PLAN.md).
3. **Test:** Test with a small network (multiple blockers, store).
4. **Decentralization:** P2P gossip, defined consensus (PoA/round-robin) — Phase 2.
5. **Economy & security:** D-Coin, fee distribution, Transfer/Donate; secure wallet; audit — Phase 3.
6. **Optional:** App submits a UserRegistration tx after registration; submits a CreatePost tx (reference) after Store receives the file.
7. **Deploy / Migrate / Launch:** Testnet → migrate data → mainnet.

## 5. References

- Bitcoin: UTXO model, Proof of Work
- Ethereum: Account model, Smart contracts
- Hyperledger Fabric: Permissioned blockchain
- IPFS: Distributed file storage
- libp2p: P2P networking
