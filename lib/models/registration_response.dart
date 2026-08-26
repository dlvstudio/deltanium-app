class RegistrationResponse {
  final String id;
  final String mnemonic;
  final String publicKey;
  final String email;
  final String fullName;
  final DateTime? dateOfBirth;
  final String bio;
  final String avatarUrl;

  RegistrationResponse({
    required this.id,
    required this.mnemonic,
    required this.publicKey,
    required this.email,
    required this.fullName,
    this.dateOfBirth,
    this.bio = '',
    this.avatarUrl = '',
  });

  factory RegistrationResponse.fromJson(Map<String, dynamic> json) {
    return RegistrationResponse(
      id: json['id'] as String,
      mnemonic: json['mnemonic'] as String,
      publicKey: json['publicKey'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String,
      dateOfBirth: json['dateOfBirth'] != null 
          ? DateTime.parse(json['dateOfBirth'] as String)
          : null,
      bio: json['bio'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'mnemonic': mnemonic,
    'publicKey': publicKey,
    'email': email,
    'fullName': fullName,
    'dateOfBirth': dateOfBirth?.toIso8601String(),
    'bio': bio,
    'avatarUrl': avatarUrl,
  };
} 