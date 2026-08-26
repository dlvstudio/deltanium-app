import 'package:flutter/material.dart';

class StoredFile {
  final String id;
  final String fileId;
  final String ownerPublicKey;
  final String storeNodeId;
  final DateTime storedAt;
  final bool isActive;
  final String? fileHash;
  final int fileSize;
  final String? fileName;
  final String? fileType;
  final String? downloadUrl;
  final String? nodeEndpoint;

  StoredFile({
    required this.id,
    required this.fileId,
    required this.ownerPublicKey,
    required this.storeNodeId,
    required this.storedAt,
    this.isActive = true,
    this.fileHash,
    required this.fileSize,
    this.fileName,
    this.fileType,
    this.downloadUrl,
    this.nodeEndpoint,
  });

  factory StoredFile.fromJson(Map<String, dynamic> json, {String? nodeEndpoint}) {
    return StoredFile(
      id: json['id'] ?? '',
      fileId: json['fileId'] ?? '',
      ownerPublicKey: json['ownerPublicKey'] ?? '',
      storeNodeId: json['storeNodeId'] ?? '',
      storedAt: json['storedAt'] != null 
          ? DateTime.parse(json['storedAt']) 
          : DateTime.now(),
      isActive: json['isActive'] ?? true,
      fileHash: json['fileHash'],
      fileSize: json['fileSize'] != null ? int.parse(json['fileSize'].toString()) : 0,
      fileName: json['fileName'],
      fileType: json['fileType'],
      downloadUrl: nodeEndpoint != null 
          ? '$nodeEndpoint/api/file/download/${json['fileId']}' 
          : null,
      nodeEndpoint: nodeEndpoint,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileId': fileId,
      'ownerPublicKey': ownerPublicKey,
      'storeNodeId': storeNodeId,
      'storedAt': storedAt.toIso8601String(),
      'isActive': isActive,
      'fileHash': fileHash,
      'fileSize': fileSize,
      'fileName': fileName,
      'fileType': fileType,
    };
  }

  String get fileSizeFormatted {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  IconData get fileIcon {
    final ext = fileName?.split('.').last.toLowerCase() ?? '';
    
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      return Icons.image;
    } else if (['pdf'].contains(ext)) {
      return Icons.picture_as_pdf;
    } else if (['doc', 'docx'].contains(ext)) {
      return Icons.description;
    } else if (['xls', 'xlsx'].contains(ext)) {
      return Icons.table_chart;
    } else if (['mp3', 'wav', 'ogg'].contains(ext)) {
      return Icons.audio_file;
    } else if (['mp4', 'mov', 'avi', 'webm'].contains(ext)) {
      return Icons.video_file;
    } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return Icons.folder_zip;
    } else if (['txt', 'csv'].contains(ext)) {
      return Icons.text_snippet;
    }
    
    return Icons.insert_drive_file;
  }

  Color get fileIconColor {
    final ext = fileName?.split('.').last.toLowerCase() ?? '';
    
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      return Colors.blue;
    } else if (['pdf'].contains(ext)) {
      return Colors.red;
    } else if (['doc', 'docx'].contains(ext)) {
      return Colors.blue.shade800;
    } else if (['xls', 'xlsx'].contains(ext)) {
      return Colors.green.shade800;
    } else if (['mp3', 'wav', 'ogg'].contains(ext)) {
      return Colors.purple;
    } else if (['mp4', 'mov', 'avi', 'webm'].contains(ext)) {
      return Colors.red.shade700;
    } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return Colors.amber.shade700;
    } else if (['txt', 'csv'].contains(ext)) {
      return Colors.blueGrey;
    }
    
    return Colors.grey;
  }
} 