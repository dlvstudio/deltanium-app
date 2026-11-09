# Deltanium Chat – Đề xuất Kiến trúc và Giải pháp Kỹ thuật (v2)

> Tài liệu đề xuất chi tiết kiến trúc chat E2E cho hệ sinh thái Deltanium, với **hai chế độ**: **Online (P2P)** và **Offline (File-based)**.

## 1. Yêu cầu tổng quan

- **Chat 1-1**: Người dùng chat trực tiếp với nhau (DM)
- **Mã hóa đầu cuối (E2E)**: Chỉ người gửi và người nhận đọc được nội dung
- **Tương thích hiện trạng**: Tận dụng mô hình identity (publicKey), crypto (ECIES), Central API và Store
- **Hai chế độ rõ ràng**:
  - **Online**: Khi cả 2 user cùng bật chế độ online → kết nối P2P trực tiếp, real-time
  - **Offline**: Khi người nhận offline → mỗi tin nhắn = 1 file, tận dụng hạ tầng Store hiện có

---

## 2. Tổng quan giải pháp

### 2.1 Ý tưởng chính

| Chế độ | Điều kiện | Cơ chế | Luồng dữ liệu |
|--------|-----------|--------|---------------|
| **Online (P2P)** | User A và B cùng bật "online" với Central API | Kết nối trực tiếp peer-to-peer | Tin nhắn đi trực tiếp A ↔ B, không qua server |
| **Offline (File-based)** | Người nhận offline hoặc không bật online | Chia sẻ file | Mỗi tin = 1 file (metadata + block) trên Store |

### 2.2 Vai trò Central API

- **Online mode**: Chỉ làm **presence registry** + **signaling server** cho WebRTC (trao đổi SDP/ICE)
- **Offline mode**: Lưu **metadata tin nhắn** (conversationId, messageId, blockId, storeNodeId) để người nhận fetch khi online
- **Không relay nội dung tin nhắn** trong cả hai chế độ
- **Auth / IDOR (đã harden):** mọi endpoint chat dùng `SignatureAuthHelper`; đọc/ghi message chỉ cho participant; `SenderPubKey` lấy từ caller đã xác thực. Offline upload dùng N-of-M (`REPLICATION_FACTOR`) giống post/file.

### 2.3 Sơ đồ tổng thể

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                        DELTANIUM CHAT – HAI CHẾ ĐỘ                                       │
└─────────────────────────────────────────────────────────────────────────────────────────┘

  CHẾ ĐỘ ONLINE (cả 2 user bật online):
  ┌──────────┐                                                    ┌──────────┐
  │  Alice   │◀──────────────── P2P (WebRTC) ────────────────────▶│   Bob    │
  │  (App)   │         Tin nhắn mã hóa E2E trực tiếp              │  (App)   │
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
                         │ (không chứa nội dung)│
                         └─────────────────────┘

  CHẾ ĐỘ OFFLINE (Bob không online):
  ┌──────────┐      upload file       ┌──────────────┐     metadata    ┌─────────────┐
  │  Alice   │ ──────────────────────▶│ Store Node   │◀────────────────│ Central API │
  │  (App)   │  (1 tin = 1 file)      │ (block mã hóa)│  POST /chat/msg │             │
  └──────────┘                        └──────┬───────┘                 └──────┬──────┘
                                             │                                 │
                                             │  Bob online lại → fetch block    │
                                             │  GET /api/file/block/{blockId}    │
                                             ▼                                 │
                                      ┌──────────┐   GET /chat/messages        │
                                      │   Bob    │◀────────────────────────────│
                                      │  (App)   │                             │
                                      └──────────┘                             │
```

---

## 3. Chi tiết chế độ Online (P2P)

### 3.1 Luồng hoạt động

```
1. Alice mở app → bật "Chế độ online" → POST /api/chat/online { pubKey, heartbeat }
2. Bob tương tự → POST /api/chat/online { pubKey, heartbeat }
3. Central API lưu: user_online_sessions.json { pubKey, lastSeen, signalingData? }
4. Alice mở chat với Bob → GET /api/chat/online-status?user=Bob
   → API trả: { online: true, signalingEndpoint? }
5. Cả 2 online → thiết lập kết nối WebRTC:
   - Alice tạo offer → gửi qua API (signaling) → Bob nhận
   - Bob tạo answer → gửi qua API → Alice nhận
   - ICE candidates trao đổi qua API
6. DataChannel WebRTC thiết lập → tin nhắn gửi trực tiếp P2P
7. Mã hóa: ECIES(K, pk_recipient) per message (hoặc session key ECDH)
```

### 3.2 Presence & Signaling API

| Method | Path | Mô tả |
|--------|------|-------|
| POST | /api/chat/online | Bật chế độ online (heartbeat mỗi 30s) |
| DELETE | /api/chat/online | Tắt chế độ online |
| GET | /api/chat/online-status?user={pubKey} | Kiểm tra user có online không |
| POST | /api/chat/signaling/offer | Gửi WebRTC offer (chỉ SDP, không nội dung) |
| POST | /api/chat/signaling/answer | Gửi WebRTC answer |
| POST | /api/chat/signaling/ice | Gửi ICE candidate |

### 3.3 Công nghệ P2P

- **WebRTC DataChannel**: Phù hợp cho Flutter (package `flutter_webrtc`)
- **NAT traversal**: WebRTC dùng STUN/TURN; có thể dùng public STUN server (hoặc tự host)
- **Signaling**: Central API chỉ relay SDP/ICE, không đọc nội dung

### 3.4 Chuyển đổi Online ↔ Offline

- Khi **Bob offline** trong lúc chat: Alice gửi tin → fallback sang chế độ file
- Khi **Bob online lại**: App Bob fetch tin nhắn offline từ Store (theo metadata trên API)
- Khi **P2P mất kết nối**: Retry P2P; nếu thất bại → chuyển sang file mode

---

## 4. Chi tiết chế độ Offline (File-based)

### 4.1 Nguyên tắc

- **Mỗi tin nhắn = 1 file** (1 metadata entry + 1 block)
- Tận dụng **100% hạ tầng hiện có**: `upload-metadata-raw`, `upload-file-block-raw`, `storedfile/register`
- `FileMetadata.Type = "chat_message"`
- `RecipientPubKey` = public key người nhận (1-1)
- `encryptedKey` = ECIES(K, pk_recipient)

### 4.2 Luồng gửi tin nhắn offline

```
1. Alice muốn gửi "Hello" cho Bob (Bob offline)
2. App tạo K (random 32 bytes)
3. payload = AES-GCM(K, JSON({ text: "Hello", createdAt, senderPubKey }))
4. encryptedKey = ECIES(K, pk_Bob)
5. Chọn Store Node từ GET /api/storenode/list
6. Upload metadata + block giống post:
   - POST Store /api/file/upload-metadata-raw (Type: chat_message, RecipientPubKey: Bob)
   - POST Store /api/file/upload-file-block-raw
7. POST Central API /api/storedfile/register (hoặc /api/chat/message)
8. API lưu metadata: { conversationId, messageId, blockId, storeNodeId, senderPubKey }
```

### 4.3 Luồng nhận tin nhắn offline

```
1. Bob online lại, mở app
2. GET /api/chat/messages?recipient={BobPubKey}&since={lastSync}
3. API trả danh sách metadata (blockId, storeNodeId, senderPubKey)
4. Bob với mỗi message: GET Store /api/file/block/{blockId}
5. ECIES decrypt → AES decrypt → hiển thị
6. Đánh dấu đã đọc (optional)
```

### 4.4 Định dạng metadata chat message

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

**Central API (chỉ index):**
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

## 5. Mô hình dữ liệu

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

### 5.3 Store – Tái sử dụng

- Dùng `upload-metadata-raw` + `upload-file-block-raw` với `type: "chat_message"`
- Không cần endpoint mới trên Store
- FileMetadata đã hỗ trợ `Type`, `RecipientPubKey`, `EncryptedKey`

---

## 6. API đề xuất tổng hợp

### 6.1 Central API – Chat Endpoints

| Method | Path | Mô tả |
|--------|------|-------|
| POST | /api/chat/online | Bật chế độ online (heartbeat) |
| DELETE | /api/chat/online | Tắt chế độ online |
| GET | /api/chat/online-status?user={pubKey} | Kiểm tra user online |
| POST | /api/chat/conversation | Tạo hoặc lấy conversation với 1 user |
| GET | /api/chat/conversations | Danh sách conversation |
| POST | /api/chat/message | Đăng ký message (metadata only, cho offline) |
| GET | /api/chat/messages/{conversationId} | Danh sách message metadata (paginated) |
| GET | /api/chat/unread-count | Số tin chưa đọc |

### 6.2 Signaling (chỉ dùng khi cả 2 online)

| Method | Path | Mô tả |
|--------|------|-------|
| POST | /api/chat/signaling/offer | Gửi WebRTC offer (Alice → Bob) |
| POST | /api/chat/signaling/answer | Gửi WebRTC answer (Bob → Alice) |
| POST | /api/chat/signaling/ice | Gửi ICE candidate |

### 6.3 Store – Không đổi

- `POST /api/file/upload-metadata-raw` với `type: "chat_message"`
- `POST /api/file/upload-file-block-raw`
- `GET /api/file/block/{blockId}`

---

## 7. Mã hóa E2E – Tận dụng hạ tầng hiện có

Chat **không cần xây dựng crypto mới** – tái sử dụng toàn bộ `CryptoService`, `EciesService`, `FileCryptoService` và `FileUploadService` đã có trong app.

### 7.1 Hạ tầng sẵn có (lib/services/)

| Service | Chức năng | Dùng cho Chat |
|---------|-----------|---------------|
| **EciesService** | `encryptWithPublicKey(data, pk)` / `decryptWithPrivateKey(data, mnemonic)` | Mã hóa K (32 bytes) cho recipient |
| **FileCryptoService** | `encryptAndSplitFile()`, `decryptMetadataBlock()`, `_encryptData()` / `_decryptData()` | Offline: encrypt message; P2P: format tương thích |
| **FileCryptoService** | `getCachedSymmetricKey()`, `cacheSymmetricKey()` | Cache key khi decrypt nhiều tin liên tiếp |
| **CryptoService** | `convertToCompressedPublicKey()`, `normalizePublicKey()` | Chuẩn hóa public key |
| **FileUploadService** | `uploadEncryptedFile()` | Offline: upload metadata + block lên Store |

### 7.2 Offline (File-based) – Gọi trực tiếp FileCryptoService

Mỗi tin nhắn = 1 file với **1 block nội dung**. Gọi `FileCryptoService.encryptAndSplitFile()`:

```dart
// ChatService gửi tin offline
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
// processed['metadataEntries'] – chọn entry có recipientPubKey = recipient
// processed['blocks'] – upload lên Store như post
```

**Decrypt** (Bob nhận tin): dùng flow giống `related_files_widget` / feed:

1. Lấy metadata từ Store (có `encryptedKey`, `recipientPubKey`, `contentBlockIds`)
2. `FileCryptoService.decryptMetadataBlock(storeMetadata, encryptedMetadataBlock, myPubKey, mnemonic)` → trả metadata + `_symmetricKey`
3. Lấy content block từ Store (`GET /api/file/block/{blockId}`)
4. `FileCryptoService.decryptRawBlockWithKey(encryptedContentBlock, symmetricKey)` → JSON text
5. Cache: `getCachedSymmetricKey()` / `cacheSymmetricKey()` nếu decrypt nhiều tin liên tiếp

**Định dạng khớp với file/post**:
- `encryptedKey` = ECIES(K, pk_recipient) – chuẩn ECIES (secp256k1, AES-CBC, HMAC-SHA256)
- Payload block = AES-GCM encrypted với K
- Store không cần sửa, `FileMetadata` đã hỗ trợ `type`, `recipientPubKey`, `encryptedKey`

### 7.3 Online (P2P) – Dùng ECIES + AES trùng format

Để **online và offline dùng chung decrypt logic**, P2P cũng dùng cùng format:

```dart
// ChatP2PService gửi tin qua DataChannel
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
// Gửi: [encryptedKey | encryptedPayload] hoặc {encryptedKey: base64, payload: base64}
```

**Decrypt** (Bob nhận qua P2P):

```dart
final K = await FileCryptoService.decryptSymmetricKeyWithPrivateKey(
  encryptedKeyBytes,
  mnemonic,
);
final decrypted = await FileCryptoService.decryptRawBlockWithKey(payloadBytes, K);
```

### 7.4 Thống nhất format – Online và Offline

| Thành phần | Online (P2P) | Offline (File) |
|------------|--------------|----------------|
| encryptedKey | EciesService.encryptWithPublicKey | encryptAndSplitFile (sharedWithPublicKeys) |
| Payload | FileCryptoService.testEncryptData | Cùng (AES-CBC, IV-prefixed) |
| Decrypt key | FileCryptoService.decryptSymmetricKeyWithPrivateKey | decryptMetadataBlock (trả `_symmetricKey`) |
| Decrypt payload | FileCryptoService.decryptRawBlockWithKey | Cùng |

→ **Một bộ decrypt** dùng cho cả P2P và file; chỉ khác nguồn dữ liệu (DataChannel vs Store).

### 7.5 Không dùng

- PRE (Umbral): chat 1-1 chỉ cần ECIES
- Signal Protocol / Double Ratchet: có thể nâng cấp sau, không cần cho MVP

---

## 8. App (Flutter) – Thay đổi đề xuất

### 8.1 Services

```
lib/services/
├── chat_service.dart           # Gửi/nhận, chọn mode (P2P vs file)
├── chat_p2p_service.dart       # WebRTC DataChannel, signaling
├── chat_presence_service.dart  # Online/offline, heartbeat
└── (tái dùng) crypto_service, file_crypto_service, file_upload_service
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
│   └── chat_conversation_screen.dart # Thread với 1 user
├── widgets/
│   ├── conversation_tile.dart
│   ├── message_bubble.dart
│   ├── chat_input.dart
│   └── online_indicator.dart        # Badge "online" / "offline"
```

### 8.4 Packages cần thêm

- `flutter_webrtc` – WebRTC DataChannel cho P2P
- (Optional) STUN/TURN server config

---

## 9. Lộ trình triển khai

### Phase 1: Offline mode (File-based) – 2–3 tuần

1. **API**: ChatController (conversation, message metadata, JSON file)
2. **Store**: Dùng file block với `type: "chat_message"` (không cần sửa Store)
3. **App**: ChatService (REST), upload/download message như file, MessagesScreen + ChatConversationScreen
4. **Polling**: Bob fetch messages mỗi 10–30s khi mở chat

### Phase 2: Presence & Online mode – 1–2 tuần

5. **API**: POST/DELETE /api/chat/online, GET online-status
6. **App**: ChatPresenceService, toggle "Chế độ online", hiển thị trạng thái online/offline
7. **Logic**: Nếu người nhận offline → dùng file mode; nếu online → chuẩn bị P2P

### Phase 3: P2P (WebRTC) – 2–3 tuần

8. **API**: Signaling endpoints (offer, answer, ice)
9. **App**: ChatP2PService với flutter_webrtc, kết nối DataChannel
10. **Flow**: Khi cả 2 online → thiết lập P2P, gửi tin trực tiếp
11. **Fallback**: P2P lỗi → chuyển sang file mode

### Phase 4: Tối ưu – 1–2 tuần

12. Offline queue: lưu tin chưa gửi, retry khi có mạng
13. Đếm chưa đọc, badge
14. Typing indicator (P2P: qua DataChannel; Offline: không support)

### Phase 5 (tùy chọn)

15. Gửi file/media trong chat (tái dùng FileUploadService)
16. Group chat – cần ECIES multi-recipient hoặc Sender Key

---

## 10. So sánh với bản cũ (Hybrid WebSocket)

| Tiêu chí | Bản cũ (Hybrid) | Bản mới (P2P + File) |
|----------|-----------------|------------------------|
| **Online** | WebSocket relay qua API | P2P trực tiếp, không relay |
| **Tải API** | API relay mọi tin nhắn | API chỉ presence + signaling |
| **Bảo mật** | API không đọc nội dung | API không biết nội dung, P2P không qua server |
| **Offline** | Store lưu, API push metadata | Store lưu, mỗi tin = 1 file |
| **Scale** | API bottleneck khi nhiều user | P2P phân tán tải |

---

## 11. Rủi ro và giảm thiểu

| Rủi ro | Giảm thiểu |
|--------|------------|
| NAT/Firewall chặn P2P | STUN server miễn phí (Google, etc.); TURN nếu cần |
| P2P không thiết lập được | Fallback sang file mode tự động |
| Tin nhắn mất khi Store lỗi | Replicate blocks; optional backup metadata trên API |
| Người nhận offline lâu | Message metadata trên API; fetch history khi online |
| Heartbeat quên gửi | Timeout 60s → coi là offline |

---

## 12. Kết luận

- **Online**: User bật chế độ online với Central API; khi cả 2 online → kết nối P2P (WebRTC), tin nhắn trực tiếp, API chỉ làm presence + signaling.
- **Offline**: Mỗi tin nhắn = 1 file trên Store, tận dụng `upload-metadata-raw`, `upload-file-block-raw`, `type: "chat_message"`; Central API lưu metadata để fetch.
- **Mã hóa**: ECIES 1-1, tương thích CryptoService hiện có.
- **Tích hợp**: Tái sử dụng Store, FileUploadService, CryptoService; thêm ChatP2PService, ChatPresenceService và UI chat.

Tài liệu này dùng làm spec cho implementation chi tiết và task breakdown.

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
