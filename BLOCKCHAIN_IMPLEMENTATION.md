# Blockchain Implementation Details for Deltanium

## 1. Transaction Structure

### 1.1. Base Transaction Class

```csharp
// deltanium-core/Core/Blockchain/Transaction.cs
namespace Deltanium.Core.Blockchain
{
    public enum TransactionType
    {
        UserRegistration,
        Follow,
        Unfollow,
        CreatePost,
        React,
        Comment,
        NodeRegistration,
        StorageOperation
    }

    public class Transaction
    {
        public string TxId { get; set; } // SHA256 hash of transaction
        public TransactionType Type { get; set; }
        public long Timestamp { get; set; }
        public string From { get; set; } // Public key of sender
        public string To { get; set; } // Optional: Public key of recipient
        public Dictionary<string, object> Data { get; set; } // Transaction-specific data
        public string Signature { get; set; } // Signature of transaction
        public long Nonce { get; set; } // Prevent duplicate transactions

        public string GetSignableData()
        {
            var dataJson = JsonSerializer.Serialize(Data, new JsonSerializerOptions 
            { 
                WriteIndented = false 
            });
            return $"{Type}:{Timestamp}:{From}:{To ?? ""}:{dataJson}:{Nonce}";
        }

        public string CalculateTxId()
        {
            var signableData = GetSignableData();
            var hash = SHA256.HashData(Encoding.UTF8.GetBytes(signableData + Signature));
            return Convert.ToHexString(hash);
        }

        public bool VerifySignature(KeyService keyService)
        {
            var signableData = GetSignableData();
            return keyService.VerifySignature(From, signableData, Signature);
        }
    }
}
```

### 1.2. Specific Transaction Types

```csharp
// deltanium-core/Core/Blockchain/Transactions/UserRegistrationTransaction.cs
namespace Deltanium.Core.Blockchain.Transactions
{
    public class UserRegistrationTransaction : Transaction
    {
        public UserRegistrationTransaction()
        {
            Type = TransactionType.UserRegistration;
        }

        public static Transaction Create(
            string publicKey,
            string email,
            string fullName,
            DateTime? dateOfBirth,
            string bio,
            string avatarUrl,
            string mnemonic,
            KeyService keyService)
        {
            var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            var data = new Dictionary<string, object>
            {
                ["email"] = email,
                ["fullName"] = fullName,
                ["dateOfBirth"] = dateOfBirth?.ToString("yyyy-MM-dd") ?? "",
                ["bio"] = bio ?? "",
                ["avatarUrl"] = avatarUrl ?? ""
            };

            var tx = new Transaction
            {
                Type = TransactionType.UserRegistration,
                Timestamp = timestamp,
                From = publicKey,
                Data = data,
                Nonce = 0 // First transaction for user
            };

            var signableData = tx.GetSignableData();
            tx.Signature = keyService.Sign(signableData, mnemonic);
            tx.TxId = tx.CalculateTxId();

            return tx;
        }
    }
}
```

```csharp
// deltanium-core/Core/Blockchain/Transactions/FollowTransaction.cs
namespace Deltanium.Core.Blockchain.Transactions
{
    public class FollowTransaction : Transaction
    {
        public static Transaction Create(
            string followerPublicKey,
            string followingPublicKey,
            string mnemonic,
            KeyService keyService)
        {
            var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            var data = new Dictionary<string, object>
            {
                ["action"] = "follow",
                ["follower"] = followerPublicKey,
                ["following"] = followingPublicKey
            };

            var tx = new Transaction
            {
                Type = TransactionType.Follow,
                Timestamp = timestamp,
                From = followerPublicKey,
                To = followingPublicKey,
                Data = data,
                Nonce = GetNextNonce(followerPublicKey) // Prevent duplicate follows
            };

            var signableData = tx.GetSignableData();
            tx.Signature = keyService.Sign(signableData, mnemonic);
            tx.TxId = tx.CalculateTxId();

            return tx;
        }
    }
}
```

```csharp
// deltanium-core/Core/Blockchain/Transactions/CreatePostTransaction.cs
namespace Deltanium.Core.Blockchain.Transactions
{
    public class CreatePostTransaction : Transaction
    {
        public static Transaction Create(
            string authorPublicKey,
            string postId,
            string storageNodeId,
            string fileId,
            string firstBlockId,
            string encryptedType,
            string shareType,
            string? encryptedKey,
            string? policyTag,
            List<string>? tags,
            string mnemonic,
            KeyService keyService)
        {
            var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            var data = new Dictionary<string, object>
            {
                ["postId"] = postId,
                ["storageNodeId"] = storageNodeId,
                ["fileId"] = fileId,
                ["firstBlockId"] = firstBlockId,
                ["encryptedType"] = encryptedType,
                ["shareType"] = shareType
            };

            if (!string.IsNullOrEmpty(encryptedKey))
                data["encryptedKey"] = encryptedKey;

            if (!string.IsNullOrEmpty(policyTag))
            {
                data["policyTag"] = policyTag;
                data["capsuleFor"] = "tag";
                data["policyScheme"] = "CPRE";
            }

            if (tags != null && tags.Any())
                data["tags"] = tags;

            var tx = new Transaction
            {
                Type = TransactionType.CreatePost,
                Timestamp = timestamp,
                From = authorPublicKey,
                Data = data,
                Nonce = GetNextNonce(authorPublicKey)
            };

            var signableData = tx.GetSignableData();
            tx.Signature = keyService.Sign(signableData, mnemonic);
            tx.TxId = tx.CalculateTxId();

            return tx;
        }
    }
}
```

## 2. Block Structure

```csharp
// deltanium-core/Core/Blockchain/Block.cs
namespace Deltanium.Core.Blockchain
{
    public class Block
    {
        public string BlockId { get; set; } // SHA256 hash of block
        public string PreviousBlockId { get; set; }
        public long Timestamp { get; set; }
        public string MerkleRoot { get; set; }
        public List<Transaction> Transactions { get; set; } = new();
        public string Miner { get; set; } // Public key of validator that created block
        public long Nonce { get; set; }
        public int Difficulty { get; set; } = 4; // Number of leading zeros in hash
        public long Height { get; set; }

        public string CalculateMerkleRoot()
        {
            if (Transactions == null || !Transactions.Any())
                return string.Empty;

            var txIds = Transactions.Select(tx => tx.TxId).ToList();
            return CalculateMerkleRoot(txIds);
        }

        private string CalculateMerkleRoot(List<string> hashes)
        {
            if (hashes.Count == 1)
                return hashes[0];

            var nextLevel = new List<string>();
            for (int i = 0; i < hashes.Count; i += 2)
            {
                if (i + 1 < hashes.Count)
                {
                    var combined = hashes[i] + hashes[i + 1];
                    var hash = SHA256.HashData(Encoding.UTF8.GetBytes(combined));
                    nextLevel.Add(Convert.ToHexString(hash));
                }
                else
                {
                    nextLevel.Add(hashes[i]);
                }
            }

            return CalculateMerkleRoot(nextLevel);
        }

        public string CalculateBlockId()
        {
            var data = $"{PreviousBlockId}:{Timestamp}:{MerkleRoot}:{Miner}:{Nonce}";
            var hash = SHA256.HashData(Encoding.UTF8.GetBytes(data));
            return Convert.ToHexString(hash);
        }

        public bool MeetsDifficulty()
        {
            var blockId = CalculateBlockId();
            return blockId.StartsWith(new string('0', Difficulty));
        }

        public bool Validate(KeyService keyService, BlockchainState state)
        {
            // Validate previous block
            if (Height > 0 && string.IsNullOrEmpty(PreviousBlockId))
                return false;

            // Validate merkle root
            var calculatedRoot = CalculateMerkleRoot();
            if (MerkleRoot != calculatedRoot)
                return false;

            // Validate difficulty
            if (!MeetsDifficulty())
                return false;

            // Validate all transactions
            foreach (var tx in Transactions)
            {
                if (!tx.VerifySignature(keyService))
                    return false;

                // Validate transaction against current state
                if (!ValidateTransaction(tx, state))
                    return false;
            }

            return true;
        }

        private bool ValidateTransaction(Transaction tx, BlockchainState state)
        {
            switch (tx.Type)
            {
                case TransactionType.UserRegistration:
                    // Check user doesn't already exist
                    return !state.IsUserRegistered(tx.From);

                case TransactionType.Follow:
                    // Check user exists and not already following
                    return state.IsUserRegistered(tx.From) &&
                           state.IsUserRegistered(tx.To) &&
                           !state.IsFollowing(tx.From, tx.To) &&
                           tx.From != tx.To;

                case TransactionType.CreatePost:
                    // Check user exists
                    return state.IsUserRegistered(tx.From);

                // Add other validations...
                default:
                    return true;
            }
        }
    }
}
```

## 3. Blockchain State

```csharp
// deltanium-core/Core/Blockchain/BlockchainState.cs
namespace Deltanium.Core.Blockchain
{
    public class BlockchainState
    {
        private Dictionary<string, UserInfo> _users = new();
        private Dictionary<string, HashSet<string>> _followers = new(); // following -> followers
        private Dictionary<string, HashSet<string>> _following = new(); // follower -> following
        private Dictionary<string, PostInfo> _posts = new(); // postId -> PostInfo
        private Dictionary<string, List<string>> _postReactions = new(); // postFileId -> list of reaction txIds
        private Dictionary<string, List<string>> _postComments = new(); // postFileId -> list of comment txIds
        private Dictionary<string, NodeInfo> _nodes = new(); // nodePublicKey -> NodeInfo

        public bool IsUserRegistered(string publicKey)
        {
            return _users.ContainsKey(publicKey);
        }

        public bool IsFollowing(string follower, string following)
        {
            return _following.ContainsKey(follower) &&
                   _following[follower].Contains(following);
        }

        public void ApplyTransaction(Transaction tx)
        {
            switch (tx.Type)
            {
                case TransactionType.UserRegistration:
                    ApplyUserRegistration(tx);
                    break;

                case TransactionType.Follow:
                    ApplyFollow(tx);
                    break;

                case TransactionType.Unfollow:
                    ApplyUnfollow(tx);
                    break;

                case TransactionType.CreatePost:
                    ApplyCreatePost(tx);
                    break;

                case TransactionType.React:
                    ApplyReact(tx);
                    break;

                case TransactionType.Comment:
                    ApplyComment(tx);
                    break;

                case TransactionType.NodeRegistration:
                    ApplyNodeRegistration(tx);
                    break;
            }
        }

        private void ApplyUserRegistration(Transaction tx)
        {
            var userInfo = new UserInfo
            {
                PublicKey = tx.From,
                Email = tx.Data["email"]?.ToString() ?? "",
                FullName = tx.Data["fullName"]?.ToString() ?? "",
                DateOfBirth = tx.Data["dateOfBirth"]?.ToString(),
                Bio = tx.Data["bio"]?.ToString() ?? "",
                AvatarUrl = tx.Data["avatarUrl"]?.ToString() ?? "",
                RegisteredAt = DateTimeOffset.FromUnixTimeSeconds(tx.Timestamp).DateTime
            };

            _users[tx.From] = userInfo;
        }

        private void ApplyFollow(Transaction tx)
        {
            if (!_followers.ContainsKey(tx.To))
                _followers[tx.To] = new HashSet<string>();

            if (!_following.ContainsKey(tx.From))
                _following[tx.From] = new HashSet<string>();

            _followers[tx.To].Add(tx.From);
            _following[tx.From].Add(tx.To);
        }

        private void ApplyUnfollow(Transaction tx)
        {
            if (_followers.ContainsKey(tx.To))
                _followers[tx.To].Remove(tx.From);

            if (_following.ContainsKey(tx.From))
                _following[tx.From].Remove(tx.To);
        }

        private void ApplyCreatePost(Transaction tx)
        {
            var postInfo = new PostInfo
            {
                PostId = tx.Data["postId"]?.ToString() ?? "",
                AuthorPublicKey = tx.From,
                StorageNodeId = tx.Data["storageNodeId"]?.ToString() ?? "",
                FileId = tx.Data["fileId"]?.ToString() ?? "",
                FirstBlockId = tx.Data["firstBlockId"]?.ToString() ?? "",
                EncryptedType = tx.Data["encryptedType"]?.ToString() ?? "encrypted",
                ShareType = tx.Data["shareType"]?.ToString() ?? "me",
                PolicyTag = tx.Data["policyTag"]?.ToString(),
                Tags = tx.Data.ContainsKey("tags") 
                    ? ((JsonElement)tx.Data["tags"]).EnumerateArray().Select(e => e.GetString()).ToList()
                    : new List<string>(),
                CreatedAt = DateTimeOffset.FromUnixTimeSeconds(tx.Timestamp).DateTime
            };

            _posts[postInfo.PostId] = postInfo;
        }

        private void ApplyReact(Transaction tx)
        {
            var postFileId = tx.Data["postFileId"]?.ToString() ?? "";
            if (!_postReactions.ContainsKey(postFileId))
                _postReactions[postFileId] = new List<string>();

            _postReactions[postFileId].Add(tx.TxId);
        }

        private void ApplyComment(Transaction tx)
        {
            var postFileId = tx.Data["postFileId"]?.ToString() ?? "";
            if (!_postComments.ContainsKey(postFileId))
                _postComments[postFileId] = new List<string>();

            _postComments[postFileId].Add(tx.TxId);
        }

        private void ApplyNodeRegistration(Transaction tx)
        {
            var nodeInfo = new NodeInfo
            {
                PublicKey = tx.From,
                NodeType = tx.Data["nodeType"]?.ToString() ?? "",
                Endpoint = tx.Data["endpoint"]?.ToString() ?? "",
                RegisteredAt = DateTimeOffset.FromUnixTimeSeconds(tx.Timestamp).DateTime
            };

            _nodes[tx.From] = nodeInfo;
        }

        public void ApplyBlock(Block block)
        {
            foreach (var tx in block.Transactions)
            {
                ApplyTransaction(tx);
            }
        }

        public BlockchainState Clone()
        {
            // Deep clone for testing transactions
            var clone = new BlockchainState();
            // Implement deep copy...
            return clone;
        }
    }

    public class UserInfo
    {
        public string PublicKey { get; set; }
        public string Email { get; set; }
        public string FullName { get; set; }
        public string? DateOfBirth { get; set; }
        public string Bio { get; set; }
        public string AvatarUrl { get; set; }
        public DateTime RegisteredAt { get; set; }
    }

    public class PostInfo
    {
        public string PostId { get; set; }
        public string AuthorPublicKey { get; set; }
        public string StorageNodeId { get; set; }
        public string FileId { get; set; }
        public string FirstBlockId { get; set; }
        public string EncryptedType { get; set; }
        public string ShareType { get; set; }
        public string? PolicyTag { get; set; }
        public List<string> Tags { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class NodeInfo
    {
        public string PublicKey { get; set; }
        public string NodeType { get; set; }
        public string Endpoint { get; set; }
        public DateTime RegisteredAt { get; set; }
    }
}
```

## 4. Blockchain Node

```csharp
// deltanium-core/Core/Blockchain/BlockchainNode.cs
namespace Deltanium.Core.Blockchain
{
    public class BlockchainNode
    {
        private readonly KeyService _keyService;
        private readonly string _nodePublicKey;
        private readonly string _nodeMnemonic;
        private readonly BlockchainState _state;
        private readonly List<Block> _chain = new();
        private readonly List<Transaction> _transactionPool = new();
        private readonly List<BlockchainNode> _peers = new();
        private readonly bool _isValidator;

        public BlockchainNode(
            KeyService keyService,
            string nodeMnemonic,
            bool isValidator = false)
        {
            _keyService = keyService;
            _nodeMnemonic = nodeMnemonic;
            _nodePublicKey = keyService.GetPublicKeyFromMnemonic(nodeMnemonic);
            _state = new BlockchainState();
            _isValidator = isValidator;

            // Create genesis block
            if (_chain.Count == 0)
            {
                var genesisBlock = CreateGenesisBlock();
                _chain.Add(genesisBlock);
                _state.ApplyBlock(genesisBlock);
            }
        }

        private Block CreateGenesisBlock()
        {
            return new Block
            {
                BlockId = "0".PadLeft(64, '0'),
                PreviousBlockId = string.Empty,
                Timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                MerkleRoot = string.Empty,
                Transactions = new List<Transaction>(),
                Miner = _nodePublicKey,
                Nonce = 0,
                Difficulty = 0,
                Height = 0
            };
        }

        public void AddTransaction(Transaction tx)
        {
            // Validate transaction
            if (!tx.VerifySignature(_keyService))
            {
                Console.WriteLine($"Invalid signature for transaction {tx.TxId}");
                return;
            }

            // Validate against current state
            if (!ValidateTransaction(tx))
            {
                Console.WriteLine($"Transaction {tx.TxId} failed validation");
                return;
            }

            // Check if already in pool
            if (_transactionPool.Any(t => t.TxId == tx.TxId))
            {
                Console.WriteLine($"Transaction {tx.TxId} already in pool");
                return;
            }

            _transactionPool.Add(tx);
            Console.WriteLine($"Added transaction {tx.TxId} to pool");

            // Broadcast to peers
            BroadcastTransaction(tx);
        }

        private bool ValidateTransaction(Transaction tx)
        {
            // Create temporary state to test transaction
            var testState = _state.Clone();
            
            // Try to apply transaction
            try
            {
                testState.ApplyTransaction(tx);
                return true;
            }
            catch
            {
                return false;
            }
        }

        public Block? CreateBlock()
        {
            if (!_isValidator)
                return null;

            if (_transactionPool.Count == 0)
                return null;

            // Select transactions (up to block size limit)
            var transactions = _transactionPool.Take(100).ToList();

            // Create block
            var block = new Block
            {
                PreviousBlockId = _chain.Last().BlockId,
                Timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                Transactions = transactions,
                Miner = _nodePublicKey,
                Nonce = 0,
                Difficulty = 4,
                Height = _chain.Count
            };

            block.MerkleRoot = block.CalculateMerkleRoot();

            // Mine block (find nonce that meets difficulty)
            while (!block.MeetsDifficulty())
            {
                block.Nonce++;
                if (block.Nonce % 10000 == 0)
                    Console.WriteLine($"Mining... nonce: {block.Nonce}");
            }

            block.BlockId = block.CalculateBlockId();

            // Validate block
            if (!block.Validate(_keyService, _state))
            {
                Console.WriteLine("Created block failed validation");
                return null;
            }

            // Apply block to state
            _state.ApplyBlock(block);
            _chain.Add(block);

            // Remove transactions from pool
            foreach (var tx in transactions)
            {
                _transactionPool.Remove(tx);
            }

            Console.WriteLine($"Created block {block.BlockId} with {transactions.Count} transactions");

            // Broadcast block to peers
            BroadcastBlock(block);

            return block;
        }

        public void AddBlock(Block block)
        {
            // Validate block
            if (!block.Validate(_keyService, _state))
            {
                Console.WriteLine($"Block {block.BlockId} failed validation");
                return;
            }

            // Check if previous block exists
            if (block.Height > 0)
            {
                var previousBlock = _chain.LastOrDefault();
                if (previousBlock == null || previousBlock.BlockId != block.PreviousBlockId)
                {
                    Console.WriteLine($"Block {block.BlockId} has invalid previous block");
                    return;
                }
            }

            // Apply block to state
            _state.ApplyBlock(block);
            _chain.Add(block);

            // Remove transactions from pool
            foreach (var tx in block.Transactions)
            {
                _transactionPool.RemoveAll(t => t.TxId == tx.TxId);
            }

            Console.WriteLine($"Added block {block.BlockId} to chain");
        }

        private void BroadcastTransaction(Transaction tx)
        {
            foreach (var peer in _peers)
            {
                try
                {
                    peer.AddTransaction(tx);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error broadcasting transaction to peer: {ex.Message}");
                }
            }
        }

        private void BroadcastBlock(Block block)
        {
            foreach (var peer in _peers)
            {
                try
                {
                    peer.AddBlock(block);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error broadcasting block to peer: {ex.Message}");
                }
            }
        }

        public void AddPeer(BlockchainNode peer)
        {
            if (!_peers.Contains(peer))
                _peers.Add(peer);
        }

        public Block? GetLatestBlock()
        {
            return _chain.LastOrDefault();
        }

        public List<Block> GetChain()
        {
            return _chain.ToList();
        }

        public BlockchainState GetState()
        {
            return _state;
        }
    }
}
```

## 5. Integration with Existing Code

### 5.1. Modify UserController to Create Transactions

```csharp
// deltanium-api/Controllers/UserController.cs (modified)
[HttpPost("register")]
public async Task<ActionResult<User>> Register([FromBody] SignedRegisterRequest request)
{
    // ... existing validation ...

    // Create blockchain transaction
    var tx = UserRegistrationTransaction.Create(
        request.PublicKey,
        request.Email,
        request.FullName,
        request.DateOfBirth,
        request.Bio,
        request.AvatarUrl,
        // Note: We don't have user's mnemonic here, so transaction is created client-side
        // Or we create transaction after user is registered
    );

    // Save user (existing code)
    var user = new User { ... };
    await _storageService.SaveUserAsync(user);

    // Add transaction to blockchain (if we have blockchain node)
    if (_blockchainNode != null)
    {
        _blockchainNode.AddTransaction(tx);
    }

    return user;
}
```

### 5.2. Modify Follow to Create Transactions

```csharp
// deltanium-api/Controllers/UserController.cs (modified)
[HttpPost("follow")]
public async Task<ActionResult> FollowUser([FromHeader(Name = "X-User-PubKey")] string userPublicKey)
{
    // ... existing validation ...

    // Create blockchain transaction
    // Note: We need user's mnemonic to sign, so transaction should be created client-side
    // Or we use the signature from request to create transaction

    // Save follow (existing code)
    var success = await _storageService.FollowUserAsync(...);

    // Add transaction to blockchain
    if (_blockchainNode != null && success)
    {
        var tx = FollowTransaction.Create(
            currentUserPublicKey,
            targetPublicKey,
            // We don't have mnemonic, so transaction is created client-side
        );
        _blockchainNode.AddTransaction(tx);
    }

    return Ok(new { message = "Successfully followed user" });
}
```

### 5.3. Client-side Transaction Creation

```dart
// deltanium-app/lib/services/blockchain_service.dart
class BlockchainService {
  static Future<Transaction> createUserRegistrationTransaction({
    required String publicKey,
    required String email,
    required String fullName,
    DateTime? dateOfBirth,
    String? bio,
    String? avatarUrl,
    required String mnemonic,
  }) async {
    final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
    final data = {
      'email': email,
      'fullName': fullName,
      'dateOfBirth': dateOfBirth?.toIso8601String().split('T')[0] ?? '',
      'bio': bio ?? '',
      'avatarUrl': avatarUrl ?? '',
    };

    final dataJson = json.encode(data);
    final signableData = 'UserRegistration:$timestamp:$publicKey:::$dataJson:0';
    final signature = await CryptoService.sign(signableData, mnemonic);

    return Transaction(
      type: 'user_registration',
      timestamp: timestamp,
      from: publicKey,
      data: data,
      signature: signature,
      nonce: 0,
    );
  }

  static Future<void> broadcastTransaction(Transaction tx) async {
    // Broadcast to multiple blockchain nodes
    final nodes = await getBlockchainNodes();
    for (final node in nodes) {
      try {
        await http.post(
          Uri.parse('${node['endpoint']}/api/blockchain/transaction'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(tx.toJson()),
        );
      } catch (e) {
        AppLogger.log('Error broadcasting to node ${node['endpoint']}: $e');
      }
    }
  }
}
```

## 6. API Endpoints for Blockchain

```csharp
// deltanium-api/Controllers/BlockchainController.cs
namespace DeltaniumApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class BlockchainController : ControllerBase
    {
        private readonly BlockchainNode _blockchainNode;

        public BlockchainController(BlockchainNode blockchainNode)
        {
            _blockchainNode = blockchainNode;
        }

        [HttpPost("transaction")]
        public IActionResult AddTransaction([FromBody] Transaction tx)
        {
            _blockchainNode.AddTransaction(tx);
            return Ok(new { message = "Transaction added to pool", txId = tx.TxId });
        }

        [HttpGet("block/{blockId}")]
        public IActionResult GetBlock(string blockId)
        {
            var block = _blockchainNode.GetChain()
                .FirstOrDefault(b => b.BlockId == blockId);
            
            if (block == null)
                return NotFound();

            return Ok(block);
        }

        [HttpGet("chain")]
        public IActionResult GetChain()
        {
            var chain = _blockchainNode.GetChain();
            return Ok(chain);
        }

        [HttpGet("state")]
        public IActionResult GetState()
        {
            var state = _blockchainNode.GetState();
            return Ok(state);
        }

        [HttpGet("transaction/{txId}")]
        public IActionResult GetTransaction(string txId)
        {
            var chain = _blockchainNode.GetChain();
            foreach (var block in chain)
            {
                var tx = block.Transactions.FirstOrDefault(t => t.TxId == txId);
                if (tx != null)
                    return Ok(tx);
            }
            return NotFound();
        }
    }
}
```

## 7. Store Node Integration

```csharp
// deltanium-store/Controllers/BlockchainController.cs
namespace DeltaniumStore.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class BlockchainController : ControllerBase
    {
        private readonly BlockchainNode _blockchainNode;
        private readonly IFileStorageService _fileStorage;

        public BlockchainController(
            BlockchainNode blockchainNode,
            IFileStorageService fileStorage)
        {
            _blockchainNode = blockchainNode;
            _fileStorage = fileStorage;
        }

        [HttpPost("transaction")]
        public IActionResult AddTransaction([FromBody] Transaction tx)
        {
            _blockchainNode.AddTransaction(tx);
            return Ok(new { message = "Transaction added to pool", txId = tx.TxId });
        }

        // Store node can create blocks (validator)
        [HttpPost("block/create")]
        public IActionResult CreateBlock()
        {
            var block = _blockchainNode.CreateBlock();
            if (block == null)
                return BadRequest("No transactions in pool or not a validator");

            return Ok(block);
        }
    }
}
```

## 8. Next Steps

1. **Implement Core Blockchain:**
   - Transaction signing/verification
   - Block creation and validation
   - State management
   - Merkle tree calculation

2. **Implement P2P Network:**
   - Node discovery
   - Transaction propagation
   - Block propagation
   - Chain sync

3. **Implement Consensus:**
   - Validator selection
   - Block creation schedule
   - Fork resolution

4. **Integration:**
   - Modify existing controllers to create transactions
   - Add blockchain endpoints
   - Client-side transaction creation

5. **Testing:**
   - Unit tests for transactions
   - Integration tests for blocks
   - Network tests with multiple nodes

6. **Migration:**
   - Migrate existing data to blockchain
   - Dual-mode operation
   - Gradual migration

