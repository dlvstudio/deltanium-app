class UserProfile {
  final String? id;
  final String? email;
  final String publicKey;
  final String? fullName;
  final String? bio;
  final String? avatarUrl;
  final String? dateOfBirth;
  final bool isVerified;
  final String? walletAddress;
  final List<String>? following;
  final List<String>? followers;

  UserProfile({
    this.id,
    this.email,
    required this.publicKey,
    this.fullName,
    this.bio,
    this.avatarUrl,
    this.dateOfBirth,
    this.isVerified = false,
    this.walletAddress,
    this.following,
    this.followers,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      email: json['email'],
      publicKey: json['publicKey'],
      fullName: json['fullName'],
      bio: json['bio'],
      avatarUrl: json['avatarUrl'],
      dateOfBirth: json['dateOfBirth'],
      isVerified: json['isVerified'] ?? false,
      walletAddress: json['walletAddress'],
      following: json['following'] != null 
          ? List<String>.from(json['following']) 
          : null,
      followers: json['followers'] != null 
          ? List<String>.from(json['followers']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'publicKey': publicKey,
      'fullName': fullName,
      'bio': bio,
      'avatarUrl': avatarUrl,
      'dateOfBirth': dateOfBirth,
      'isVerified': isVerified,
      'walletAddress': walletAddress,
      'following': following,
      'followers': followers,
    };
  }

  UserProfile copyWith({
    String? id,
    String? email,
    String? publicKey,
    String? fullName,
    String? bio,
    String? avatarUrl,
    String? dateOfBirth,
    bool? isVerified,
    String? walletAddress,
    List<String>? following,
    List<String>? followers,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      publicKey: publicKey ?? this.publicKey,
      fullName: fullName ?? this.fullName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      isVerified: isVerified ?? this.isVerified,
      walletAddress: walletAddress ?? this.walletAddress,
      following: following ?? this.following,
      followers: followers ?? this.followers,
    );
  }
} 