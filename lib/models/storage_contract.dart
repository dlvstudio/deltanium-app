import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Storage contract model for Dart/Flutter
///
/// Represents a signed agreement between an App (user) and Storage Node for file storage.
/// Contract specifies terms (duration, size, fees) and must be signed by both parties.
/// Signing uses contract hash (SHA-256 of canonical JSON); [messageToSign] is deprecated.

class StorageContract {
  String contractId;
  String contractType; // "TimeFixed" or "OpenEnded"

  // Parties
  String appPublicKey;
  String storageNodePublicKey;

  // Terms
  int startDateUnix;
  int? endDateUnix; // null for OpenEnded
  int totalFileSize; // bytes
  double totalFee; // Deltanium
  /// Exact F10 string used in canonical JSON (from Store). Use this for V2 hash to match C#.
  String? totalFeeCanonical;
  List<String> fileIds;

  // Signatures and proof
  /// Hash of canonical contract (hex lowercase). This is what both parties sign.
  String contractHash;
  /// Deprecated: legacy message format; prefer signing [contractHash].
  String messageToSign;
  String appSignature;
  String storageNodeSignature;

  // Metadata
  int createdAtUnix;
  String status; // "Active", "Completed", "Cancelled", "Pending"

  StorageContract({
    required this.contractId,
    required this.contractType,
    required this.appPublicKey,
    required this.storageNodePublicKey,
    required this.startDateUnix,
    this.endDateUnix,
    required this.totalFileSize,
    required this.totalFee,
    this.totalFeeCanonical,
    required this.fileIds,
    this.contractHash = '',
    required this.messageToSign,
    required this.appSignature,
    required this.storageNodeSignature,
    required this.createdAtUnix,
    this.status = "Active",
  });

  /// Build canonical JSON for hashing (alphabetical keys, content only, no signatures).
  /// Matches Store/Blocker canonical format so hash is identical across App, Store, Blocker.
  /// [feeStringForHash]: use this exact string for totalFee when provided (e.g. from Store totalFeeCanonical).
  static String buildCanonicalContractJson({
    required String contractId,
    required String contractType,
    required String appPublicKey,
    required String storageNodePublicKey,
    required int startDateUnix,
    int? endDateUnix,
    required int totalFileSize,
    required double totalFee,
    String? feeStringForHash,
    required List<String> fileIds,
    required int createdAtUnix,
    required String status,
  }) {
    final sortedFileIds = List<String>.from(fileIds)..sort();
    final feeString = feeStringForHash ?? totalFee.toStringAsFixed(10);
    // Strict alphabetical key order to match C# SortedDictionary
    final map = <String, dynamic>{
      'appPublicKey': appPublicKey,
      'contractId': contractId,
      'contractType': contractType,
      'createdAtUnix': createdAtUnix,
      if (endDateUnix != null) 'endDateUnix': endDateUnix,
      'fileIds': sortedFileIds,
      'startDateUnix': startDateUnix,
      'status': status,
      'storageNodePublicKey': storageNodePublicKey,
      'totalFee': feeString,
      'totalFileSize': totalFileSize,
    };
    return jsonEncode(map);
  }

  /// Compute contract hash: SHA-256(utf8(canonicalJson)) as lowercase hex.
  /// Uses [totalFeeCanonical] when set so V2 hash matches Store/Blocker (C#).
  static String computeContractHash(StorageContract contract) {
    final canonical = buildCanonicalContractJson(
      contractId: contract.contractId,
      contractType: contract.contractType,
      appPublicKey: contract.appPublicKey,
      storageNodePublicKey: contract.storageNodePublicKey,
      startDateUnix: contract.startDateUnix,
      endDateUnix: contract.endDateUnix,
      totalFileSize: contract.totalFileSize,
      totalFee: contract.totalFee,
      feeStringForHash: contract.totalFeeCanonical,
      fileIds: contract.fileIds,
      createdAtUnix: contract.createdAtUnix,
      status: contract.status,
    );
    final bytes = utf8.encode(canonical);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Generate the message that both parties must sign (deprecated; use contractHash)
  static String generateMessageToSign({
    required String contractType,
    required int startDate,
    int? endDate,
    required String appPublicKey,
    required String storageNodePublicKey,
    required double totalFee,
    required int totalFileSize,
  }) {
    if (contractType == "TimeFixed") {
      if (endDate == null) {
        throw ArgumentError("TimeFixed contracts require endDate");
      }
      // 🆕 Format fee with toStringAsFixed(10) to match C# formatting (10 decimal places)
      // This ensures signature verification works correctly when C# verifies the same message
      return "TimeFixed|$startDate|$endDate|$appPublicKey|$storageNodePublicKey|${totalFee.toStringAsFixed(10)}|$totalFileSize";
    } else if (contractType == "OpenEnded") {
      // 🆕 Format fee with toStringAsFixed(10) to match C# formatting (10 decimal places)
      return "OpenEnded|$startDate|$appPublicKey|$storageNodePublicKey|${totalFee.toStringAsFixed(10)}|$totalFileSize";
    } else {
      throw ArgumentError("Unknown contract type: $contractType");
    }
  }

  /// Check if contract is currently valid
  bool isValidNow() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    if (status != "Active") return false;
    if (now < startDateUnix) return false;
    
    if (contractType == "TimeFixed" && endDateUnix != null && now > endDateUnix!) {
      return false;
    }
    
    if (contractType == "OpenEnded" && now > startDateUnix + (365 * 24 * 60 * 60)) {
      return false;
    }
    
    return true;
  }

  /// Check if file ID is covered by contract
  bool coversFileId(String fileId) => fileIds.contains(fileId);

  /// Check if file size is within limit
  bool coversFileSize(int fileSizeBytes) => fileSizeBytes <= totalFileSize;

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'contractId': contractId,
    'contractType': contractType,
    'appPublicKey': appPublicKey,
    'storageNodePublicKey': storageNodePublicKey,
    'startDateUnix': startDateUnix,
    'endDateUnix': endDateUnix,
    'totalFileSize': totalFileSize,
    'totalFee': totalFee,
    if (totalFeeCanonical != null) 'totalFeeCanonical': totalFeeCanonical,
    'fileIds': fileIds,
    'contractHash': contractHash,
    'messageToSign': messageToSign,
    'appSignature': appSignature,
    'storageNodeSignature': storageNodeSignature,
    'createdAtUnix': createdAtUnix,
    'status': status,
  };

  /// Create from JSON
  factory StorageContract.fromJson(Map<String, dynamic> json) => StorageContract(
    contractId: json['contractId'] as String? ?? '',
    contractType: json['contractType'] as String? ?? '',
    appPublicKey: json['appPublicKey'] as String? ?? '',
    storageNodePublicKey: json['storageNodePublicKey'] as String? ?? '',
    startDateUnix: json['startDateUnix'] as int? ?? 0,
    endDateUnix: json['endDateUnix'] as int?,
    totalFileSize: json['totalFileSize'] as int? ?? 0,
    totalFee: (json['totalFee'] as num?)?.toDouble() ?? 0.0,
    totalFeeCanonical: json['totalFeeCanonical'] as String?,
    fileIds: (json['fileIds'] as List<dynamic>?)?.cast<String>() ?? [],
    contractHash: json['contractHash'] as String? ?? '',
    messageToSign: json['messageToSign'] as String? ?? '',
    appSignature: json['appSignature'] as String? ?? '',
    storageNodeSignature: json['storageNodeSignature'] as String? ?? '',
    createdAtUnix: json['createdAtUnix'] as int? ?? 0,
    status: json['status'] as String? ?? 'Active',
  );
}
