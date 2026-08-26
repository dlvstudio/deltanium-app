# Block Creator Node - Detailed Functions

## Overview

Block Creator Nodes are the most important nodes in the Deltanium blockchain network, responsible for processing transactions and creating blocks. Each Block Creator node must:
- Have its own Public/Private Key pair
- Be authenticated and authorized by the Central Node (deltanium.com)
- Stake D coins (penalized if it fails to create a block in time)
- Receive transaction fees when creating blocks

## Specific Functions

### 1. Transaction Pool Management

#### 1.1. Receive and Store Transactions
- **Receive transactions from the network:**
  - Transactions are broadcast to all Block Creator nodes
  - Receive the following transaction types:
    - UserRegistration
    - Follow/Unfollow
    - CreatePost
    - React/Comment
    - Transfer (D coin)
    - Donate
    - NodeRegistration
    - StorageOperation

- **Transaction Pool (Memory Pool):**
  - Store pending transactions waiting to be included in a block
  - Maintain the transaction pool with a capacity limit
  - Remove transactions after they are included in a block
  - Remove duplicate transactions

#### 1.2. Validate Transactions Before Adding to the Pool
- **Signature Verification:**
  - Verify the digital signature of the transaction
  - Verify the sender's public key
  - Verify the signature matches the transaction data

- **Transaction Validity Checks:**
  - Check that the transaction format is correct
  - Check that the timestamp is not too old or too far in the future
  - Check the nonce to prevent duplicate transactions
  - Check the transaction type and data structure

- **State Validation:**
  - Check that the sender has sufficient balance (for Transfer/Donate)
  - Check that the user is registered (for other transactions)
  - Check that there is no double-spending
  - Check that follow/unfollow relationships are valid

- **Fee Validation:**
  - Check that the transaction has a sufficient fee
  - Prioritize transactions with higher fees

#### 1.3. Transaction Prioritization
- **Prioritize by fees:**
  - Transactions with higher fees are prioritized
  - Calculate fee per byte to optimize block space

- **Prioritize by timestamp:**
  - Older transactions are prioritized (FIFO with fee consideration)
  - Prevent transaction starvation

- **Prioritize by type:**
  - Critical transactions (node registration) may be prioritized
  - User transactions are processed fairly

### 2. Block Creation (When Selected by the Central Node)

#### 2.1. Receive Block Creation Request from the Central Node
- **Central Node Selection:**
  - The Central Node selects which Block Creator will create the next block
  - The Central Node signs the decision and sends it to the selected node
  - The Block Creator receives the request with:
    - Block creation authorization (signed by Central Node)
    - Time limit to create the block
    - Previous block hash
    - Current blockchain state

#### 2.2. Select Transactions from the Pool
- **Transaction Selection Logic:**
  - Select transactions from the pool by priority (fees, timestamp)
  - Fill the block up to the block size limit
  - Ensure the block is not too large
  - Balance fees and transaction count

- **Transaction Ordering:**
  - Order transactions within the block
  - Ensure dependencies are resolved (for example: registration before follow)

#### 2.3. Build Block Structure
- **Block Header:**
  - Previous block hash
  - Merkle root of the transactions
  - Timestamp
  - Block height
  - Difficulty target
  - Nonce (if proof-of-work is needed)
  - Block Creator's public key
  - Signature of the Central Node authorization

- **Block Body:**
  - List of transactions
  - Transaction count
  - Total fees collected

- **Merkle Tree:**
  - Calculate the Merkle root from all transactions
  - Build the Merkle tree structure
  - Enable efficient transaction verification

#### 2.4. Sign Block
- **Block Signing:**
  - Sign the block with the Block Creator's private key
  - Include the signature in the block header
  - Verify the signature before broadcast

#### 2.5. Broadcast Block
- **Block Propagation:**
  - Broadcast the block to all nodes in the network
  - Send to:
    - Other Block Creator nodes (to validate)
    - Inspector nodes (to audit)
    - User nodes (to sync)
    - Content Store nodes (to update state)
    - Router nodes (if needed)

- **Block Announcement:**
  - Announce the block hash before sending the full block
  - Nodes can request the full block if needed

### 3. Block Validation (Validate Blocks from Other Nodes)

#### 3.1. Receive Blocks from Other Block Creators
- **Block Reception:**
  - Receive blocks broadcast from other Block Creator nodes
  - Verify that the block format is correct
  - Check that the block is not a duplicate

#### 3.2. Validate Block Structure
- **Header Validation:**
  - Verify the previous block hash matches the local chain
  - Verify the Merkle root matches the transactions
  - Verify the timestamp is valid
  - Verify the block height is correct
  - Verify the Central Node authorization signature
  - Verify the Block Creator signature

#### 3.3. Validate All Transactions in the Block
- **Transaction Validation:**
  - Validate each transaction in the block:
    - Signature verification
    - State validation
    - Double-spending check
    - Fee validation
  - Verify that the transaction order is valid
  - Verify that there are no duplicate transactions

#### 3.4. Validate Block Against Local State
- **State Consistency:**
  - Check that the block does not conflict with the local blockchain state
  - Verify that state transitions are valid
  - Check balances, relationships, etc.

#### 3.5. Signal Acceptance or Report Invalid
- **Acceptance Signal:**
  - If the block is valid:
    - Add the block to the local blockchain
    - Update local state
    - Broadcast an acceptance signal to the network
    - Remove transactions from the pool (if they are in the block)

- **Invalid Report:**
  - If the block is invalid:
    - Report to the Central Node
    - Report to Inspector nodes
    - Include the reason for rejection
    - Sign the report with the Block Creator's key

### 4. Blockchain State Management

#### 4.1. Maintain Local Blockchain
- **Chain Storage:**
  - Store the full blockchain locally
  - Maintain a block index
  - Store block headers and bodies
  - Optimize storage with pruning (if needed)

#### 4.2. State Updates
- **Apply Blocks:**
  - Apply the transactions in the block to state
  - Update the user registry
  - Update follow relationships
  - Update post references
  - Update D coin balances
  - Update the node registry

#### 4.3. Fork Handling
- **Fork Detection:**
  - Detect when there are multiple chains
  - Compare chain lengths
  - Compare chain difficulty/work

- **Fork Resolution:**
  - Choose the longest chain
  - Revert transactions if needed (reorg)
  - Update state according to the chosen chain

#### 4.4. Chain Synchronization
- **Sync with the Network:**
  - Request missing blocks from other nodes
  - Verify and add blocks to the chain
  - Sync state with the network

### 5. Communication with the Central Node

#### 5.1. Node Registration
- **Initial Registration:**
  - Register with the Central Node
  - Provide public key
  - Provide endpoint
  - Stake D coins
  - Receive authorization

#### 5.2. Heartbeat/Health Reporting
- **Status Updates:**
  - Send a periodic heartbeat to the Central Node
  - Report node status (online, synced, etc.)
  - Report performance metrics

#### 5.3. Receive Block Creation Requests
- **Block Creation Authorization:**
  - Receive requests from the Central Node
  - Verify the Central Node signature
  - Check the time limit
  - Create the block within the time limit

#### 5.4. Report Issues
- **Invalid Block Reports:**
  - Report invalid blocks to the Central Node
  - Report malicious nodes
  - Request penalties

### 6. Fee Collection

#### 6.1. Collect Transaction Fees
- **Fee Accumulation:**
  - Collect fees from transactions in blocks this node creates
  - Calculate total fees per block
  - Store fees in the wallet

#### 6.2. Fee Distribution
- **Fee Sharing (if applicable):**
  - Share fees with the Central Node (if required)
  - Distribute fees according to the rules

### 7. Penalty Handling

#### 7.1. Stake Management
- **Stake Locking:**
  - Lock D coins when registering as a Block Creator
  - Stake remains locked for the entire time as a Block Creator

#### 7.2. Penalty for Not Creating a Block in Time
- **Timeout Penalty:**
  - If selected by the Central Node but the block is not created within the time limit
  - The Central Node will:
    - Cancel the request
    - Select another Block Creator
    - Penalize the node (lose a portion of stake)
  - The Block Creator receives a penalty notification

#### 7.3. Penalty for Creating Invalid Blocks
- **Invalid Block Penalty:**
  - If an invalid block is created
  - Inspector nodes may report it
  - The Central Node may penalize
  - Lose stake or be removed from the network

### 8. Performance Optimization

#### 8.1. Transaction Pool Optimization
- **Efficient Storage:**
  - Use efficient data structures (hash maps, priority queues)
  - Index transactions by type, fee, timestamp
  - Fast lookup and removal

#### 8.2. Block Creation Optimization
- **Fast Block Assembly:**
  - Optimize transaction selection
  - Fast Merkle tree calculation
  - Parallel transaction validation (if possible)

#### 8.3. Validation Optimization
- **Fast Block Validation:**
  - Parallel transaction validation
  - Cache validation results
  - Optimize state lookups

## Overall Operating Flows

### Block Creation Flow (When Selected)

```
1. Receive block creation request from the Central Node
   ↓
2. Verify Central Node authorization
   ↓
3. Select transactions from the pool (by priority)
   ↓
4. Validate selected transactions
   ↓
5. Build block structure
   ↓
6. Calculate Merkle root
   ↓
7. Sign block with private key
   ↓
8. Broadcast block to the network
   ↓
9. Wait for validations from other Block Creators
   ↓
10. Collect fees from transactions
```

### Block Validation Flow (When Receiving a Block from Another Node)

```
1. Receive block from the network
   ↓
2. Verify block format
   ↓
3. Verify Central Node authorization
   ↓
4. Verify Block Creator signature
   ↓
5. Validate all transactions in the block
   ↓
6. Verify block against local state
   ↓
7. Check for conflicts/forks
   ↓
8. If valid:
   - Add to local chain
   - Update state
   - Signal acceptance
   - Remove transactions from the pool
   ↓
9. If invalid:
   - Report to Central Node
   - Report to Inspector nodes
```

## Requirements and Constraints

### Technical Requirements
- **Storage:** Full blockchain state (may be several GB to TB)
- **Network:** High bandwidth to broadcast blocks
- **CPU:** Fast enough to validate transactions and create blocks
- **Memory:** Sufficient to maintain the transaction pool

### Economic Requirements
- **Stake:** Must stake D coins (penalized if it fails)
- **Fees:** Receive transaction fees when creating blocks
- **Costs:** Infrastructure costs (server, bandwidth, storage)

### Operational Requirements
- **Uptime:** Must be online and responsive
- **Sync:** Must sync with the network
- **Security:** Must secure private keys
- **Monitoring:** Monitor performance and health

## API Endpoints (If Implemented)

### Internal APIs
- `POST /block/create` - Create a block when authorized by the Central Node
- `POST /block/validate` - Validate a block from other nodes
- `GET /transactions/pool` - Get transaction pool
- `POST /transactions/add` - Add transaction to pool
- `GET /chain/status` - Get blockchain status
- `POST /chain/sync` - Sync with the network

### External APIs (for other nodes)
- `GET /block/{blockId}` - Get block by ID
- `POST /block/broadcast` - Broadcast block
- `POST /validation/signal` - Signal block acceptance/rejection
- `GET /transactions/pending` - Get pending transactions (if public)

## Security Considerations

### Key Management
- **Private Key Security:**
  - Store private key securely (HSM, encrypted storage)
  - Never expose private key
  - Use key rotation if needed

### Block Validation Security
- **Verify All Signatures:**
  - Always verify Central Node signatures
  - Always verify transaction signatures
  - Always verify block creator signatures

### Network Security
- **Secure Communication:**
  - Use TLS/SSL for all communications
  - Authenticate messages
  - Prevent replay attacks

### State Security
- **State Integrity:**
  - Verify state transitions
  - Check for double-spending
  - Validate all state changes

## Monitoring and Logging

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
  - Log each block that is created
  - Log transactions included
  - Log fees collected

- **Block Validation:**
  - Log blocks validated
  - Log invalid blocks and reasons
  - Log acceptance/rejection signals

- **Errors:**
  - Log all errors
  - Log network issues
  - Log validation failures

## Conclusion

Block Creator Nodes are the backbone of the Deltanium blockchain, responsible for:
1. ✅ **Process transactions** and maintain the transaction pool
2. ✅ **Create blocks** when selected by the Central Node
3. ✅ **Validate blocks** from other Block Creators
4. ✅ **Maintain blockchain state** locally
5. ✅ **Communicate** with the Central Node and other nodes
6. ✅ **Collect fees** and manage stake
7. ✅ **Handle penalties** if they fail

This is an important role and requires high performance, security, and reliability.
