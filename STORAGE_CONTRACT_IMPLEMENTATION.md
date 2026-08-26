# Storage Contract Implementation Guide

## Overview
This document provides a complete guide to the Storage Contract workflow implementation for Deltanium. Storage Contracts enable secure, pre-negotiated agreements between Apps (users) and Storage Nodes before file uploads occur.

## Architecture

### Key Components

#### 1. **Storage Contract Models**
- **Location**: 
  - `.NET`: `deltanium-api/Models/StorageContract.cs` & `deltanium-blocker/Core/StorageContract.cs`
  - **Dart**: `deltanium-app/lib/models/storage_contract.dart`

- **Key Fields**:
  - `ContractId`: Unique identifier
  - `ContractType`: "TimeFixed" or "OpenEnded"
  - `AppPublicKey` / `StorageNodePublicKey`: Signing parties
  - `StartDateUnix` / `EndDateUnix`: Duration terms
  - `TotalFileSize`: Maximum storage in bytes
  - `TotalFee`: Storage fees in Deltanium
  - `FileIds`: List of files covered
  - `AppSignature` / `StorageNodeSignature`: Dual signatures for proof
  - `MessageToSign`: Message format: `Type|{date}|{pubkey}|{fee}|{size}`

#### 2. **Extended Transaction Model**
- **File**: `deltanium-blocker/Core/Transaction.cs` & `deltanium-api/Models/BlockchainTransaction.cs`
- **Changes**:
  - Added `Cosignatures` dictionary for multi-party signatures
  - Added `Contract` property for StorageContract objects
  - Supports type-specific data in `Data[string, object]` dictionary

#### 3. **Extended FileMetadata**
- **File**: `deltanium-store/Models/FileMetadata.cs`
- **New Fields**:
  - `ContractId`: Links metadata to contract
  - `ContractStatus`: Tracks contract state
  - `ContractStartDate` / `ContractEndDate`: Contract term boundaries

---

## Workflow

### Phase 1: Contract Creation (Off-Chain)

**Actors**: App (User), Storage Node

1. **App Creates Contract Proposal**
   - Specifies: file IDs, duration, size limit, fees
   - Generates message: `TimeFixed|{start}|{end}|{appPubKey}|{nodePubKey}|{fee}|{size}`
   - Signs with App's private key

2. **Storage Node Reviews & Signs**
   - Verifies terms are acceptable
   - Signs same message with Node's private key
   - Stores both signatures

3. **Storage Node Marks Active**
   - Updates contract status to "Active"
   - Contract is now enforceable

### Phase 2: File Upload with Contract Validation

**Endpoints**: `POST /api/file/upload-metadata-raw`, `POST /api/file/upload-file-block-raw`

1. **App Calls Upload Endpoints**
   - Includes `X-Contract-Id` header
   - FileMetadata includes `contractId` field

2. **Store Validates Against Contract**
   ```csharp
   // In FileController
   if (!string.IsNullOrEmpty(metadata.ContractId))
   {
       var (valid, error) = await _contractService.ValidateUploadAgainstContractAsync(
           metadata.ContractId,
           metadata.FileId,
           metadata.FileSize ?? 0,
           userPubKey);
       
       if (!valid)
           return BadRequest();
   }
   ```

3. **Validation Checks**:
   - Contract exists and is Active
   - Current time is within contract duration
   - FileId is in contract.FileIds list
   - FileSize ≤ contract.TotalFileSize
   - Both signatures present and valid

### Phase 3: StorageOperation Transaction Creation

**Actor**: Storage Node (after successful upload)

1. **Create Transaction with Contract Proof**
   ```csharp
   var storageOp = new StorageOperation
   {
       ContractId = contract.ContractId,
       ContractObject = contract, // Full contract w/ signatures
       FileIds = uploadedFileIds,
       BlockId = blockId,
       FileSize = totalSize,
   };
   
   var tx = new BlockchainTransaction
   {
       Type = "StorageOperation",
       From = storageNodePubKey,
       Fee = contract.TotalFee,
       Data = {
           { "contract", contract },
           { "FileIds", fileIds },
           { "FileSize", fileSize }
       },
       Signature = storageNodeSignature // Node's tx signature
   };
   ```

2. **App Provides Cosignature**
   - App signs same transaction data to approve upload
   - Submits as `Cosignatures[appPubKey] = appSignature`
   ```csharp
   tx.Cosignatures[contract.AppPublicKey] = appSignature;
   ```

3. **Submit Transaction to API**
   ```
   POST /api/tx/submit
   Body: BlockchainTransaction with contract + cosignatures
   ```

### Phase 4: Blocker Validation

**Component**: `deltanium-blocker/Services/BlockValidator.cs`

1. **Extract & Parse Contract**
   - Get contract object from `tx.Data["contract"]`
   - Deserialize StorageContract

2. **Validate Six Rules**:
   ```csharp
   // Rule 1: Both signatures present
   if (!contract.AppSignature || !contract.StorageNodeSignature)
       return false;
   
   // Rule 2: Fee matches
   if (tx.Fee != contract.TotalFee)
       return false;
   
   // Rule 3: FileIds covered
   foreach (fileId in txFileIds)
       if (!contract.CoversFileId(fileId))
           return false;
   
   // Rule 4: FileSize within limit
   if (txFileSize > contract.TotalFileSize)
       return false;
   
   // Rule 5: Contract valid now
   if (!contract.IsValidNow())
       return false;
   
   // Rule 6: App cosignature exists
   if (!tx.Cosignatures.ContainsKey(contract.AppPublicKey))
       return false;
   ```

3. **Include in Block**
   - If all validations pass, include StorageOperation in block
   - Fee is split: 70% Storage Node, 30% Block Creator

---

## API Endpoints

### Store Contract Management (`/api/storage/contracts`)

#### Create Contract
```http
POST /api/storage/contracts/create
X-User-PubKey: {appPubKey}
Content-Type: application/json

{
  "contractType": "TimeFixed",
  "startDateUnix": 1704067200,
  "endDateUnix": 1735689600,
  "appPublicKey": "{appPubKey}",
  "storageNodePublicKey": "{nodePubKey}",
  "totalFileSize": 1073741824,
  "totalFee": 100.0,
  "fileIds": ["fileId1", "fileId2"]
}

Response 200:
{
  "contractId": "{uuid}",
  "status": "Pending",
  "message": "Contract created..."
}
```

#### Sign Contract (Storage Node)
```http
POST /api/storage/contracts/sign/{contractId}
Content-Type: application/json

{
  "storageNodeSignature": "{signature}"
}

Response 200:
{
  "contractId": "{uuid}",
  "status": "Active",
  "message": "Contract signed by Storage Node..."
}
```

#### Validate Upload
```http
POST /api/storage/contracts/validate
X-User-PubKey: {appPubKey}
Content-Type: application/json

{
  "contractId": "{uuid}",
  "fileId": "file123",
  "fileSize": 5242880
}

Response 200:
{ "valid": true }
```

#### List Active Contracts
```http
GET /api/storage/contracts/list/active
X-User-PubKey: {appPubKey}

Response 200:
{
  "count": 2,
  "contracts": [...]
}
```

---

## File Upload with Contract

### Upload Metadata
```http
POST /api/file/upload-metadata-raw
X-User-PubKey: {userPubKey}
Content-Type: application/json

{
  "fileId": "file123",
  "firstBlockId": "block0_hash",
  "encryptedKey": [base64 data],
  "contractId": "{contractId}",
  "type": "file",
  "shareType": "me"
}
```

### Upload File Block
```http
POST /api/file/upload-file-block-raw
X-User-PubKey: {userPubKey}
X-File-Id: file123
X-Block-Id: block0_hash
X-Block-Index: 0
X-Contract-Id: {contractId}

[binary file block data]
```

---

## Implementation Checklist

### ✅ Completed Components

#### Models
- [x] `StorageContract.cs` (.NET) - with TimeFixed/OpenEnded support
- [x] `StorageContract.dart` (Flutter) - mirrored with validation logic
- [x] `Transaction.cs` - added Cosignatures dictionary
- [x] `BlockchainTransaction.cs` - added Contract property
- [x] `FileMetadata.cs` - added ContractId, ContractStatus, ContractDates

#### Services
- [x] `StorageContractService.cs` (Store) - contract lifecycle management
- [x] `StorageOperationService.cs` (API) - StorageOperation creation
- [x] `StorageContractService.dart` (App) - contract + upload integration

#### Controllers
- [x] `ContractController.cs` (Store) - create, sign, validate, list endpoints
- [x] `FileController.cs` (Store) - integrated contract validation in upload endpoints

#### Validation
- [x] `BlockValidator.cs` (Blocker) - StorageOperation-specific validation rules
  - Contract signature verification
  - Fee matching
  - FileId coverage
  - File size limits
  - Time validity checks
  - App cosignature requirement

#### DI Registration
- [x] `Program.cs` (Store) - registered `IStorageContractService`

---

## Key Validation Rules

### During Upload (Store)
1. FileId must be in contract.FileIds
2. FileSize ≤ contract.TotalFileSize
3. Current time within contract validity
4. Both signatures present on contract

### During Blockchain Validation (Blocker)
1. Contract must be embedded in transaction
2. App signature present on contract
3. Storage Node signature present
4. Transaction fee = contract.TotalFee
5. FileIds match contract list
6. FileSize within contract limit
7. Time validity confirmed
8. App cosignature present on transaction

---

## Error Handling

### Contract Validation Errors
Return HTTP 400 with detailed error:
```json
{
  "error": "Contract validation failed",
  "details": "File ID {fileId} not covered by contract"
}
```

### Invalid Contract State
- "Contract not found"
- "Contract is not active"
- "Contract time period is invalid"
- "File size exceeds contract limit"
- "StorageOperation must include App cosignature"

---

## Message Signing Format

### TimeFixed Contract
```
TimeFixed|{startDate}|{endDate}|{appPublicKey}|{storageNodePublicKey}|{totalFee}|{totalFileSize}
```

### OpenEnded Contract
```
OpenEnded|{startDate}|{appPublicKey}|{storageNodePublicKey}|{totalFee}|{totalFileSize}
```

---

## Security Considerations

1. **Dual Signatures**: Both App and Storage Node must sign for contract validity
2. **Cosignature Verification**: Blocker verifies App's secondary signature on StorageOperation
3. **Message Canonicalization**: Standardized message format prevents signature tampering
4. **Time Validation**: Contracts automatically expire based on type (TimeFixed vs OpenEnded)
5. **No Central API Dependency**: Blocker validates using supplied contract proof only

---

## Integration Points

### For App Developers
1. Create `StorageContractService` instance with Store URL
2. Call `createContract()` to propose terms
3. Wait for Storage Node to sign
4. Call `uploadFileMetadata()` with contractId
5. Call `uploadFileBlock()` for each block
6. Create StorageOperation with cosignature when ready

### For Storage Node Developers
1. Implement contract signing endpoint
2. Validate uploads against contract before accepting
3. Create StorageOperation with full contract object
4. Submit transaction with Storage Node signature
5. Include contract in transaction Data

### For Block Creator/Blocker
1. Use enhanced `BlockValidator` for StorageOperation validation
2. Extract contract from `tx.Data["contract"]`
3. Apply 6 validation rules
4. Include transaction if all rules pass

---

## Testing Scenarios

1. **Happy Path**: App creates contract → Node signs → Upload succeeds → Transaction validated
2. **Contract Mismatch**: Upload fileId not in contract → Rejected at Store
3. **Expired Contract**: TimeFixed contract past end date → Rejected during upload
4. **Fee Mismatch**: StorageOperation fee ≠ contract.TotalFee → Rejected by Blocker
5. **Missing Cosignature**: StorageOperation without App signature → Rejected by Blocker
6. **No Signature Verification**: App or Node signature missing → Upload rejected

