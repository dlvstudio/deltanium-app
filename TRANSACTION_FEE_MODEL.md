# Deltanium Transaction Fee Model & Analysis

**Last Updated:** February 11, 2026  
**Status:** Knowledge Base - Pending Implementation

---

## Table of Contents

1. [Node Architecture](#node-architecture)
2. [Fee Flow by Transaction Type](#fee-flow-by-transaction-type)
3. [Storage Fee Model (Initial & Renewal)](#storage-fee-model)
4. [Fee Distribution Patterns](#fee-distribution-patterns)
5. [Edge Cases & Governance](#edge-cases--governance)
6. [Implementation Recommendations](#implementation-recommendations)

---

## Node Architecture

### System Overview

```
┌─────────────────────────────────────────────────────┐
│          DELTANIUM NETWORK ARCHITECTURE              │
├─────────────────────────────────────────────────────┤
│                                                       │
│  👤 USER NODE (User Client/Wallet)                  │
│     - Create transactions, manage private keys      │
│     - Pay fees, receive transfers                    │
│                                                       │
│  🏢 CENTRAL NODE (Deltanium-API Server)             │
│     - Authenticate users, store metadata            │
│     - Manage vouchers and user profiles             │
│     - Control authorization                         │
│                                                       │
│  ⛓️ BLOCK CREATOR NODE (Deltanium-Blocker)          │
│     - Create blocks, forge transactions             │
│     - Collect transaction fees                      │
│     - Maintain blockchain                           │
│                                                       │
│  💾 STORAGE NODE (Deltanium-Store)                  │
│     - Store encrypted files and blocks              │
│     - Serve file retrieval                          │
│     - Charge for storage/bandwidth                  │
│                                                       │
└─────────────────────────────────────────────────────┘
```

---

## Storage Contract Model (NEW)

### Overview: Pre-Agreement Before File Upload

**Key Concept:** Before uploading any file (post, media, comment, etc.), App (User) and Storage Node must sign a **Storage Contract** that specifies:
- Storage commitment terms (time-based or open-ended)
- Total fee
- Total file size
- File identifiers
- Both parties' signatures

### Contract Types

#### 1️⃣ Time-Fixed Storage Contract

```json
{
  "contractId": "contract_uuid",
  "type": "TimeFixed",
  "appPublicKey": "user_pubkey",
  "storageNodePublicKey": "node_store_pubkey",
  
  "terms": {
    "startDate": 1707550800,        // Unix timestamp
    "endDate": 1708155600,          // 30 days later (example)
    "totalDuration": 30,             // days
    "totalFileSize": 5242880,        // bytes (5 MB)
    "totalFee": 105,                 // D coins
    "fileIds": ["file_id_1", "file_id_2"]  // all files in contract
  },
  
  "signatureData": {
    "messageToSign": "TimeFixed|1707550800|1708155600|user_pubkey|node_store_pubkey|105|5242880",
    "appSignature": "sig_from_app_private_key",
    "storageNodeSignature": "sig_from_storage_node_private_key"
  },
  
  "status": "Active",
  "createdAt": 1707550800,
  "expiresAt": 1708155600
}
```

**Use Case:** User wants guaranteed storage for 30 days
- **Start:** File uploaded immediately
- **Duration:** Fixed 30 days
- **Renewal:** User must create new contract to extend
- **Auto-delete:** After endDate, Storage Node can delete file

---

#### 2️⃣ Open-Ended Storage Contract (No Time Limit)

```json
{
  "contractId": "contract_uuid",
  "type": "OpenEnded",
  "appPublicKey": "user_pubkey",
  "storageNodePublicKey": "node_store_pubkey",
  
  "terms": {
    "startDate": 1707550800,        // Unix timestamp
    "endDate": null,                 // No expiration
    "totalFileSize": 5242880,        // bytes
    "totalFee": 500,                 // D coins (one-time)
    "fileIds": ["file_id_1"]
  },
  
  "signatureData": {
    "messageToSign": "OpenEnded|1707550800|user_pubkey|node_store_pubkey|500|5242880",
    "appSignature": "sig_from_app_private_key",
    "storageNodeSignature": "sig_from_storage_node_private_key"
  },
  
  "autoDeleteAfter": 365,            // Storage node deletes after 1 year if not renewed
  "status": "Active",
  "createdAt": 1707550800
}
```

**Use Case:** User wants long-term storage without renewal hassle
- **Duration:** Indefinite
- **Fee:** One-time (higher than time-fixed for convenience)
- **Auto-clean:** After 1 year, Storage Node removes file automatically
- **Cost Justification:** Simpler for both parties (no renewal tracking)

---

### Storage Contract Lifecycle

```
┌────────────────────────────────────────────────────────┐
│         STORAGE CONTRACT LIFECYCLE                      │
├────────────────────────────────────────────────────────┤
│                                                         │
│ PHASE 1: NEGOTIATION & SIGNING                        │
│ ├─ App initiates contract                             │
│ │  (terms: duration, size, fee)                       │
│ ├─ Storage Node reviews & accepts                     │
│ ├─ Both parties sign contract                         │
│ └─ Contract status: "Active"                          │
│                                                         │
│ PHASE 2: FILE UPLOAD                                  │
│ ├─ App uploads files to Storage Node                  │
│ ├─ Files reference contractId                         │
│ ├─ Storage Node validates against contract            │
│ │  (total size, file count)                           │
│ └─ Files stored with contractId tag                   │
│                                                         │
│ PHASE 3: STORAGE OPERATION TRANSACTION                │
│ ├─ Storage Node creates StorageOperation tx           │
│ │  (includes contractId as proof)                     │
│ ├─ App signs approval (secondary signature)           │
│ ├─ Blocker verifies:                                  │
    ... (content omitted for brevity) ...
