class RegisterRequest {
  final String email;
  final String fullName;
  final DateTime? dateOfBirth;
  final String bio;
  final String avatarUrl;

  RegisterRequest({
    required this.email,
    required this.fullName,
    this.dateOfBirth,
    this.bio = '',
    this.avatarUrl = '',
  });

  Map<String, dynamic> toJson() => {
    'email': email,
    'fullName': fullName,
    'dateOfBirth': dateOfBirth?.toIso8601String(),
    'bio': bio,
    'avatarUrl': avatarUrl,
  };
} 