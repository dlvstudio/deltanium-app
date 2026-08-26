# Deltanium Block and Transaction Model

## Overview

The Deltanium blockchain uses a **Block** structure to store **Transactions**. Each block contains a list of transactions, secured by a Merkle tree and digital signatures from Block Creator nodes.

---

## 1. Block Structure

### Block Definition

```csharp
public record Block
{
    public string Id { get; init; }                              // Unique block identifier (hash)
    public string PreviousId { get; init; }                     // Hash of previous block (chain linking)
    public long Height { get; init; }                           // Block height in blockchain
    public long Timestamp { get; init; }                        // Unix timestamp (seconds)
    public List<Transaction> Transactions { get; init; }        // List of transactions in block
    public string MerkleRoot { get; init; }                     // Merkle tree root of transactions
    public string CreatorPublicKey { get; init; }               // Block creator's public key
    public string CentralAuthorizationSignature { get; init; }  // Signature from Central Node
    public string CreatorSignature { get; init; }               // Signature from block creator
}
```

### Block Fields Description

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| **Id** | `string` | SHA256 hash of block header | `a1b2c3d4e5f6g7h8...` |
| **PreviousId** | `string` | Hash of previous block (creates chain) | `0000000000000000...` |
| **Height** | `long` | Sequential block number (0, 1, 2, ...) | `12345` |
| **Timestamp** | `long` | Unix timestamp when block created | `1707550800` |
| **Transactions** | `List<Transaction>` | All transactions included in this block | `[tx1, tx2, tx3, ...]` |
| **MerkleRoot** | `string` | SHA256 hash of Merkle tree of all txs | `merkle_root_hash...` |
| **CreatorPublicKey** | `string` | Public key of Block Creator node | `creator_pubkey...` |
| **CentralAuthorizationSignature** | `string` | Signature proving Central Node authorized this block | `central_sig...` |
| **CreatorSignature** | `string` | Signature from block creator's private key | `creator_sig...` |

### Merkle Root Calculation

The **Merkle Root** is calculated from all transactions in the block:

```csharp
public static string CalculateMerkleRoot(IEnumerable<Transaction> txs)
{
    var hashes = txs.Select(tx => Hash(tx.Id)).ToList();
    if (!hashes.Any()) return string.Empty;
    
    // Build Merkle tree bottom-up
    while (hashes.Count > 1)
    {
        var next = new List<string>();
        for (int i = 0; i < hashes.Count; i += 2)
        {
            if (i + 1 < hashes.Count)
                next.Add(Hash(hashes[i] + hashes[i + 1]));
            else
                next.Add(hashes[i]);  // Odd transaction, hash with itself
        }
        hashes = next;
    }
    return hashes[0];
}
```

**Purpose:** Provides quick verification of transaction integrity. If any transaction changes, the Merkle root changes completely.

### Block Signature Verification

A valid block requires **two signatures**:

1. **CentralAuthorizationSignature**
   - Signed by Central Node
   - Proves Central Node approved this block
   - Prevents unauthorized block creation

2. **CreatorSignature**
   - Signed by Block Creator node's private key
   - Proves the block creator created this block
   - Prevents tampering after creation

---

## 2. Transaction Structure

### Transaction Definition

```csharp
public enum TransactionType
{
    UserRegistration,    // User registers with public key
    Follow,             // User A follows User B
    Unfollow,           // User A unfollows User B
    CreatePost,         // User creates a post/content
    React,              // User reacts to content (like, love, etc.)
    Comment,            // User comments on content
    NodeRegistration,   // Storage node registers
    StorageOperation,   // Store/retrieve files
    Transfer,           // Transfer D coins
    Donate              // Donate D coins to content owner
}

public record Transaction
{
    public string Id { get; init; }                     // Transaction ID (GUID)
    public TransactionType Type { get; init; }         // Type of transaction
    public string From { get; init; }                  // Sender's public key
    public string? To { get; init; }                   // Recipient's public key (nullable)
    public Dictionary<string, object> Data { get; init; } // Transaction-specific data
    public long Timestamp { get; init; }               // Unix timestamp
    public long Fee { get; init; }                     // Transaction fee (in D coins)
    public string Signature { get; init; }             // Digital signature of transaction
}
```

### Transaction Fields Description

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| **Id** | `string` | Unique transaction identifier (GUID) | `550e8400-e29b-41d4-a716-446655440000` |
| **Type** | `TransactionType` | Category of transaction | `CreatePost` |
| **From** | `string` | Public key of transaction sender | `user_pubkey_a...` |
| **To** | `string?` | Public key of recipient (null for broadcasts) | `user_pubkey_b...` |
| **Data** | `Dictionary<string, object>` | Transaction-specific payload | `{ "contentId": "...", "text": "..." }` |
| **Timestamp** | `long` | Unix timestamp of creation | `1707550800` |
| **Fee** | `long` | Amount in D coins for Block Creator | `100` |
| **Signature** | `string` | Sender's digital signature | `sig_hex_string...` |

### Transaction Signature

Every transaction is signed to prevent tampering:

```
Signature = Sign(From_PrivateKey, JSON(Type + From + To + Data + Timestamp + Fee))
```

Verification verifies that `Data` hasn't been modified:
```
Verify(From_PublicKey, Signature, Message) => true/false
```

---

## 3. Transaction Types in Detail

### 3.1 UserRegistration

**Purpose:** Register a new user on the blockchain

**Data Schema:**
```json
{
    "publicKey": "user_public_key",
    "email": "user@example.com",
    "fullName": "John Doe",
    "dateOfBirth": "1990-01-15",
    "bio": "My bio here",
    "avatarUrl": "https://example.com/avatar.jpg"
}
```

**Example Transaction:**
```json
{
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "type": "UserRegistration",
    "from": "user_pubkey_a...",
    "to": null,
    "data": {
        "publicKey": "user_pubkey_a...",
        "email": "john@example.com",
        "fullName": "John Doe",
        "dateOfBirth": "1990-01-15",
        "bio": "Software developer",
        "avatarUrl": "https://deltanium.com/avatars/john.jpg"
    },
    "timestamp": 1707550800,
    "fee": 500,
    "signature": "digital_signature_hex..."
}
```

**Processing:**
- Central API validates user doesn't already exist
- Stores user profile in `users.json`
- Block Creator includes transaction in next block
- User can now post content and interact

---

### 3.2 Follow

**Purpose:** User A follows User B

**Data Schema:**
```json
{
    "targetPublicKey": "user_pubkey_b",
    "metadata": {
        "timestamp": 1707550800,
        "signedData": "message_signed"
    }
}
```

**Example Transaction:**
```json
{
    "id": "550e8400-e29b-41d4-a716-446655440001",
    "type": "Follow",
    "from": "user_pubkey_a...",
    "to": "user_pubkey_b...",
    "data": {
        "targetPublicKey": "user_pubkey_b...",
        "timestamp": 1707550800,
        "signedData": "Follow Request from A to B"
    },
    "timestamp": 1707550800,
    "fee": 50,
    "signature": "digital_signature_hex..."
}
```

**Processing:**
- Central API verifies User B exists
- Records follow relationship: A → B
- User B appears in A's "following" list
- User A appears in B's "followers" list
- Stored in `user_follows.json` on Central API

---

### 3.3 Unfollow

**Purpose:** User A unfollows User B

**Data Schema:**
```json
{
    "targetPublicKey": "user_pubkey_b",
    "reason": "No longer interested" // optional
}
```

**Example Transaction:**
```json
{
    "id": "550e8400-e29b-41d4-a716-446655440002",
    "type": "Unfollow",
    "from": "user_pubkey_a...",
    "to": "user_pubkey_b...",
    "data": {
        "targetPublicKey": "user_pubkey_b...",
        "reason": "Content no longer relevant"
    },
    "timestamp": 1707550805,
    "fee": 50,
    "signature": "digital_signature_hex..."
}
```

**Processing:**
- Central API removes follow relationship A → B
- A's "following" list updated
- B's "followers" list updated

---

### 3.4 CreatePost

**Purpose:** User creates a post with encrypted content

**Data Schema:**
```json
{
    "fileId": "unique_file_id",
    "firstBlockId": "block_id_0",
    "type": "post",
    "shareType": "public|followers|private",
    "encryptedType": "ECIES",
    "encryptedKey": "Base64_encrypted_key",
    "recipientPubKey": "recipient_key_optional",
    "metadata": {
        "text": "Post content",
        "mediaUrls": ["url1", "url2"],
        "hashtags": ["tag1", "tag2"]
    }
}
```

**PRE Hybrid (For Followers-Only):**
```json
{
    "fileId": "unique_file_id",
    "firstBlockId": "block_id_0",
    "type": "post",
    "shareType": "followers",
    "encryptedType": "CPRE",
    "ownerPubKey": "user_pubkey_a...",
    "policyTag": "followers:2025",
    "capsuleFor": "tag",
    "policyScheme": "CPRE",
    "encryptedKey": "Base64_encrypted_key_for_author",
    "encapsulatedForRecipient": "Base64_PRE_capsule",
    "metadata": {
        "text": "Post visible to followers only",
        "mediaUrls": []
    }
}
```

**Example Transaction:**
```json
{
    "id": "550e8400-e29b-41d4-a716-446655440003",
    "type": "CreatePost",
    "from": "user_pubkey_a...",
    "to": null,
    "data": {
        "fileId": "file_12345",
        "firstBlockId": "block_0",
        "type": "post",
        "shareType": "public",
        "encryptedType": "ECIES",
        "encryptedKey": "BASE64_ENCRYPTED_KEY",
        "metadata": {
            "text": "Hello Deltanium! #web3 #blockchain",
            "mediaUrls": ["https://store.deltanium.com/file_12345/media_0"],
            "hashtags": ["web3", "blockchain"]
        }
    },
    "timestamp": 1707550810,
    "fee": 100,
    "signature": "digital_signature_hex..."
}
```

**Processing:**
- Block Creator validates transaction signature
- Store node uploads encrypted content blocks
- Metadata stored on Store node
- Transaction included in next block
- Post appears in creator's timeline
- Followers can see (if shareType allows)

---

### 3.5 React

**Purpose:** User reacts to content (like, love, haha, angry, etc.)

**Data Schema:**
```json
{
    "contentId": "referenced_file_id",
    "reactionType": "like|love|haha|wow|angry|sad",
    "timestamp": 1707550815
}
```

**Example Transaction:**
```json
{
    "id": "550e8400-e29b-41d4-a716-446655440004",
    "type": "React",
    "from": "user_pubkey_c...",
    "to": "user_pubkey_a...",
    "data": {
        "contentId": "file_12345",
        "reactionType": "love",
        "timestamp": 1707550815
    },
    "timestamp": 1707550815,
    "fee": 50,
    "signature": "digital_signature_hex..."
}
```

**Processing:**
- Store node records reaction
- Updates reaction count on content
- Content owner receives notification
- Reaction stored with timestamp (prevents duplicate reactions)
- Block Creator may collect fee portion

---

### 3.6 Comment

**Purpose:** User comments on content

**Data Schema:**
```json
{
    "contentId": "referenced_file_id",
    "commentText": "My comment here",
    "parentCommentId": "parent_comment_id_optional",
    "encryptedContent": "Base64_encrypted_comment"
}
```

**Example Transaction:**
```json
{
    "id": "550e8400-e29b-41d4-a716-446655440005",
    "type": "Comment",
    "from": "user_pubkey_b...",
    "to": "user_pubkey_a...",
    "data": {
        "contentId": "file_12345",
        "commentText": "Great post!",
        "parentCommentId": null,
        "encryptedContent": "BASE64_ENCRYPTED"
    },
    "timestamp": 1707550820,
    "fee": 50,
    "signature": "digital_signature_hex..."
}
```

**Processing:**
- Store node creates comment entry
- Links to parent content via `contentId`
- Optional reply-to functionality via `parentCommentId`
- Content owner notified of comment
- Comment encrypted with author's key

---

### 3.7 NodeRegistration

**Purpose:** Storage node registers with the network

**Data Schema:**
```json
{
    "nodePublicKey": "node_public_key",
    "nodeEndpoint": "https://store.example.com",
    "voucher": "registration_voucher_code",
    "capacity": 1000000000,
    "metadata": {
        "location": "US-East",
        "bandwidthMbps": 1000
    }
}
```

**Example Transaction:**
```json
{
    "id": "550e8400-e29b-41d4-a716-446655440006",
    "type": "NodeRegistration",
    "from": "node_pubkey...",
    "to": null,
    "data": {
        "nodePublicKey": "node_pubkey...",
        "nodeEndpoint": "https://store1.deltanium.com",
        "voucher": "VOUCHER_0001",
        "capacity": 5000000000,
        "metadata": {
            "location": "US-West",
            "bandwidthMbps": 1000
        }
    },
    "timestamp": 1707550825,
    "fee": 1000,
    "signature": "digital_signature_hex..."
}
```

**Processing:**
- Central API validates voucher (must be unused)
- Stores node in `nodes.json`
- Marks voucher as used
- Node can now accept file uploads
- Discovered by users via `GET /api/storenode/list`

---

### 3.8 StorageOperation

**Purpose:** Record file storage, retrieval, or deletion

**Data Schema:**
```json
{
    "operationType": "store|retrieve|delete",
    "contentId": "file_id",
    "ownerPublicKey": "owner_pubkey",
    "size": 1048576,
    "duration": "days_stored"
}
```

**Example Transaction:**
```json
{
    "id": "550e8400-e29b-41d4-a716-446655440007",
    "type": "StorageOperation",
    "from": "node_pubkey...",
    "to": "user_pubkey_a...",
    "data": {
        "operationType": "store",
        "contentId": "file_12345",
        "ownerPublicKey": "user_pubkey_a...",
        "size": 2097152,
        "duration": 30
    },
    "timestamp": 1707550830,
    "fee": 200,
    "signature": "digital_signature_hex..."
}
```

**Processing:**
- Storage node confirms file receipt
- Updates storage quotas
- Records file location for retrieval
- Owner may pay storage fees

---

### 3.9 Transfer

**Purpose:** Transfer D coins from one user to another

**Data Schema:**
```json
{
    "amount": 1000,
    "recipientPublicKey": "recipient_pubkey",
    "message": "Payment for services" // optional
}
```

**Example Transaction:**
```json
{
    "id": "550e8400-e29b-41d4-a716-446655440008",
    "type": "Transfer",
    "from": "user_pubkey_a...",
    "to": "user_pubkey_b...",
    "data": {
        "amount": 5000,
        "recipientPublicKey": "user_pubkey_b...",
        "message": "Payment for design work"
    },
    "timestamp": 1707550835,
    "fee": 100,
    "signature": "digital_signature_hex..."
}
```

**Processing:**
- Verify sender has sufficient balance
- Deduct amount + fee from sender
- Add amount to recipient
- Block Creator receives fee
- Transaction recorded on blockchain for auditing

---

### 3.10 Donate

**Purpose:** Donate D coins to content owner (tipping)

**Data Schema:**
```json
{
    "amount": 500,
    "contentId": "file_id_referenced",
    "message": "Love your content!" // optional
}
```

**Example Transaction:**
```json
{
    "id": "550e8400-e29b-41d4-a716-446655440009",
    "type": "Donate",
    "from": "user_pubkey_c...",
    "to": "user_pubkey_a...",
    "data": {
        "amount": 1000,
        "contentId": "file_12345",
        "message": "Amazing content, love it!"
    },
    "timestamp": 1707550840,
    "fee": 50,
    "signature": "digital_signature_hex..."
}
```

**Processing:**
- Verify donor has sufficient balance
- Transfer amount to content owner
- Block Creator receives fee
- Content owner notified of tip
- Donation linked to specific content for tracking

---

## 4. Block Creation Flow

### Step-by-Step Process

```
1. Transactions Submitted
   ↓
2. Block Creator receives authorization from Central Node
   ↓
3. Select pending transactions from pool (prioritized by fee)
   ↓
4. Verify each transaction:
   - Valid signature
   - Valid timestamp (within time window)
   - Sender has sufficient balance/permissions
   ↓
5. Build Block Structure:
   - Id (hash of block header)
   - PreviousId (from previous block)
   - Height (incremented)
   - Timestamp (current time)
   - Transactions (selected txs)
   - MerkleRoot (calculated)
   - CreatorPublicKey
   ↓
6. Sign with Creator's Private Key
   → CreatorSignature
   ↓
7. Receive CentralAuthorizationSignature from Central Node
   ↓
8. Add Block to Blockchain
   ↓
9. Broadcast Block to Network
   ↓
10. Update Transaction Pool (remove included txs)
```

### Block Creation Example

```csharp
// 1. Collect transactions
var transactions = transactionPool
    .OrderByDescending(tx => tx.Fee)
    .ThenByDescending(tx => tx.Timestamp)
    .Take(500)  // Max 500 txs per block
    .ToList();

// 2. Validate transactions
foreach (var tx in transactions)
{
    if (!ValidateTransaction(tx))
        continue;  // Skip invalid
}

// 3. Build block
var block = new Block
{
    Id = BlockHash(blockHeader),
    PreviousId = lastBlock.Id,
    Height = lastBlock.Height + 1,
    Timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
    Transactions = transactions,
    MerkleRoot = Block.CalculateMerkleRoot(transactions),
    CreatorPublicKey = nodeConfig.NodePublicKey
};

// 4. Sign with private key
block.CreatorSignature = Sign(nodeConfig.NodePrivateKey, block);

// 5. Get authorization from Central
block.CentralAuthorizationSignature = await centralClient.AuthorizeBlock(block);

// 6. Add to blockchain
blockchain.Add(block);

// 7. Broadcast to network
await BroadcastBlock(block);
```

---

## 5. Transaction Fees & Economics

### Fee Structure

| Transaction Type | Min Fee | Typical Fee | Description |
|------------------|---------|------------|-------------|
| UserRegistration | 500 | 500-1000 | Prevents spam registrations |
| Follow | 50 | 50-100 | Social operations |
| Unfollow | 50 | 50-100 | Social operations |
| CreatePost | 100 | 100-500 | Content creation |
| React | 50 | 50 | Lightweight interaction |
| Comment | 50 | 50-100 | Content interaction |
| NodeRegistration | 1000 | 1000-5000 | High value for infrastructure |
| StorageOperation | 100 | 100-1000 | Depends on file size |
| Transfer | 100 | 100-1000 | Amount-dependent |
| Donate | 50 | 50 | Percentage-based in future |

### Fee Distribution

```
User Pays:  Transaction Amount + Transaction Fee
            ↓
            Sender's Balance: - (Amount + Fee)
            ↓
Block Creator: + Fee (collected from all txs in block)
Recipient:    + Amount (for transfer/donate)
```

**Example Transfer:**
```
Alice sends 1000 coins to Bob with 100 fee
Alice balance: -1100
Bob balance:   +1000
Block Creator: +100
```

---

## 6. Security Considerations

### Transaction Validation Checklist

Before including a transaction in a block, verify:

- ✅ **Signature Valid:** `Verify(From_PubKey, Signature, Message) == true`
- ✅ **Timestamp Valid:** Within last 5 minutes
- ✅ **Sender Exists:** User registered on blockchain
- ✅ **Type Valid:** Known transaction type
- ✅ **Balance Sufficient:** For Transfer/Donate/Fee
- ✅ **Data Complete:** All required fields present
- ✅ **No Double Spend:** Transaction not already in previous blocks

### Block Validation Checklist

When receiving a block from network, verify:

- ✅ **Block Hash Valid:** Hash matches block data
- ✅ **PreviousId Correct:** Links to previous block
- ✅ **Height Correct:** Incremented from previous
- ✅ **Merkle Root Valid:** Matches calculated root
- ✅ **Creator Signature Valid:** Signed by declared creator
- ✅ **Central Signature Valid:** Authorized by Central Node
- ✅ **All Transactions Valid:** Each tx passes validation
- ✅ **No Duplicate Transactions:** Across previous blocks

---

## 7. Data Persistence

### JSON Storage (Current MVP)

Files stored in deltanium-api:

```
{
  "users.json": [{id, pubKey, email, name, ...}],
  "user_follows.json": [{follower, following}],
  "nodes.json": [{nodeId, endpoint, pubKey, ...}],
  "vouchers.json": [{code, used, usedBy, ...}],
  "stored_files.json": [{fileId, ownerId, nodeId, ...}],
  "user_rekeys.json": [{authorId, followerId, rekey, tag, ...}],
  "conversations.json": [{id, participants, messages, ...}],
  "chat_messages.json": [{id, conversationId, sender, text, ...}],
  "signaling_messages.json": [{id, from, to, data, ...}],
  "online_sessions.json": [{userId, nodeId, timestamp, ...}]
}
```

### Future: Database Migration

When scaling:

1. **PostgreSQL** for relational data (users, follows, transactions)
2. **MongoDB** for documents (posts metadata, comments)
3. **Redis** for caching (transaction pool, active sessions)
4. **File Storage** for encrypted content (S3/IPFS)

---

## 8. Example Complete Flow

### Scenario: User A Creates and Shares a Post to Followers

**Step 1: User A Registers**
```
Transaction: UserRegistration
From: user_a_pubkey
Type: UserRegistration
Data: { email, fullName, bio, ... }
Fee: 500
Block #0: Included in block
```

**Step 2: User B, C, D Register**
```
Similar to User A, included in blocks #1-3
```

**Step 3: User B Follows User A**
```
Transaction: Follow
From: user_b_pubkey
To: user_a_pubkey
Type: Follow
Data: { targetPublicKey: user_a_pubkey }
Fee: 50
Block #4: Included in block
Central API Updates: user_b → follows → user_a
```

**Step 4: User C Follows User A**
```
Similar to User B, included in block #5
```

**Step 5: User A Creates Followers-Only Post**
```
Transaction: CreatePost
From: user_a_pubkey
Type: CreatePost
Data: {
    fileId: "file_xyz",
    shareType: "followers",
    encryptedType: "CPRE",
    ownerPubKey: user_a_pubkey,
    policyTag: "followers:2025",
    capsuleFor: "tag",
    encryptedKey: ECIES(K, user_a_pubkey),
    encapsulatedForRecipient: PRE.encapsulate(K, user_a_pubkey, "followers:2025")
}
Fee: 200
Block #6: Included in block
```

**Step 6: A Uploads Rekeys**
```
POST /api/policy/upload-rekeys-batch
{
    rekeys: [
        {
            followingPubKey: user_a_pubkey,
            followerPubKey: user_b_pubkey,
            rkBase64: generateRekey(sk_A, pk_B, "followers:2025")
        },
        {
            followingPubKey: user_a_pubkey,
            followerPubKey: user_c_pubkey,
            rkBase64: generateRekey(sk_A, pk_C, "followers:2025")
        }
    ]
}
```

**Step 7: User B Views Followers Feed**
```
GET /api/post/following-feed
Returns: Post from User A with PRE fields
```

**Step 8: User B Decrypts Post**
```
1. Request rekey from Central:
   POST /api/policy/fetch-rekey
   Body: { followerPubKey: user_b, followingPubKey: user_a_pubkey, tag: "followers:2025" }
   
2. Central verifies: B follows A ✓ + PoP ✓
   Returns: rk(A→B)

3. B's device:
   - Re-encrypt: capsule_for_B = reencrypt(capsule, rk_AB)
   - Decapsulate: K = decapsulate(capsule_for_B, sk_B)
   
4. Download content blocks + decrypt with K
```

**Step 9: User B Reacts to Post**
```
Transaction: React
From: user_b_pubkey
To: user_a_pubkey
Type: React
Data: { contentId: "file_xyz", reactionType: "love" }
Fee: 50
Block #7: Included in block
```

**Result:**
- Post created, encrypted, and shared to followers safely
- Followers can decrypt and view content
- Author receives notification of reactions
- All transactions recorded on blockchain immutably
- Block Creator nodes earned fees: 200 + 50 = 250 coins

---

## 9. Best Practices

### For Transaction Creation

1. ✅ Always calculate Fee based on transaction size and type
2. ✅ Include valid Timestamp (within 5 minutes of now)
3. ✅ Sign with private key ONLY on client device
4. ✅ Never transmit private key to server
5. ✅ Verify signature locally before submitting
6. ✅ Handle replay attacks with unique Timestamps

### For Block Creation

1. ✅ Request authorization before creating block
2. ✅ Validate ALL transactions before including
3. ✅ Calculate MerkleRoot correctly
4. ✅ Sign block with private key
5. ✅ Broadcast to all nodes immediately
6. ✅ Update transaction pool after block inclusion

### For Network Participants

1. ✅ Validate block signature from creator
2. ✅ Validate central authorization signature
3. ✅ Verify MerkleRoot before acceptance
4. ✅ Reject blocks with invalid transactions
5. ✅ Report suspicious blocks to Central Node

---

## 10. Testing

### Unit Tests Examples

```csharp
[Test]
public void CreateBlock_CalculatesMerkleRootCorrectly()
{
    var txs = new[] {
        new Transaction { Id = "tx1", ... },
        new Transaction { Id = "tx2", ... }
    };
    
    var merkle = Block.CalculateMerkleRoot(txs);
    
    Assert.That(merkle, Is.Not.Empty);
    Assert.That(merkle.Length, Is.EqualTo(64)); // SHA256 = 32 bytes = 64 hex chars
}

[Test]
public void Transaction_ValidateSignature_ReturnsTrueForValidSignature()
{
    var sender = "user_pubkey...";
    var message = sender + "data...";
    var signature = Sign(privateKey, message);
    var tx = new Transaction { From = sender, Signature = signature };
    
    var isValid = VerifySignature(tx.From, tx.Signature, message);
    
    Assert.That(isValid, Is.True);
}

[Test]
public void Block_ValidateStructure_RejectsInvalidPreviousHash()
{
    var block = new Block { PreviousId = "invalid_hash", ... };
    var lastBlock = blockchain.Last();
    
    var isValid = ValidateBlockStructure(block, lastBlock);
    
    Assert.That(isValid, Is.False);
}
```

---

## 11. Reference

- [Deltanium API Documentation](./README.md)
- [Deltanium Store Guide](../deltanium-store/README.md)
- [Deltanium Blocker Implementation](../deltanium-blocker/README.md)
- [PRE Security Model](./BLOCKCHAIN_IMPLEMENTATION.md)

---

**Last Updated:** February 2026
**Status:** Active Development
