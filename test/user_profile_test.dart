import 'package:deltanium_app/models/user_profile.dart';
import 'package:deltanium_app/models/register_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile', () {
    test('fromJson parses core fields and lists', () {
      final profile = UserProfile.fromJson({
        'id': 'u1',
        'email': 'a@b.com',
        'publicKey': '02abc',
        'fullName': 'Ada',
        'bio': 'hi',
        'avatarUrl': 'https://x/y.png',
        'isVerified': true,
        'following': ['pk1'],
        'followers': ['pk2', 'pk3'],
      });

      expect(profile.id, 'u1');
      expect(profile.publicKey, '02abc');
      expect(profile.fullName, 'Ada');
      expect(profile.isVerified, isTrue);
      expect(profile.following, ['pk1']);
      expect(profile.followers, ['pk2', 'pk3']);
    });

    test('fromJson defaults isVerified and null lists', () {
      final profile = UserProfile.fromJson({
        'publicKey': '02xyz',
      });

      expect(profile.isVerified, isFalse);
      expect(profile.following, isNull);
      expect(profile.followers, isNull);
    });

    test('toJson round-trips', () {
      final original = UserProfile(
        id: '1',
        publicKey: '02aa',
        fullName: 'Bob',
        following: const ['x'],
      );

      final again = UserProfile.fromJson(original.toJson());
      expect(again.id, original.id);
      expect(again.publicKey, original.publicKey);
      expect(again.fullName, original.fullName);
      expect(again.following, original.following);
    });
  });

  group('RegisterRequest', () {
    test('toJson includes email and fullName', () {
      final req = RegisterRequest(
        email: 't@example.com',
        fullName: 'Test User',
        bio: 'bio',
        avatarUrl: 'url',
        dateOfBirth: DateTime.utc(1990, 1, 2),
      );

      final json = req.toJson();
      expect(json['email'], 't@example.com');
      expect(json['fullName'], 'Test User');
      expect(json['bio'], 'bio');
      expect(json['dateOfBirth'], '1990-01-02T00:00:00.000Z');
    });
  });
}
