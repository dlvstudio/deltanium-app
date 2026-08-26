class Post {
  final String id;
  final String userId;
  final String content;
  final List<String> mediaUrls;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final String? blockchainId;
  final String? signature;
  final List<String> tags;
  final PostPrivacy privacy;
  final List<String> sharedWithUserIds;
  final PostType type;
  final int version;

  Post({
    required this.id,
    required this.userId,
    required this.content,
    this.mediaUrls = const [],
    required this.createdAt,
    this.updatedAt,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
    this.blockchainId,
    this.signature,
    this.tags = const [],
    this.privacy = PostPrivacy.public,
    this.sharedWithUserIds = const [],
    this.type = PostType.text,
    this.version = 1,
  });

  Post copyWith({
    String? id,
    String? userId,
    String? content,
    List<String>? mediaUrls,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? likesCount,
    int? commentsCount,
    int? sharesCount,
    String? blockchainId,
    String? signature,
    List<String>? tags,
    PostPrivacy? privacy,
    List<String>? sharedWithUserIds,
    PostType? type,
    int? version,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      sharesCount: sharesCount ?? this.sharesCount,
      blockchainId: blockchainId ?? this.blockchainId,
      signature: signature ?? this.signature,
      tags: tags ?? this.tags,
      privacy: privacy ?? this.privacy,
      sharedWithUserIds: sharedWithUserIds ?? this.sharedWithUserIds,
      type: type ?? this.type,
      version: version ?? this.version,
    );
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String,
      userId: json['userId'] as String,
      content: json['content'] as String,
      mediaUrls: (json['mediaUrls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
      likesCount: json['likesCount'] as int? ?? 0,
      commentsCount: json['commentsCount'] as int? ?? 0,
      sharesCount: json['sharesCount'] as int? ?? 0,
      blockchainId: json['blockchainId'] as String?,
      signature: json['signature'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      privacy: PostPrivacy.values.firstWhere(
        (e) => e.name == (json['privacy'] as String),
        orElse: () => PostPrivacy.public,
      ),
      sharedWithUserIds: (json['sharedWithUserIds'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      type: PostType.values.firstWhere(
        (e) => e.name == (json['type'] as String),
        orElse: () => PostType.text,
      ),
      version: json['version'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'content': content,
      'mediaUrls': mediaUrls,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'likesCount': likesCount,
      'commentsCount': commentsCount,
      'sharesCount': sharesCount,
      'blockchainId': blockchainId,
      'signature': signature,
      'tags': tags,
      'privacy': privacy.name,
      'sharedWithUserIds': sharedWithUserIds,
      'type': type.name,
      'version': version,
    };
  }

  // Generate content for blockchain
  Map<String, dynamic> toBlockchainData() {
    return {
      'id': id,
      'userId': userId,
      'contentHash': _generateContentHash(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'privacy': privacy.name,
      'version': version,
    };
  }

  String _generateContentHash() {
    // In a real implementation, this would use crypto library to generate a hash
    // of the content and media URLs
    return 'hash_of_$content';
  }
}

enum PostPrivacy {
  public,
  followers,
  private,
  specificUsers
}

enum PostType {
  text,
  image,
  video,
  article,
  link
} 