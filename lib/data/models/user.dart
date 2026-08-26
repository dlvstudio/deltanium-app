import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String username;
  final String displayName;
  final String email;
  final String profileImageUrl;
  final String publicKey;
  final String bio;
  final bool isVerified;
  final DateTime createdAt;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final List<String> interests;

  const User({
    required this.id,
    required this.username,
    required this.displayName,
    required this.email,
    this.profileImageUrl = '',
    required this.publicKey,
    this.bio = '',
    this.isVerified = false,
    required this.createdAt,
    this.followersCount = 0,
    this.followingCount = 0,
    this.postsCount = 0,
    this.interests = const [],
  });

  User copyWith({
    String? id,
    String? username,
    String? displayName,
    String? email,
    String? profileImageUrl,
    String? publicKey,
    String? bio,
    bool? isVerified,
    DateTime? createdAt,
    int? followersCount,
    int? followingCount,
    int? postsCount,
    List<String>? interests,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      publicKey: publicKey ?? this.publicKey,
      bio: bio ?? this.bio,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      postsCount: postsCount ?? this.postsCount,
      interests: interests ?? this.interests,
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      email: json['email'] as String,
      profileImageUrl: json['profileImageUrl'] as String? ?? '',
      publicKey: json['publicKey'] as String,
      bio: json['bio'] as String? ?? '',
      isVerified: json['isVerified'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      followersCount: json['followersCount'] as int? ?? 0,
      followingCount: json['followingCount'] as int? ?? 0,
      postsCount: json['postsCount'] as int? ?? 0,
      interests: (json['interests'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'displayName': displayName,
      'email': email,
      'profileImageUrl': profileImageUrl,
      'publicKey': publicKey,
      'bio': bio,
      'isVerified': isVerified,
      'createdAt': createdAt.toIso8601String(),
      'followersCount': followersCount,
      'followingCount': followingCount,
      'postsCount': postsCount,
      'interests': interests,
    };
  }

  @override
  List<Object?> get props => [
        id,
        username,
        displayName,
        email,
        profileImageUrl,
        publicKey,
        bio,
        isVerified,
        createdAt,
        followersCount,
        followingCount,
        postsCount,
        interests,
      ];

  // User representation for blockchain
  Map<String, dynamic> toBlockchainData() {
    return {
      'id': id,
      'username': username,
      'publicKey': publicKey,
      'createdAt': createdAt.toIso8601String(),
    };
  }
} 