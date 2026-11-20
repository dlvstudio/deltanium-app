// Live testnet checks of posting with attachments and of followers posts (Umbral PRE), through the app's own
// services: RegistrationService, PostPublisher, AttachmentDownloader, FollowingFeedService, FileCryptoService.
// Runs only with LIVE_TESTNET=1 and the native libraries (DELTANIUM_NATIVE_CRYPTO=1, DELTANIUM_UMBRAL=1); build with
//   --dart-define=NETWORK_ID=deltanium-test --dart-define=CENTRAL_API_BASE=https://testnet-api.deltanium.com/api
// Each run registers three throwaway QA identities on testnet and stores a few small files (free tier).
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/config/network.dart';
import 'package:deltanium_app/features/create_post/post_publisher.dart';
import 'package:deltanium_app/services/attachment_downloader.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/dltp/dltp_client_io.dart';
import 'package:deltanium_app/services/dltp/node_address.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/services/following_feed_service.dart';
import 'package:deltanium_app/services/registration_service.dart';
import 'package:deltanium_app/services/store_node_directory.dart';
import 'package:deltanium_app/services/user_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoHttps extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw StateError('HTTPS fallback used for ${request.url}: DLTP did not answer');
}

Uint8List _bytes(int n, int seed) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

String _sha(List<int> b) => crypto.sha256.convert(b).toString();

void main() {
  final enabled = Platform.environment['LIVE_TESTNET'] == '1' &&
      Platform.environment['DELTANIUM_NATIVE_CRYPTO'] == '1' &&
      Platform.environment['DELTANIUM_UMBRAL'] == '1';
  final run = DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(36);
  late RegisteredIdentity a, b, c;

  Future<void> actAs(RegisteredIdentity who) =>
      AuthService().setCurrentUser({'email': 'qa@example.test', 'mnemonic': who.mnemonic, 'publicKey': who.publicKey});

  Future<Map<String, dynamic>> contractOf(String fileId) async =>
      json.decode((await http.get(Uri.parse('${AppConstants.apiBaseUrl}/storedfile/contract/$fileId'))).body) as Map<String, dynamic>;

  setUpAll(() async {
    if (!enabled) return;
    expect(Network.name, 'deltanium-test');
    SharedPreferences.setMockInitialValues({});
    // Fixed QA identities (GitHub secrets QA_MNEMONIC_A/B/C) so runs do not create accounts; Central allows only a
    // few new accounts per network per day. QA_REGISTER=1 registers them once. Without the secrets: fresh accounts.
    Future<RegisteredIdentity> identity(String name) async {
      final phrase = Platform.environment['QA_MNEMONIC_$name']?.trim() ?? '';
      if (phrase.isEmpty) {
        return RegistrationService.register(email: 'qa-live-$run-${name.toLowerCase()}@example.test', fullName: 'QA live $name $run');
      }
      final pk = CryptoService.getPublicKeyHex(CryptoService.generateKeyPairFromMnemonic(phrase));
      if (Platform.environment['QA_REGISTER'] == '1') {
        try {
          await RegistrationService.register(
              email: 'qa-fixed-${name.toLowerCase()}@example.test', fullName: 'QA fixed $name', mnemonic: phrase);
        } on RegistrationException catch (e) {
          if (!e.message.contains('already registered')) rethrow;
        }
      }
      return RegisteredIdentity(phrase, pk);
    }

    a = await identity('A');
    b = await identity('B');
    c = await identity('C');
    // ignore: avoid_print
    print('identities A=${a.publicKey.substring(0, 10)} B=${b.publicKey.substring(0, 10)} C=${c.publicKey.substring(0, 10)}');
  });

  test('a private post with an image: stored on two Stores, each returns the same image over HTTPS and DLTP', () async {
    await actAs(a);
    final image = _bytes(300 * 1024, 1);
    final published = await PostPublisher(publicKey: a.publicKey, mnemonic: a.mnemonic, confirmStorage: (_) async => true)
        .publish(PostPublishRequest(
      text: 'QA live image post $run',
      media: [PostMediaInput(bytes: image, name: 'qa-$run.jpg', type: 'image', extension: 'jpg')],
      shareType: 'me',
      encryptedType: 'encrypted',
      recipients: [a.publicKey],
    ));
    expect(published.uploadedMedia, hasLength(1), reason: 'the attachment was uploaded');
    final fileId = published.uploadedMedia.single['fileId'] as String;

    final contract = await contractOf(fileId);
    final nodeIds = (contract['storeNodeIds'] as List).cast<String>();
    expect(nodeIds.length, AppConstants.replicationFactor, reason: 'N-of-M replicas of the attachment');
    final nodes = {for (final n in await StoreNodeDirectory.listNodes()) n['id'] as String: n};

    for (final id in nodeIds) {
      final https = nodes[id]!['httpsEndpoint'] as String;
      final r = await AttachmentDownloader.download(
          {'fileId': fileId, 'nodeEndpoint': https, 'userPublicKey': a.publicKey, 'userMnemonic': a.mnemonic});
      expect(r['success'], isTrue, reason: '$https: ${r['error']}');
      expect(_sha(r['imageData'] as Uint8List), _sha(image), reason: 'decrypted image from $https');
      // ignore: avoid_print
      print('OK  image from $https over HTTPS');
    }

    // The same downloads through the app's DLTP client, with no HTTPS fallback.
    NodeAddress.enabled = true;
    try {
      for (final id in nodeIds) {
        final n = StoreNodeDirectory.normalizeNode(Map<String, dynamic>.from(nodes[id]!));
        if ((n['tcpEndpoint'] ?? '').toString().isEmpty) continue;
        final r = await http.runWithClient(
          () => AttachmentDownloader.download(
              {'fileId': fileId, 'nodeEndpoint': n['endpoint'], 'userPublicKey': a.publicKey, 'userMnemonic': a.mnemonic}),
          () => DltpRoutingClient(inner: _NoHttps()),
        );
        expect(r['success'], isTrue, reason: '${n['tcpEndpoint']}: ${r['error']}');
        expect(_sha(r['imageData'] as Uint8List), _sha(image));
        // ignore: avoid_print
        print('OK  image from ${n['tcpEndpoint']} over DLTP');
      }
    } finally {
      NodeAddress.enabled = false;
      NodeAddress.clear();
    }

    // Another identity cannot read A's private image.
    final asC = await AttachmentDownloader.download(
        {'fileId': fileId, 'nodeEndpoint': nodes[nodeIds.first]!['httpsEndpoint'], 'userPublicKey': c.publicKey, 'userMnemonic': c.mnemonic});
    expect(asC['success'], isNot(true), reason: 'C must not decrypt A\'s private image');
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 6)));

  test('a large attachment (over the DLTP frame budget) still uploads from a DLTP-enabled app', () async {
    await actAs(a);
    final big = _bytes(12 * 1024 * 1024, 2);
    NodeAddress.enabled = true;
    late PostPublishResult published;
    try {
      // Nodes with HTTPS take bodies too large for one DLTP frame over HTTPS (the routing client decides).
      published = await http.runWithClient(
        () => PostPublisher(publicKey: a.publicKey, mnemonic: a.mnemonic, confirmStorage: (_) async => true).publish(
          PostPublishRequest(
            text: 'QA live large attachment $run',
            media: [PostMediaInput(bytes: big, name: 'qa-big-$run.bin', type: 'file', extension: 'bin')],
            shareType: 'me',
            encryptedType: 'encrypted',
            recipients: [a.publicKey],
          ),
        ),
        () => DltpRoutingClient(inner: IOClient()),
      );
    } finally {
      NodeAddress.enabled = false;
      NodeAddress.clear();
    }
    expect(published.uploadedMedia, hasLength(1));
    final fileId = published.uploadedMedia.single['fileId'] as String;
    final node = published.primaryNode;
    final r = await AttachmentDownloader.download(
        {'fileId': fileId, 'nodeEndpoint': node['httpsEndpoint'], 'userPublicKey': a.publicKey, 'userMnemonic': a.mnemonic});
    expect(r['success'], isTrue, reason: '${r['error']}');
    expect(_sha(r['imageData'] as Uint8List), _sha(big));
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 8)));

  test('a followers post (PRE): the follower reads it, a stranger cannot, nobody can take the follower\'s rekey', () async {
    final tag = 'followers:${DateTime.now().year}';
    await actAs(b);
    await UserDiscoveryService().followUser(a.publicKey); // B follows A (already true on later runs with fixed identities)

    await actAs(a);
    final text = 'QA live followers post $run';
    final published = await PostPublisher(publicKey: a.publicKey, mnemonic: a.mnemonic, confirmStorage: (_) async => true)
        .publish(PostPublishRequest(
      text: text,
      shareType: 'followers',
      encryptedType: 'encrypted',
      recipients: [a.publicKey],
      preTag: tag,
      rekeyFor: [a.publicKey, b.publicKey],
    ));
    expect(published.rekeys[b.publicKey], isTrue, reason: 'rekey A->B uploaded');

    // B: the post appears in the Following feed, decrypted through the rekey.
    await actAs(b);
    final feedB = await FollowingFeedService().getFollowingFeed();
    final mine = feedB.where((p) => p.fileId == published.fileId || p.textContent == text).toList();
    expect(mine, isNotEmpty, reason: 'B sees A\'s followers post');
    expect(mine.first.textContent, text);

    // C (not a follower): not in the feed, and Central has no rekey for C.
    await actAs(c);
    final feedC = await FollowingFeedService().getFollowingFeed();
    expect(feedC.where((p) => p.textContent == text), isEmpty);
    expect(
      await FileCryptoService.fetchRekeyFromCentral(
          followerPubKey: c.publicKey, followingPubKey: a.publicKey, policyTag: tag, mnemonic: c.mnemonic),
      isNull,
    );
    // C cannot fetch B's rekey by naming B: the proof of possession is signed with C's key.
    expect(
      await FileCryptoService.fetchRekeyFromCentral(
          followerPubKey: b.publicKey, followingPubKey: a.publicKey, policyTag: tag, mnemonic: c.mnemonic),
      isNull,
    );
    // B can.
    expect(
      await FileCryptoService.fetchRekeyFromCentral(
          followerPubKey: b.publicKey, followingPubKey: a.publicKey, policyTag: tag, mnemonic: b.mnemonic),
      isNotNull,
    );
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 6)));
}
