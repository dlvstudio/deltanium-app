# Block Creator Node - Chức Năng Chi Tiết

## Tổng Quan

Block Creator Nodes là các nodes quan trọng nhất trong mạng Deltanium blockchain, chịu trách nhiệm xử lý transactions và tạo blocks. Mỗi Block Creator node phải:
- Có cặp Public/Private Key riêng
- Được Central Node (deltanium.com) authenticate và authorize
- Stake D coins (bị penalty nếu không tạo block kịp thời)
- Nhận transaction fees khi tạo blocks

## Các Chức Năng Cụ Thể

### 1. Transaction Pool Management

#### 1.1. Nhận và Lưu Trữ Transactions
- **Nhận transactions từ network:**
  - Transactions được broadcast đến tất cả Block Creator nodes
  - Nhận các loại transactions:
    - UserRegistration
    - Follow/Unfollow
    - CreatePost
    - React/Comment
    - Transfer (D coin)
    - Donate
    - NodeRegistration
    - StorageOperation

- **Transaction Pool (Memory Pool):**
  - Lưu trữ pending transactions chờ được include vào block
  - Maintain transaction pool với capacity limit
  - Remove transactions sau khi được include trong block
  - Remove duplicate transactions

#### 1.2. Validate Transactions Trước Khi Add Vào Pool
- **Signature Verification:**
  - Verify digital signature của transaction
  - Verify public key của sender
  - Verify signature matches transaction data

- **Transaction Validity Checks:**
  - Check transaction format đúng
  - Check timestamp không quá cũ hoặc quá xa trong tương lai
  - Check nonce để prevent duplicate transactions
  - Check transaction type và data structure

- **State Validation:**
  - Check sender có đủ balance (cho Transfer/Donate)
  - Check user đã registered (cho các transactions khác)
  - Check không có double-spending
  - Check follow/unfollow relationships hợp lệ

- **Fee Validation:**
  - Check transaction có đủ fee
  - Prioritize transactions với fees cao hơn

#### 1.3. Transaction Prioritization
- **Prioritize theo fees:**
  - Transactions với fees cao hơn được ưu tiên
  - Tính toán fee per byte để optimize block space

- **Prioritize theo timestamp:**
  - Older transactions được ưu tiên (FIFO với fee consideration)
  - Prevent transaction starvation

- **Prioritize theo type:**
  - Critical transactions (node registration) có thể được ưu tiên
  - User transactions được xử lý công bằng

### 2. Block Creation (Khi Được Central Node Chọn)

#### 2.1. Nhận Block Creation Request từ Central Node
- **Central Node Selection:**
  - Central Node chọn Block Creator nào sẽ tạo block tiếp theo
  - Central Node ký vào quyết định và gửi đến selected node
  - Block Creator nhận request với:
    - Block creation authorization (signed by Central Node)
    - Time limit để tạo block
    - Previous block hash
    - Current blockchain state

#### 2.2. Select Transactions từ Pool
- **Transaction Selection Logic:**
  - Select transactions từ pool theo priority (fees, timestamp)
  - Fill block đến block size limit
  - Đảm bảo block không quá lớn
  - Balance giữa fees và transaction count

- **Transaction Ordering:**
  - Order transactions trong block
  - Đảm bảo dependencies được resolve (ví dụ: registration trước follow)

#### 2.3. Build Block Structure
- **Block Header:**
  - Previous block hash
  - Merkle root của transactions
  - Timestamp
  - Block height
  - Difficulty target
  - Nonce (nếu cần proof-of-work)
  - Block Creator's public key
  - Signature của Central Node authorization

- **Block Body:**
  - List of transactions
  - Transaction count
  - Total fees collected

- **Merkle Tree:**
  - Calculate Merkle root từ tất cả transactions
  - Build Merkle tree structure
  - Enable efficient transaction verification

#### 2.4. Sign Block
- **Block Signing:**
  - Sign block với Block Creator's private key
  - Include signature trong block header
  - Verify signature trước khi broadcast

#### 2.5. Broadcast Block
- **Block Propagation:**
  - Broadcast block đến tất cả nodes trong network
  - Send đến:
    - Other Block Creator nodes (để validate)
    - Inspector nodes (để audit)
    - User nodes (để sync)
    - Content Store nodes (để update state)
    - Router nodes (nếu cần)

- **Block Announcement:**
  - Announce block hash trước khi send full block
  - Nodes có thể request full block nếu cần

### 3. Block Validation (Validate Blocks của Nodes Khác)

#### 3.1. Nhận Blocks từ Other Block Creators
- **Block Reception:**
  - Nhận blocks được broadcast từ other Block Creator nodes
  - Verify block format đúng
  - Check block không duplicate

#### 3.2. Validate Block Structure
- **Header Validation:**
  - Verify previous block hash matches local chain
  - Verify Merkle root matches transactions
  - Verify timestamp hợp lệ
  - Verify block height đúng
  - Verify Central Node authorization signature
  - Verify Block Creator signature

#### 3.3. Validate All Transactions trong Block
- **Transaction Validation:**
  - Validate từng transaction trong block:
    - Signature verification
    - State validation
    - Double-spending check
    - Fee validation
  - Verify transaction order hợp lệ
  - Verify không có duplicate transactions

#### 3.4. Validate Block Against Local State
- **State Consistency:**
  - Check block không conflict với local blockchain state
  - Verify state transitions hợp lệ
  - Check balances, relationships, etc.

#### 3.5. Signal Acceptance hoặc Report Invalid
- **Acceptance Signal:**
  - Nếu block valid:
    - Add block vào local blockchain
    - Update local state
    - Broadcast acceptance signal đến network
    - Remove transactions từ pool (nếu có trong block)

- **Invalid Report:**
  - Nếu block invalid:
    - Report đến Central Node
    - Report đến Inspector nodes
    - Include reason for rejection
    - Sign report với Block Creator's key

### 4. Blockchain State Management

#### 4.1. Maintain Local Blockchain
- **Chain Storage:**
  - Store full blockchain locally
  - Maintain block index
  - Store block headers và bodies
  - Optimize storage với pruning (nếu cần)

#### 4.2. State Updates
- **Apply Blocks:**
  - Apply transactions trong block vào state
  - Update user registry
  - Update follow relationships
  - Update post references
  - Update D coin balances
  - Update node registry

#### 4.3. Fork Handling
- **Fork Detection:**
  - Detect khi có multiple chains
  - Compare chain lengths
  - Compare chain difficulty/work

- **Fork Resolution:**
  - Chọn longest chain
  - Revert transactions nếu cần (reorg)
  - Update state theo chain được chọn

#### 4.4. Chain Synchronization
- **Sync với Network:**
  - Request missing blocks từ other nodes
  - Verify và add blocks vào chain
  - Sync state với network

### 5. Communication với Central Node

#### 5.1. Node Registration
- **Initial Registration:**
  - Register với Central Node
  - Provide public key
  - Provide endpoint
  - Stake D coins
  - Receive authorization

#### 5.2. Heartbeat/Health Reporting
- **Status Updates:**
  - Send periodic heartbeat đến Central Node
  - Report node status (online, synced, etc.)
  - Report performance metrics

#### 5.3. Receive Block Creation Requests
- **Block Creation Authorization:**
  - Nhận requests từ Central Node
  - Verify Central Node signature
  - Check time limit
  - Create block trong time limit

#### 5.4. Report Issues
- **Invalid Block Reports:**
  - Report invalid blocks đến Central Node
  - Report malicious nodes
  - Request penalties

### 6. Fee Collection

#### 6.1. Collect Transaction Fees
- **Fee Accumulation:**
  - Collect fees từ transactions trong blocks mình tạo
  - Calculate total fees per block
  - Store fees trong wallet

#### 6.2. Fee Distribution
- **Fee Sharing (nếu có):**
  - Share fees với Central Node (nếu required)
  - Distribute fees theo rules

### 7. Penalty Handling

#### 7.1. Stake Management
- **Stake Locking:**
  - Lock D coins khi register làm Block Creator
  - Stake được lock trong suốt thời gian là Block Creator

#### 7.2. Penalty khi Không Tạo Block Kịp Thời
- **Timeout Penalty:**
  - Nếu được Central Node chọn nhưng không tạo block trong time limit
  - Central Node sẽ:
    - Cancel request
    - Select another Block Creator
    - Penalize node (mất một phần stake)
  - Block Creator nhận penalty notification

#### 7.3. Penalty khi Tạo Invalid Blocks
- **Invalid Block Penalty:**
  - Nếu tạo invalid block
  - Inspector nodes có thể report
  - Central Node có thể penalize
  - Mất stake hoặc bị remove khỏi network

### 8. Performance Optimization

#### 8.1. Transaction Pool Optimization
- **Efficient Storage:**
  - Use efficient data structures (hash maps, priority queues)
  - Index transactions by type, fee, timestamp
  - Fast lookup và removal

#### 8.2. Block Creation Optimization
- **Fast Block Assembly:**
  - Optimize transaction selection
  - Fast Merkle tree calculation
  - Parallel transaction validation (nếu possible)

#### 8.3. Validation Optimization
- **Fast Block Validation:**
  - Parallel transaction validation
  - Cache validation results
  - Optimize state lookups

## Luồng Hoạt Động Tổng Quan

### Luồng Tạo Block (Khi Được Chọn)

```
1. Nhận block creation request từ Central Node
   ↓
2. Verify Central Node authorization
   ↓
3. Select transactions từ pool (theo priority)
   ↓
4. Validate selected transactions
   ↓
5. Build block structure
   ↓
6. Calculate Merkle root
   ↓
7. Sign block với private key
   ↓
8. Broadcast block đến network
   ↓
9. Wait for validations từ other Block Creators
   ↓
10. Collect fees từ transactions
```

### Luồng Validate Block (Khi Nhận Block từ Node Khác)

```
1. Nhận block từ network
   ↓
2. Verify block format
   ↓
3. Verify Central Node authorization
   ↓
4. Verify Block Creator signature
   ↓
5. Validate all transactions trong block
   ↓
6. Verify block against local state
   ↓
7. Check for conflicts/forks
   ↓
8. If valid:
   - Add to local chain
   - Update state
   - Signal acceptance
   - Remove transactions từ pool
   ↓
9. If invalid:
   - Report to Central Node
   - Report to Inspector nodes
```

## Requirements và Constraints

### Technical Requirements
- **Storage:** Full blockchain state (có thể vài GB đến TB)
- **Network:** High bandwidth để broadcast blocks
- **CPU:** Fast để validate transactions và create blocks
- **Memory:** Đủ để maintain transaction pool

### Economic Requirements
- **Stake:** Phải stake D coins (bị penalty nếu fail)
- **Fees:** Nhận transaction fees khi tạo blocks
- **Costs:** Chi phí infrastructure (server, bandwidth, storage)

### Operational Requirements
- **Uptime:** Phải online và responsive
- **Sync:** Phải sync với network
- **Security:** Phải secure private keys
- **Monitoring:** Monitor performance và health

## API Endpoints (Nếu Implement)

### Internal APIs
- `POST /block/create` - Create block khi được Central Node authorize
- `POST /block/validate` - Validate block từ other nodes
- `GET /transactions/pool` - Get transaction pool
- `POST /transactions/add` - Add transaction to pool
- `GET /chain/status` - Get blockchain status
- `POST /chain/sync` - Sync với network

### External APIs (cho other nodes)
- `GET /block/{blockId}` - Get block by ID
- `POST /block/broadcast` - Broadcast block
- `POST /validation/signal` - Signal block acceptance/rejection
- `GET /transactions/pending` - Get pending transactions (nếu public)

## Security Considerations

### Key Management
- **Private Key Security:**
  - Store private key securely (HSM, encrypted storage)
  - Never expose private key
  - Use key rotation nếu cần

### Block Validation Security
- **Verify All Signatures:**
  - Always verify Central Node signatures
  - Always verify transaction signatures
  - Always verify block creator signatures

### Network Security
- **Secure Communication:**
  - Use TLS/SSL cho all communications
  - Authenticate messages
  - Prevent replay attacks

### State Security
- **State Integrity:**
  - Verify state transitions
  - Check for double-spending
  - Validate all state changes

## Monitoring và Logging

### Metrics to Monitor
- **Performance:**
  - Block creation time
  - Transaction validation time
  - Block validation time
  - Network latency

- **Health:**
  - Uptime
  - Sync status
  - Transaction pool size
  - Blockchain height

- **Economic:**
  - Fees collected
  - Stake locked
  - Penalties received

### Logging
- **Block Creation:**
  - Log mỗi block được tạo
  - Log transactions included
  - Log fees collected

- **Block Validation:**
  - Log blocks validated
  - Log invalid blocks và reasons
  - Log acceptance/rejection signals

- **Errors:**
  - Log all errors
  - Log network issues
  - Log validation failures

## Kết Luận

Block Creator Nodes là backbone của Deltanium blockchain, chịu trách nhiệm:
1. ✅ **Process transactions** và maintain transaction pool
2. ✅ **Create blocks** khi được Central Node chọn
3. ✅ **Validate blocks** từ other Block Creators
4. ✅ **Maintain blockchain state** locally
5. ✅ **Communicate** với Central Node và other nodes
6. ✅ **Collect fees** và manage stake
7. ✅ **Handle penalties** nếu fail

Đây là một role quan trọng và yêu cầu high performance, security, và reliability.













