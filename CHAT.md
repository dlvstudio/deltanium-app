# Deltanium Chat – Architecture and Technical Solution Proposal (v2)

> Detailed architecture proposal for E2E chat in the Deltanium ecosystem, with **two modes**: **Online (P2P)** and **Offline (File-based)**.

## 1. Overview of requirements

- **1-1 Chat**: Users chat directly with each other (DM)
- **End-to-end encryption (E2E)**: Only the sender and recipient can read the content
- **Compatible with the current system**: Leverage the identity model (publicKey), crypto (ECIES), Central API, and Store
- **Two distinct modes**:
  - **Online**: When both users enable online mode → direct P2P connection, real-time
  - **Offline**: When the recipient is offline → each message = 1 file, leveraging existing Store infrastructure

---

## 2. Solution overview

### 2.1 Core idea

| Mode | Condition | Mechanism | Data flow |
|------|-----------|-----------|-----------|
| **Online (P2P)** | User A and B both enable "online" with the Central API | Direct peer-to-peer connection | Messages go directly A ↔ B, not through the server |
| **Offline (File-based)** | Recipient is offline or has not enabled online | File sharing | Each message = 1 file (metadata + block) on Store |

### 2.2 Central API role

- **Online mode**: Only acts as a **presence registry** + **signaling server** for WebRTC (SDP/ICE exchange)
- **Offline mode**: Stores **message metadata** (conversationId, messageId, blockId, storeNodeId) so the recipient can fetch when online
- **Does not relay message content** in either mode

### 2.3 Overall diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                        DELTANIUM CHAT – TWO MODES                                        │
└─────────────────────────────────────────────────────────────────────────────────────────┘

  ONLINE MODE (both users have online enabled):
  ┌──────────┐                                                    ┌──────────┐
  │  Alice   │◀──────────────── P2P (WebRTC) ────────────────────▶│   Bob    │
  │  (App)   │         E2E-encrypted messages sent directly       │  (App)   │
  └────┬─────┘                                                    └────┬─────┘
       │                                                               │
       │   POST /api/chat/online    POST /api/chat/online               │
       │   (presence + signaling)  (presence + signaling)               │
       └───────────────────────────┬─────────────────────────────────┘
                                    │
                                    ▼
                         ┌─────────────────────┐
                         │   Central API       │
                         │ - Presence registry │
                         │ - WebRTC signaling  │
                         │ (does not contain   │
                         │  content)           │
                         └─────────────────────┘

  OFFLINE MODE (Bob is not online):
  ┌──────────┐      upload file       ┌──────────────┐     metadata    ┌─────────────┐
  │  Alice   │ ──────────────────────▶│ Store Node   │◀────────────────│ Central API │
  │  (App)   │  (1 message = 1 file)  │ (encrypted   │  POST /chat/msg │             │
  └──────────┘                        │  block)      │                 └──────┬──────┘
                                      └──────┬───────┘                        │
                                             │                                │
                                             │  Bob comes back online →       │
                                             │  fetch block                   │
                                             │  GET /api/file/block/{blockId} │
                                             ▼                                │
                                      ┌──────────┐   GET /chat/messages       │
                                      │   Bob    │◀───────────────────────────│
                                      │  (App)   │                            │
                                      └──────────┘                            │
```

---

## 3. Online mode (P2P) details

### 3.1 Operating flow

```
1. Alice opens the app → enables "Online mode" → POST /api/chat/online { pubKey, heartbeat }
2. Bob does the same → POST /api/chat/online { pubKey, heartbeat }
3. Central API stores: user_online_sessions.json { pubKey, lastSeen, signalingData? }
4. Alice opens chat with Bob → GET /api/chat/online-status?user=Bob
   → API returns: { online: true, signalingEndpoint? }
5. Both are online → establish a WebRTC connection:
   - Alice creates an offer → sends via API (signaling) → Bob receives
   - Bob creates an answer → sends via API → Alice receives
   - ICE candidates are exchanged via API
6. WebRTC DataChannel is established → messages are sent directly P2P
7. Encryption: ECIES(K, pk_recipient) per message (or ECDH session key)
```

### 3.2 Presence & Signaling API

| Method | Path | Description |
|--------|------|-------------|
| POST | /api/chat/online | Enable online mode (heartbeat every 30s) |
| DELETE | /api/chat/online | Disable online mode |
| GET | /api/chat/online-status?user={pubKey} | Check whether a user is online |
| POST | /api/chat/signaling/offer | Send WebRTC offer (SDP only, no content) |
| POST | /api/chat/signaling/answer | Send WebRTC answer |
| POST | /api/chat/signaling/ice | Send ICE candidate |

### 3.3 P2P technology

- **WebRTC DataChannel**: Suitable for Flutter (package `flutter_webrtc`)
- **NAT traversal**: WebRTC uses STUN/TURN; a public STUN server can be used (or self-hosted)
- **Signaling**: Central API only relays SDP/ICE and does not read content

### 3.4 Switching Online ↔ Offline

- When **Bob goes offline** during a chat: Alice sends a message → fallback to file mode
- When **Bob comes back online**: Bob's app fetches offline messages from Store (using metadata on the API)
- When **P2P connection is lost**: Retry P2P; if it fails → switch to file mode

---

## 4. Offline mode (File-based) details

### 4.1 Principles

- **Each message = 1 file** (1 metadata entry + 1 block)
- Leverage **100% of the existing infrastructure**: `upload-metadata-raw`, `upload-file-block-raw`, `storedfile/register`
- `FileMetadata.Type = "chat_message"`
- `RecipientPubKey` = recipient's public key (1-1)
- `encryptedKey` = ECIES(K, pk_recipient)

### 4.2 Offline message send flow

```
1. Alice wants to send "Hello" to Bob (Bob is offline)
2. App creates K (random 32 bytes)
3. payload = AES-GCM(K, JSON({ text: "Hello", createdAt, senderPubKey }))
4. encryptedKey = ECIES(K, pk_Bob)
5. Select a Store Node from GET /api/storenode/list
6. Upload metadata + block the same way as a post:
   - POST Store /api/file/upload-metadata-raw (Type: chat_message, RecipientPubKey: Bob)
   - POST Store /api/file/upload-file-block-raw
7. POST Central API /api/storedfile/register (or /api/chat/message)
8. API stores metadata: { conversationId, messageId, blockId, storeNodeId, senderPubKey }
```

### 4.3 Offline message receive flow

```
1. Bob comes back online and opens the app
2. GET /api/chat/messages?recipient={BobPubKey}&since={lastSync}
3. API returns a list of metadata (blockId, storeNodeId, senderPubKey)
4. For each message, Bob: GET Store /api/file/block/{blockId}
5. ECIES decrypt → AES decrypt → display
6. Mark as read (optional)
```

### 4.4 Chat message metadata format

**Store (FileMetadata):**
```json
{
  "fileId": "msg_uuid",
  "type": "chat_message",
  "recipientPubKey": "02abc...",
  "ownerPubKey": "02def...",
  "creationTime": "2025-02-08T10:00:00Z",
  "encryptedKey": "<base64>",
  "shareType": "me",
  "firstBlockId": "block_uuid"
}
```

**Central API (index only):**
```json
{
  "messageId": "msg_uuid",
  "conversationId": "conv_uuid",
  "senderPubKey": "02def...",
  "recipientPubKey": "02abc...",
  "storeNodeId": "node_1",
  "blockId": "block_uuid",
  "createdAt": "2025-02-08T10:00:00Z"
}
```

---

## 5. Data model

### 5.1 Conversation (Central API)

```json
{
  "conversationId": "conv_uuid",
  "participants": ["pubkey_A", "pubkey_B"],
  "createdAt": "2025-02-08T10:00:00Z",
  "lastMessageAt": "2025-02-08T10:30:00Z"
}
```

### 5.2 Online session (Central API)

```json
{
  "userPubKey": "02abc...",
  "lastHeartbeat": "2025-02-08T10:35:00Z",
  "signalingToken": "optional_token_for_webrtc"
}
```

### 5.3 Store – Reuse

- Use `upload-metadata-raw` + `upload-file-block-raw` with `type: "chat_message"`
- No new Store endpoint is needed
- FileMetadata already supports `Type`, `RecipientPubKey`, `EncryptedKey`

---

## 6. Proposed API summary

### 6.1 Central API – Chat Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | /api/chat/online | Enable online mode (heartbeat) |
| DELETE | /api/chat/online | Disable online mode |
| GET | /api/chat/online-status?user={pubKey} | Check whether a user is online |
| POST | /api/chat/conversation | Create or get a conversation with a user |
| GET | /api/chat/conversations | Conversation list |
| POST | /api/chat/message | Register a message (metadata only, for offline) |
| GET | /api/chat/messages/{conversationId} | Message metadata list (paginated) |
| GET | /api/chat/unread-count | Unread message count |

### 6.2 Signaling (used only when both are online)

| Method | Path | Description |
|--------|------|-------------|
| POST | /api/chat/signaling/offer | Send WebRTC offer (Alice → Bob) |
| POST | /api/chat/signaling/answer | Send WebRTC answer (Bob → Alice) |
| POST | /api/chat/signaling/ice | Send ICE candidate |

### 6.3 Store – Unchanged

- `POST /api/file/upload-metadata-raw` with `type: "chat_message"`
- `POST /api/file/upload-file-block-raw`
- `GET /api/file/block/{blockId}`

---

## 7. E2E encryption – Leverage existing infrastructure

Chat **does not require new crypto** – reuse the entire existing `CryptoService`, `EciesService`, `FileCryptoService`, and `FileUploadService` in the app.

### 7.1 Existing infrastructure (lib/services/)

| Service | Function | Used for Chat |
|---------|----------|---------------|
| **EciesService** | `encryptWithPublicKey(data, pk)` / `decryptWithPrivateKey(data, mnemonic)` | Encrypt K (32 bytes) for the recipient |
| **FileCryptoService** | `encryptAndSplitFile()`, `decryptMetadataBlock()`, `_encryptData()` / `_decryptData()` | Offline: encrypt message; P2P: compatible format |
| **FileCryptoService** | `getCachedSymmetricKey()`, `cacheSymmetricKey()` | Cache the key when decrypting many consecutive messages |
| **CryptoService** | `convertToCompressedPublicKey()`, `normalizePublicKey()` | Normalize public keys |
| **FileUploadService** | `uploadEncryptedFile()` | Offline: upload metadata + block to Store |

### 7.2 Offline (File-based) – Call FileCryptoService directly

Each message = 1 file with **1 content block**. Call `FileCryptoService.encryptAndSplitFile()`:

```dart
// ChatService sends an offline message
final payload = jsonEncode({
  'text': text,
  'createdAt': DateTime.now().toIso8601String(),
  'senderPubKey': myPubKey,
});
final fileData = Uint8List.fromList(utf8.encode(payload));

final processed = await FileCryptoService.encryptAndSplitFile(
  fileData: fileData,
  fileName: 'chat',
  ownerPublicKey: myPubKey,
  mnemonic: mnemonic,
  sharedWithPublicKeys: [recipientPubKey],
  fileType: 'chat_message',
  shareType: 'me',
);
// processed['metadataEntries'] – select the entry with recipientPubKey = recipient
// processed['blocks'] – upload to Store like a post
```

**Decrypt** (Bob receives a message): use the same flow as `related_files_widget` / feed:

1. Get metadata from Store (includes `encryptedKey`, `recipientPubKey`, `contentBlockIds`)
2. `FileCryptoService.decryptMetadataBlock(storeMetadata, encryptedMetadataBlock, myPubKey, mnemonic)` → returns metadata + `_symmetricKey`
3. Get the content block from Store (`GET /api/file/block/{blockId}`)
4. `FileCryptoService.decryptRawBlockWithKey(encryptedContentBlock, symmetricKey)` → JSON text
5. Cache: `getCachedSymmetricKey()` / `cacheSymmetricKey()` if decrypting many consecutive messages

**Format matches file/post**:
- `encryptedKey` = ECIES(K, pk_recipient) – standard ECIES (secp256k1, AES-CBC, HMAC-SHA256)
- Payload block = AES-GCM encrypted with K
- Store does not need changes; `FileMetadata` already supports `type`, `recipientPubKey`, `encryptedKey`

### 7.3 Online (P2P) – Use ECIES + AES with the same format

So that **online and offline share the same decrypt logic**, P2P also uses the same format:

```dart
// ChatP2PService sends a message over DataChannel
final K = Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256)));
final encryptedKey = await EciesService.encryptWithPublicKey(
  data: K,
  publicKeyHex: recipientPubKey,
);
final payload = utf8.encode(jsonEncode({...}));
final encryptedPayload = await FileCryptoService.testEncryptData(
  Uint8List.fromList(payload),
  K,
);
// Send: [encryptedKey | encryptedPayload] or {encryptedKey: base64, payload: base64}
```

**Decrypt** (Bob receives via P2P):

```dart
final K = await FileCryptoService.decryptSymmetricKeyWithPrivateKey(
  encryptedKeyBytes,
  mnemonic,
);
final decrypted = await FileCryptoService.decryptRawBlockWithKey(payloadBytes, K);
```

### 7.4 Unified format – Online and Offline

| Component | Online (P2P) | Offline (File) |
|-----------|--------------|----------------|
| encryptedKey | EciesService.encryptWithPublicKey | encryptAndSplitFile (sharedWithPublicKeys) |
| Payload | FileCryptoService.testEncryptData | Same (AES-CBC, IV-prefixed) |
| Decrypt key | FileCryptoService.decryptSymmetricKeyWithPrivateKey | decryptMetadataBlock (returns `_symmetricKey`) |
| Decrypt payload | FileCryptoService.decryptRawBlockWithKey | Same |

→ **One decrypt set** is used for both P2P and file; only the data source differs (DataChannel vs Store).

### 7.5 Not used

- PRE (Umbral): 1-1 chat only needs ECIES
- Signal Protocol / Double Ratchet: can be upgraded later; not needed for MVP

---

## 8. App (Flutter) – Proposed changes

### 8.1 Services

```
lib/services/
├── chat_service.dart           # Send/receive, choose mode (P2P vs file)
├── chat_p2p_service.dart       # WebRTC DataChannel, signaling
├── chat_presence_service.dart  # Online/offline, heartbeat
└── (reuse) crypto_service, file_crypto_service, file_upload_service
```

### 8.2 Models

```
lib/models/
├── conversation.dart
├── chat_message.dart
├── chat_message_metadata.dart
└── online_status.dart
```

### 8.3 UI

```
lib/features/messages/
├── screens/
│   ├── messages_screen.dart          # List conversations
│   └── chat_conversation_screen.dart # Thread with 1 user
├── widgets/
│   ├── conversation_tile.dart
│   ├── message_bubble.dart
│   ├── chat_input.dart
│   └── online_indicator.dart        # Badge "online" / "offline"
```

### 8.4 Packages to add

- `flutter_webrtc` – WebRTC DataChannel for P2P
- (Optional) STUN/TURN server config

---

## 9. Implementation roadmap

### Phase 1: Offline mode (File-based) – 2–3 weeks

1. **API**: ChatController (conversation, message metadata, JSON file)
2. **Store**: Use file blocks with `type: "chat_message"` (no Store changes needed)
3. **App**: ChatService (REST), upload/download messages like files, MessagesScreen + ChatConversationScreen
4. **Polling**: Bob fetches messages every 10–30s when chat is open

### Phase 2: Presence & Online mode – 1–2 weeks

5. **API**: POST/DELETE /api/chat/online, GET online-status
6. **App**: ChatPresenceService, toggle "Online mode", display online/offline status
7. **Logic**: If the recipient is offline → use file mode; if online → prepare P2P

### Phase 3: P2P (WebRTC) – 2–3 weeks

8. **API**: Signaling endpoints (offer, answer, ice)
9. **App**: ChatP2PService with flutter_webrtc, DataChannel connection
10. **Flow**: When both are online → establish P2P, send messages directly
11. **Fallback**: P2P fails → switch to file mode

### Phase 4: Optimization – 1–2 weeks

12. Offline queue: store unsent messages, retry when network is available
13. Unread count, badge
14. Typing indicator (P2P: via DataChannel; Offline: not supported)

### Phase 5 (optional)

15. Send files/media in chat (reuse FileUploadService)
16. Group chat – needs multi-recipient ECIES or Sender Key

---

## 10. Comparison with the previous version (Hybrid WebSocket)

| Criterion | Previous version (Hybrid) | New version (P2P + File) |
|----------|---------------------------|--------------------------|
| **Online** | WebSocket relay via API | Direct P2P, no relay |
| **API load** | API relays every message | API only does presence + signaling |
| **Security** | API does not read content | API does not know the content; P2P does not go through the server |
| **Offline** | Store persists, API pushes metadata | Store persists, each message = 1 file |
| **Scale** | API bottleneck with many users | P2P distributes the load |

---

## 11. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| NAT/Firewall blocks P2P | Free STUN server (Google, etc.); TURN if needed |
| P2P cannot be established | Automatic fallback to file mode |
| Messages lost when Store fails | Replicate blocks; optional backup metadata on the API |
| Recipient is offline for a long time | Message metadata on the API; fetch history when online |
| Heartbeat not sent | 60s timeout → treat as offline |

---

## 12. Conclusion

- **Online**: The user enables online mode with the Central API; when both are online → P2P connection (WebRTC), messages go directly, API only does presence + signaling.
- **Offline**: Each message = 1 file on Store, leveraging `upload-metadata-raw`, `upload-file-block-raw`, `type: "chat_message"`; Central API stores metadata for fetch.
- **Encryption**: 1-1 ECIES, compatible with the existing CryptoService.
- **Integration**: Reuse Store, FileUploadService, CryptoService; add ChatP2PService, ChatPresenceService, and chat UI.

This document serves as the spec for detailed implementation and task breakdown.

## Blockchain Integration

Chat messages in Offline (File-based) mode are integrated with the Deltanium Blockchain using the `StorageContract` and `StorageOperation` pattern.

### Chat Session Bundles
To provide a smooth user experience and avoid a confirmation popup for every message:
- The app negotiates a **Chat Session Bundle** (Storage Contract) for a specific size (e.g., 5MB).
- This bundle covers multiple messages within a single conversation.
- The `ContractId` of the bundle is attached to each chat message's metadata.

### Auto-Approval
- Small storage fees for chat messages (below 0.1 DLT) are automatically approved and signed by the app.
- This ensures chat remains fluid while still being recorded on-chain.

### On-Chain Record
- Each chat message upload triggers a `StorageOperation` transaction on the blockchain.
- The transaction includes the `contractId`, `ownerPubKey`, and `metadataHash`.
- This ensures the storage node is paid and the message existence is immutable.
