# Post Upload with Storage Cost Confirmation - Integration Guide

## Overview
When a user creates/uploads a post, the app will:
1. Calculate the file size
2. Call the Store API to get the storage price (calculated by the Storage Node)
3. Show a fee confirmation dialog to the user
4. If the user confirms → sign the contract + upload
5. If the user cancels → stop

## Usage Example

### In Your Create Post Screen (UI)

```dart
import 'package:deltanium_app/services/post_service.dart';
import 'package:deltanium_app/widgets/confirm_storage_cost_dialog.dart';

class CreatePostScreen extends StatefulWidget {
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  bool _isLoading = false;

  /// User taps "Upload" button
  void _onUploadPressed() async {
    setState(() => _isLoading = true);
    
    try {
      // Step 1: Create post (local processing)
      final postResult = await PostService.createPost(
        textContent: _textController.text,
        authorPublicKey: userPublicKey,
        mnemonic: userMnemonic,
        attachedMedia: selectedMedia,
        onProgress: (msg) => setState(() => _progressMessage = msg),
      );

      if (!postResult['success']) {
        _showError('Failed to create post');
        return;
      }

      // Step 2: Prepare upload with cost calculation
      final storageInfo = await PostService.preparePostUploadWithStorageCost(
        postResult: postResult,
        storeBaseUrl: storeBaseUrl,
        appPublicKey: userPublicKey,
        storageNodePublicKey: storageNodePublicKey,
        durationDays: 365,
        onProgress: (msg) => setState(() => _progressMessage = msg),
      );

      if (!storageInfo['success']) {
        _showError(storageInfo['error'] ?? 'Failed to calculate cost');
        return;
      }

      // Step 3: Show confirmation dialog
      if (!mounted) return;
      
      ConfirmStorageCostDialog.show(
        context: context,
        totalFee: storageInfo['totalFee'] as double,
        durationDays: storageInfo['durationDays'] as int,
        costPerDay: storageInfo['estimatedCostPerDay'] as double,
        estimatedSizeBytes: storageInfo['estimatedSize'] as int,
        feeBasis: storageInfo['feeBasis'] as String,
        
        // User confirms
        onConfirm: () async {
          await _confirmAndUpload(postResult, storageInfo);
        },
        
        // User cancels
        onCancel: () {
          _showMessage('Upload cancelled');
        },
      );

    } catch (e) {
      _showError('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Step 4: Confirm and upload
  Future<void> _confirmAndUpload(
    Map<String, dynamic> postResult,
    Map<String, dynamic> storageInfo,
  ) async {
    try {
      setState(() => _isLoading = true);
      
      final uploadResult = await PostService.confirmAndUploadPost(
        postResult: postResult,
        storageInfo: storageInfo,
        storeBaseUrl: storeBaseUrl,
        appPublicKey: userPublicKey,
        storageNodePublicKey: storageNodePublicKey,
        userPrivateKeyForSigning: userPrivateKey,
        selectedNode: selectedStorageNode,
        onProgress: (msg) => setState(() => _progressMessage = msg),
      );

      if (uploadResult['success']) {
        _showMessage('✅ Post uploaded successfully!');
        _clearForm();
        Navigator.pop(context);
      } else {
        _showError(uploadResult['error'] ?? 'Upload failed');
      }
    } catch (e) {
      _showError('Error during upload: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Post')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Text input
            TextField(
              controller: _textController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'What\'s on your mind?',
                border: OutlineInputBorder(),
              ),
            ),
            
            // Progress indicator
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(_progressMessage),
                  ],
                ),
              ),
            
            // Upload button
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Upload Post'),
              onPressed: _isLoading ? null : _onUploadPressed,
            ),
          ],
        ),
      ),
    );
  }
}
```

## Flow Diagram

```
User creates post with media
         ↓
PostService.createPost()
  └─ Encrypts content + splits into blocks
         ↓
PostService.preparePostUploadWithStorageCost()
  └─ Calculates total file size
  └─ Calls Store API to create contract proposal
  └─ Store calculates fee & returns
         ↓
ConfirmStorageCostDialog.show()
  └─ Display fee breakdown to user
         ↓
    User decides
    /         \
[Cancel]    [Confirm]
  |            |
  └─ Exit      PostService.confirmAndUploadPost()
               ├─ Signs contract (App approves fee)
               ├─ Calls Store sign endpoint
               ├─ uploadPost() (actual file upload)
               └─ Returns result
                  ↓
              ✅ Success or ❌ Error
```

## API Integration (In PostService helpers)

The `_createContractProposal` and `_signAndApproveContract` should call real HTTP endpoints:

```dart
// In _createContractProposal()
static Future<Map<String, dynamic>> _createContractProposal(...) async {
  final response = await http.post(
    Uri.parse('$storeBaseUrl/api/storage/contracts/create'),
    headers: {
      'Content-Type': 'application/json',
      'X-User-PubKey': appPublicKey,
    },
    body: jsonEncode({
      'contractType': contractType,
      'startDateUnix': startDateUnix,
      'endDateUnix': endDateUnix,
      'totalFileSize': totalFileSize,
      'fileIds': fileIds,
    }),
  );
  
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    return {
      'success': true,
      'contractId': data['contractId'],
      'totalFee': data['totalFee'],
      'feeBasis': data['feeBasis'],
    };
  } else {
    return {'success': false, 'error': response.body};
  }
}

// In _signAndApproveContract()
static Future<Map<String, dynamic>> _signAndApproveContract(...) async {
  // Generate message to sign
  final message = StorageContract.generateMessageToSign(...);
  
  // Sign with app's private key (using existing signer)
  final signature = await signer.signData(message);
  
  final response = await http.post(
    Uri.parse('$storeBaseUrl/api/storage/contracts/sign/$contractId'),
    headers: {
      'Content-Type': 'application/json',
      'X-User-PubKey': appPublicKey,
    },
    body: jsonEncode({
      'appSignature': signature,
    }),
  );
  
  if (response.statusCode == 200) {
    return {'success': true, 'status': 'Active'};
  } else {
    return {'success': false, 'error': response.body};
  }
}
```

## Dialog Display Details

The `ConfirmStorageCostDialog` shows:
- **Duration**: How long storage is contracted for
- **Size**: Estimated file size
- **Unit Cost**: Per day cost
- **Total Cost**: Highlighted in blue box
- **Fee Basis**: Calculation explanation (e.g., "2.5GB × 6.08 months × 2.0 DLT/GB-month")
- **Warning**: "This cost will be deducted from your account upon confirmation"

## Error Handling

```dart
// If contract creation fails
"Failed to create contract proposal"
└─ User sees: "Storage service temporarily unavailable"

// If user rejects fee
"Upload cancelled"
└─ No cost deducted, post discarded

// If upload fails after fee paid
"Failed to upload post"
└─ Show retry option or refund process

// If signing fails
"Failed to sign contract"
└─ User should retry or contact support
```

## Future Enhancements

- [ ] Payment/credits balance check before showing dialog
- [ ] Multiple storage duration options (30/90/365 days)
- [ ] Different storage tiers (standard/premium)
- [ ] Wallet integration for auto-payment
- [ ] Transaction history showing storage charges
- [ ] Contract extension/renewal UI
- [ ] Cost estimation with different file sizes
