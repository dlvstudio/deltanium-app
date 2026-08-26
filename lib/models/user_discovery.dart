/// Model for user discovery and search functionality
class DiscoveredUser {
  final String publicKey;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final DateTime joinDate;
  final int postsCount;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;
  final DateTime? lastActive;

  DiscoveredUser({
    required this.publicKey,
    this.displayName,
    this.bio,
    this.avatarUrl,
    required this.joinDate,
    this.postsCount = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.isFollowing = false,
    this.lastActive,
  });

  factory DiscoveredUser.fromJson(Map<String, dynamic> json) {
    return DiscoveredUser(
      publicKey: json['publicKey'] ?? '',
      displayName: json['displayName'],
      bio: json['bio'],
      avatarUrl: json['avatarUrl'],
      joinDate: DateTime.tryParse(json['joinDate'] ?? '') ?? DateTime.now(),
      postsCount: json['postsCount'] ?? 0,
      followersCount: json['followersCount'] ?? 0,
      followingCount: json['followingCount'] ?? 0,
      isFollowing: json['isFollowing'] ?? false,
      lastActive: json['lastActive'] != null 
          ? DateTime.tryParse(json['lastActive']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'publicKey': publicKey,
      'displayName': displayName,
      'bio': bio,
      'avatarUrl': avatarUrl,
      'joinDate': joinDate.toIso8601String(),
      'postsCount': postsCount,
      'followersCount': followersCount,
      'followingCount': followingCount,
      'isFollowing': isFollowing,
      'lastActive': lastActive?.toIso8601String(),
    };
  }

  String get shortPublicKey {
    return '${publicKey.substring(0, 6)}...${publicKey.substring(publicKey.length - 4)}';
  }

  String get formattedJoinDate {
    final now = DateTime.now();
    final difference = now.difference(joinDate);
    
    if (difference.inDays < 1) {
      return 'Joined today';
    } else if (difference.inDays < 7) {
      return 'Joined ${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return 'Joined ${weeks} week${weeks > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return 'Joined ${months} month${months > 1 ? 's' : ''} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return 'Joined ${years} year${years > 1 ? 's' : ''} ago';
    }
  }

  String get lastActiveFormatted {
    if (lastActive == null) return 'Active recently';
    
    final now = DateTime.now();
    final difference = now.difference(lastActive!);
    
    if (difference.inMinutes < 1) {
      return 'Active now';
    } else if (difference.inMinutes < 60) {
      return 'Active ${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return 'Active ${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return 'Active ${difference.inDays}d ago';
    } else {
      return 'Active ${(difference.inDays / 7).floor()}w ago';
    }
  }

  DiscoveredUser copyWith({
    String? publicKey,
    String? displayName,
    String? bio,
    String? avatarUrl,
    DateTime? joinDate,
    int? postsCount,
    int? followersCount,
    int? followingCount,
    bool? isFollowing,
    DateTime? lastActive,
  }) {
    return DiscoveredUser(
      publicKey: publicKey ?? this.publicKey,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      joinDate: joinDate ?? this.joinDate,
      postsCount: postsCount ?? this.postsCount,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      isFollowing: isFollowing ?? this.isFollowing,
      lastActive: lastActive ?? this.lastActive,
    );
  }
} 