import 'package:deltanium_app/models/storage_contract.dart';
import 'package:deltanium_app/services/request_signer.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:deltanium_app/services/app_logger.dart';

/// Service for managing storage contracts and operations
/// Handles contract creation, signing, and storage file uploads
class StorageContractService {
  final String storeBaseUrl; // e.g., "http://localhost:5001"
  final RequestSigner _signer;

  StorageContractService({
    required this.storeBaseUrl,
    required RequestSigner signer,
  }) : _signer = signer;

  /// Create a new storage contract proposal
  /// App proposes terms (files, duration, size); Storage Node calculates and returns fee
  /// Initial status: "PendingAppApproval"
  Future<StorageContract?> createContract({
    required String contractType, // "TimeFixed" or "OpenEnded"
    required int startDate,
    int? endDate,
    required int totalFileSize,
    required List<String> fileIds,
    required String appPublicKey,
    required String storageNodePublicKey,
  }) async {
    try {
      final request = {
        'contractType': contractType,
        'startDateUnix': startDate,
        'endDateUnix': endDate,
        'totalFileSize': totalFileSize,
        'fileIds': fileIds,
      };

      final bodyBytes = utf8.encode(jsonEncode(request));
      final signature = await _signer.signRequest('POST', '/api/storage/contracts/create', Uint8List.fromList(bodyBytes));
      final normalizedPubKey = _signer.getPublicKeyBase64();

      final response = await http.post(
        Uri.parse('$storeBaseUrl/api/storage/contracts/create'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': normalizedPubKey,
          'X-Timestamp': signature['timestamp']!,
          'X-Signature': signature['signature']!,
        },
        body: jsonEncode(request),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Store returns content + contractHash (envelope source of truth); use contractHash for V2 signing
        final contractHashFromStore = data['contractHash'] as String? ?? '';
        final contract = StorageContract(
          contractId: data['contractId'] ?? '',
          contractType: contractType,
          appPublicKey: appPublicKey,
          storageNodePublicKey: storageNodePublicKey,
          startDateUnix: startDate,
          endDateUnix: endDate,
          totalFileSize: totalFileSize,
          totalFee: (data['totalFee'] as num?)?.toDouble() ?? 0.0,
          totalFeeCanonical: data['totalFeeCanonical'] as String?,
          fileIds: fileIds,
          contractHash: contractHashFromStore,
          messageToSign: '', // Will be set when signing (V1)
          appSignature: '',
          storageNodeSignature: '',
          createdAtUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          status: data['status'] ?? 'PendingAppApproval',
        );
        AppLogger.log('Contract created with fee: ${contract.totalFee} DLT (${data['feeBasis']})');
        return contract;
      } else {
        AppLogger.log('Failed to create contract: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      AppLogger.log('Error creating contract: $e');
      return null;
    }
  }

  /// Signing version: 1 = sign message (legacy, ensures blocks are created); 2 = sign contract hash.
  /// Default 2 so post creation uses contract hash (V2) signing.
  static const int defaultSigningVersion = 2;

  /// Sign a storage contract on behalf of the App.
  /// [signingVersion]: 1 = sign message (legacy); 2 = sign contract hash.
  Future<StorageContract?> approveAndSignContract({
    required StorageContract contract,
    required String appPrivateKey, // For signing (in production, use secure key management)
    int signingVersion = defaultSigningVersion,
  }) async {
    try {
      if (signingVersion == 2) {
        // V2: sign contract hash. Prefer Store's hash from create (envelope); else compute locally.
        final contractHash = contract.contractHash.isNotEmpty
            ? contract.contractHash
            : StorageContract.computeContractHash(contract);
        final appSignature = await _signer.signData(contractHash);
        final request = {'appSignature': appSignature, 'signingVersion': 2};
        return _sendSignRequest(contract, request, (data) {
          contract.contractHash = data['contractHash'] as String? ?? data['hash'] as String? ?? contractHash;
          contract.appSignature = data['appSignature'] as String? ?? appSignature;
          contract.storageNodeSignature = data['storageNodeSignature'] as String? ?? '';
          contract.status = data['status'] ?? 'Active';
        });
      }

      // V1: sign message (legacy format; Blocker accepts this and creates blocks)
      final messageToSign = StorageContract.generateMessageToSign(
        contractType: contract.contractType,
        startDate: contract.startDateUnix,
        endDate: contract.endDateUnix,
        appPublicKey: contract.appPublicKey,
        storageNodePublicKey: contract.storageNodePublicKey,
        totalFee: contract.totalFee,
        totalFileSize: contract.totalFileSize,
      );
      final appSignature = await _signer.signData(messageToSign);
      final request = {
        'appSignature': appSignature,
        'messageToSign': messageToSign,
        'signingVersion': 1,
      };
      return _sendSignRequest(contract, request, (data) {
        contract.messageToSign = data['messageToSign'] as String? ?? messageToSign;
        contract.appSignature = appSignature;
        contract.storageNodeSignature = data['storageNodeSignature'] as String? ?? '';
        contract.status = data['status'] ?? 'Active';
      });
    } catch (e) {
      AppLogger.log('Error signing contract: $e');
      return null;
    }
  }

  Future<StorageContract?> _sendSignRequest(
    StorageContract contract,
    Map<String, dynamic> request,
    void Function(Map<String, dynamic> data) applyResponse,
  ) async {
    final bodyBytes = utf8.encode(jsonEncode(request));
    final signature = await _signer.signRequest(
      'POST',
      '/api/storage/contracts/sign/${contract.contractId}',
      Uint8List.fromList(bodyBytes),
    );
    final normalizedPubKey = _signer.getPublicKeyBase64();
    final response = await http.post(
      Uri.parse('$storeBaseUrl/api/storage/contracts/sign/${contract.contractId}'),
      headers: {
        'Content-Type': 'application/json',
        'X-User-PubKey': normalizedPubKey,
        'X-Timestamp': signature['timestamp']!,
        'X-Signature': signature['signature']!,
      },
      body: jsonEncode(request),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      applyResponse(data);
      AppLogger.log('Contract approved and signed by App');
      return contract;
    }
    AppLogger.log('Failed to sign contract: ${response.statusCode} - ${response.body}');
    return null;
  }

  /// Get a contract by ID
  Future<StorageContract?> getContract({
    required String contractId,
    required String userPublicKey,
  }) async {
    try {
      final signature = await _signer.signRequest('GET', '/api/storage/contracts/$contractId');
      final normalizedPubKey = _signer.getPublicKeyBase64();
      final response = await http.get(
        Uri.parse('$storeBaseUrl/api/storage/contracts/$contractId'),
        headers: {
          'X-User-PubKey': normalizedPubKey,
          'X-Timestamp': signature['timestamp']!,
          'X-Signature': signature['signature']!,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return StorageContract.fromJson(data);
      }
      return null;
    } catch (e) {
      AppLogger.log('Error fetching contract: $e');
      return null;
    }
  }

  /// Validate that a file upload matches a contract
  Future<bool> validateUpload({
    required String contractId,
    required String fileId,
    required int fileSize,
    required String userPublicKey,
  }) async {
    try {
      final body = jsonEncode({
        'contractId': contractId,
        'fileId': fileId,
        'fileSize': fileSize,
      });
      final signature = await _signer.signRequest('POST', '/api/storage/contracts/validate', Uint8List.fromList(utf8.encode(body)));
      final normalizedPubKey = _signer.getPublicKeyBase64();
      final response = await http.post(
        Uri.parse('$storeBaseUrl/api/storage/contracts/validate'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': normalizedPubKey,
          'X-Timestamp': signature['timestamp']!,
          'X-Signature': signature['signature']!,
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['valid'] == true;
      }
      return false;
    } catch (e) {
      AppLogger.log('Error validating upload: $e');
      return false;
    }
  }

  /// List active contracts for user
  Future<List<StorageContract>> listActiveContracts({
    required String userPublicKey,
  }) async {
    try {
      final signature = await _signer.signRequest('GET', '/api/storage/contracts/list/active');
      final normalizedPubKey = _signer.getPublicKeyBase64();
      final response = await http.get(
        Uri.parse('$storeBaseUrl/api/storage/contracts/list/active'),
        headers: {
          'X-User-PubKey': normalizedPubKey,
          'X-Timestamp': signature['timestamp']!,
          'X-Signature': signature['signature']!,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final contracts = (data['contracts'] as List<dynamic>?)
            ?.map((c) => StorageContract.fromJson(c as Map<String, dynamic>))
            .toList() ?? [];
        return contracts;
      }
      return [];
    } catch (e) {
      AppLogger.log('Error listing contracts: $e');
      return [];
    }
  }

  /// Upload file metadata with contract reference
  Future<bool> uploadFileMetadata({
    required String contractId,
    required String fileId,
    required String firstBlockId,
    required List<int> encryptedKey,
    required String userPublicKey,
    String? type,
    String? shareType,
  }) async {
    try {
      // First validate against contract
      final isValid = await validateUpload(
        contractId: contractId,
        fileId: fileId,
        fileSize: encryptedKey.length,
        userPublicKey: userPublicKey,
      );

      if (!isValid) {
        AppLogger.log('File does not match contract terms');
        return false;
      }

      final metadata = {
        'fileId': fileId,
        'firstBlockId': firstBlockId,
        'encryptedKey': base64Encode(encryptedKey),
        'contractId': contractId,
        'type': type ?? 'file',
        'shareType': shareType ?? 'me',
        'encryptedType': 'encrypted',
        'version': '2.0',
      };

      final body = jsonEncode(metadata);
      final signature = await _signer.signRequest('POST', '/api/file/upload-metadata-raw', Uint8List.fromList(utf8.encode(body)));
      final normalizedPubKey = _signer.getPublicKeyBase64();
      final response = await http.post(
        Uri.parse('$storeBaseUrl/api/file/upload-metadata-raw'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-PubKey': normalizedPubKey,
          'X-Timestamp': signature['timestamp']!,
          'X-Signature': signature['signature']!,
        },
        body: body,
      );

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.log('Error uploading file metadata: $e');
      return false;
    }
  }

  /// Upload file block with contract reference
  Future<bool> uploadFileBlock({
    required String contractId,
    required String fileId,
    required String blockId,
    required int blockIndex,
    required List<int> blockData,
    required String userPublicKey,
  }) async {
    try {
      final signature = await _signer.signRequest('POST', '/api/file/upload-file-block-raw', Uint8List.fromList(blockData));
      final normalizedPubKey = _signer.getPublicKeyBase64();
      final response = await http.post(
        Uri.parse('$storeBaseUrl/api/file/upload-file-block-raw'),
        headers: {
          'X-User-PubKey': normalizedPubKey,
          'X-Timestamp': signature['timestamp']!,
          'X-Signature': signature['signature']!,
          'X-Contract-Id': contractId,
          'X-File-Id': fileId,
          'X-Block-Id': blockId,
          'X-Block-Index': blockIndex.toString(),
        },
        body: blockData,
      );

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.log('Error uploading file block: $e');
      return false;
    }
  }

  /// Create a StorageOperation transaction for blockchain
  /// This is called after successful file upload
  /// The Storage Node creates this transaction with the contract as proof
  Map<String, dynamic> createStorageOperationData({
    required String contractId,
    required StorageContract contract,
    required List<String> fileIds,
    String? blockId,
    required int fileSize,
    required double fee,
  }) {
    if (fee != contract.totalFee) {
      throw ArgumentError('Fee must equal contract total fee');
    }

    return {
      'contractId': contractId,
      'contract': contract.toJson(),
      'fileIds': fileIds,
      'blockId': blockId,
      'fileSize': fileSize,
      'storageNodePubKey': contract.storageNodePublicKey,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };
  }

  /// Sign a StorageOperation as the App (cosignature)
  Future<String> createStorageOperationCosignature({
    required String contractId,
    required List<String> fileIds,
    String? blockId,
  }) async {
    // Create the message to sign for StorageOperation
    final message = 'StorageOperation|$contractId|${fileIds.join(',')}|${blockId ?? ''}';
    final signature = await _signer.signData(message);
    return signature;
  }
}
