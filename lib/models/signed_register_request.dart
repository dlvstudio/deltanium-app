class SignedRegisterRequest {
  final String publicKey;
  final String email;
  final String fullName;
  final DateTime? dateOfBirth;
  final String bio;
  final String avatarUrl;
  final String signature;
  final int timestamp; // Unix timestamp for signature validation

  SignedRegisterRequest({
    required this.publicKey,
    required this.email,
    required this.fullName,
    this.dateOfBirth,
    this.bio = '',
    this.avatarUrl = '',
    required this.signature,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'publicKey': publicKey,
    'email': email,
    'fullName': fullName,
    'dateOfBirth': dateOfBirth?.toIso8601String(),
    'bio': bio,
    'avatarUrl': avatarUrl,
    'signature': signature,
    'timestamp': timestamp,
  };

  // Helper method to get the data that needs to be signed (now includes timestamp)
  String getSignableData() {
    String? dob;
    if (dateOfBirth != null) {
      final y = dateOfBirth!.year.toString().padLeft(4, '0');
      final m = dateOfBirth!.month.toString().padLeft(2, '0');
      final d = dateOfBirth!.day.toString().padLeft(2, '0');
      dob = '$y-$m-$d';
    }
    return '$email:$fullName:${dob ?? ''}:$timestamp';
  }
} 