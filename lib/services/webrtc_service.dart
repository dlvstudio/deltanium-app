import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/ecies_service.dart';
import 'package:deltanium_app/services/file_crypto_service.dart';
import 'package:deltanium_app/services/auth_service.dart';
import 'package:deltanium_app/services/app_logger.dart';

/// P2P connection state
enum P2PState {
  disconnected,
  connecting,
  connected,
  failed,
}

/// WebRTC P2P Service for direct peer-to-peer chat messaging.
/// Uses WebRTC DataChannel for direct communication when both users are online.
/// Signaling is done through the Central API.
class WebRTCService {
  static final String _apiBase = AppConstants.apiBaseUrl;

  // WebRTC objects
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;

  // State
  P2PState _state = P2PState.disconnected;
  P2PState get state => _state;

  // Callbacks
  Function(P2PState)? onStateChanged;
  Function(Map<String, dynamic>)? onMessageReceived;

  // Connection info
  final String _myPubKey;
  final String _myMnemonic;
  final String _remotePubKey;
  bool _isInitiator = false;

  // Signaling poll timer
  Timer? _signalingTimer;
  bool _isPollingSignaling = false;

  // ICE candidates buffer (collected before remote description is set)
  final List<RTCIceCandidate> _pendingIceCandidates = [];
  bool _remoteDescriptionSet = false;

  // STUN servers for NAT traversal
  static const Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  WebRTCService({
    required String myPubKey,
    required String myMnemonic,
    required String remotePubKey,
  })  : _myPubKey = myPubKey,
        _myMnemonic = myMnemonic,
        _remotePubKey = remotePubKey;

  // ========== PUBLIC API ==========

  /// Initiate P2P connection (caller/initiator side)
  Future<void> connect() async {
    if (_state == P2PState.connecting || _state == P2PState.connected) return;

    _isInitiator = true;
    _setState(P2PState.connecting);
    AppLogger.log('WebRTC: Initiating P2P connection to $_remotePubKey');

    try {
      await _createPeerConnection();
      _createDataChannel();

      // Create and send offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      AppLogger.log('WebRTC: Created offer, sending via signaling');

      await _sendSignaling('offer', jsonEncode({
        'sdp': offer.sdp,
        'type': offer.type,
      }));

      // Start polling for answer and ICE candidates
      _startSignalingPoll();
    } catch (e) {
      AppLogger.log('WebRTC: connect error: $e');
      _setState(P2PState.failed);
    }
  }

  /// Start listening for incoming P2P connections (callee side)
  Future<void> listen() async {
    if (_state == P2PState.connecting || _state == P2PState.connected) return;

    _isInitiator = false;
    _setState(P2PState.connecting);
    AppLogger.log('WebRTC: Listening for P2P connection from $_remotePubKey');

    // Start polling for offers
    _startSignalingPoll();
  }

  /// Send an encrypted message through P2P DataChannel
  Future<bool> sendMessage(Map<String, dynamic> messageData) async {
    if (_state != P2PState.connected || _dataChannel == null) {
      AppLogger.log('WebRTC: Cannot send - not connected (state=$_state)');
      return false;
    }

    try {
      // 1. Generate random symmetric key K (32 bytes)
      final K = Uint8List.fromList(
        List.generate(32, (_) => Random.secure().nextInt(256)),
      );

      // 2. Encrypt message payload with K (AES)
      final payload = utf8.encode(jsonEncode(messageData));
      final encryptedPayload = await FileCryptoService.testEncryptData(
        Uint8List.fromList(payload),
        K,
      );

      // 3. Encrypt K with recipient's public key (ECIES)
      final encryptedKey = await EciesService.encryptWithPublicKey(
        data: K,
        publicKeyHex: _remotePubKey,
      );

      // 4. Build P2P message envelope
      final envelope = jsonEncode({
        'type': 'chat_message',
        'encryptedKey': base64Encode(encryptedKey),
        'payload': base64Encode(encryptedPayload),
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      // 5. Send via DataChannel
      _dataChannel!.send(RTCDataChannelMessage(envelope));
      AppLogger.log('WebRTC: Message sent via P2P (${envelope.length} bytes)');
      return true;
    } catch (e) {
      AppLogger.log('WebRTC: sendMessage error: $e');
      return false;
    }
  }

  /// Disconnect and clean up
  Future<void> disconnect() async {
    AppLogger.log('WebRTC: Disconnecting');
    _signalingTimer?.cancel();
    _signalingTimer = null;

    _dataChannel?.close();
    _dataChannel = null;

    await _peerConnection?.close();
    _peerConnection = null;

    _pendingIceCandidates.clear();
    _remoteDescriptionSet = false;
    _isPollingSignaling = false;

    _setState(P2PState.disconnected);
  }

  void dispose() {
    disconnect();
    onStateChanged = null;
    onMessageReceived = null;
  }

  // ========== PEER CONNECTION ==========

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_rtcConfig);

    _peerConnection!.onIceCandidate = (candidate) {
      AppLogger.log('WebRTC: New ICE candidate: ${candidate.candidate?.substring(0, min(50, candidate.candidate?.length ?? 0))}...');
      _sendSignaling('ice', jsonEncode({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }));
    };

    _peerConnection!.onIceConnectionState = (state) {
      AppLogger.log('WebRTC: ICE connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        _setState(P2PState.connected);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _setState(P2PState.failed);
      }
    };

    _peerConnection!.onDataChannel = (channel) {
      AppLogger.log('WebRTC: Received data channel: ${channel.label}');
      _dataChannel = channel;
      _setupDataChannel(channel);
    };

    AppLogger.log('WebRTC: PeerConnection created');
  }

  void _createDataChannel() {
    final channelInit = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = 3;

    _peerConnection!.createDataChannel('chat', channelInit).then((channel) {
      _dataChannel = channel;
      _setupDataChannel(channel);
      AppLogger.log('WebRTC: DataChannel created: ${channel.label}');
    });
  }

  void _setupDataChannel(RTCDataChannel channel) {
    channel.onDataChannelState = (state) {
      AppLogger.log('WebRTC: DataChannel state: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _setState(P2PState.connected);
        // Stop signaling poll once connected
        _signalingTimer?.cancel();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _setState(P2PState.disconnected);
      }
    };

    channel.onMessage = (message) {
      _handleIncomingMessage(message);
    };
  }

  // ========== MESSAGE HANDLING ==========

  Future<void> _handleIncomingMessage(RTCDataChannelMessage message) async {
    try {
      final envelope = jsonDecode(message.text) as Map<String, dynamic>;
      final type = envelope['type'] as String?;

      if (type == 'chat_message') {
        // Decrypt the message
        final encryptedKeyBytes = base64Decode(envelope['encryptedKey'] as String);
        final encryptedPayloadBytes = base64Decode(envelope['payload'] as String);

        // 1. Decrypt symmetric key K with my private key (ECIES)
        final K = await FileCryptoService.decryptSymmetricKeyWithPrivateKey(
          Uint8List.fromList(encryptedKeyBytes),
          _myMnemonic,
        );

        // 2. Decrypt payload with K (AES)
        final decryptedPayload = await FileCryptoService.decryptRawBlockWithKey(
          Uint8List.fromList(encryptedPayloadBytes),
          K,
        );

        if (decryptedPayload != null) {
          final messageData = jsonDecode(utf8.decode(decryptedPayload)) as Map<String, dynamic>;
          AppLogger.log('WebRTC: Received P2P message: ${messageData['text']?.toString().substring(0, min(30, (messageData['text']?.toString().length ?? 0)))}...');
          onMessageReceived?.call(messageData);
        } else {
          AppLogger.log('WebRTC: Failed to decrypt P2P message');
        }
      }
    } catch (e) {
      AppLogger.log('WebRTC: handleIncomingMessage error: $e');
    }
  }

  // ========== SIGNALING ==========

  void _startSignalingPoll() {
    _signalingTimer?.cancel();
    _signalingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollSignaling();
    });
    // Also poll immediately
    _pollSignaling();
  }

  Future<void> _pollSignaling() async {
    if (_isPollingSignaling) return;
    _isPollingSignaling = true;

    try {
      final messages = await _getSignalingMessages();
      for (final msg in messages) {
        await _handleSignalingMessage(msg);
      }
    } catch (e) {
      AppLogger.log('WebRTC: pollSignaling error: $e');
    } finally {
      _isPollingSignaling = false;
    }
  }

  Future<void> _handleSignalingMessage(Map<String, dynamic> msg) async {
    final type = msg['type'] ?? msg['Type'] ?? '';
    final payload = msg['payload'] ?? msg['Payload'] ?? '';
    final fromPubKey = msg['fromPubKey'] ?? msg['FromPubKey'] ?? '';

    // Only process messages from our peer
    if (CryptoService.normalizePublicKey(fromPubKey) !=
        CryptoService.normalizePublicKey(_remotePubKey)) {
      return;
    }

    AppLogger.log('WebRTC: Received signaling: type=$type from=$fromPubKey');

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;

      switch (type) {
        case 'offer':
          await _handleOffer(data);
          break;
        case 'answer':
          await _handleAnswer(data);
          break;
        case 'ice':
          await _handleIceCandidate(data);
          break;
      }
    } catch (e) {
      AppLogger.log('WebRTC: handleSignalingMessage error: $e');
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> data) async {
    if (_isInitiator) {
      AppLogger.log('WebRTC: Ignoring offer (I am initiator)');
      return;
    }

    AppLogger.log('WebRTC: Processing offer');

    await _createPeerConnection();

    final offer = RTCSessionDescription(data['sdp'], data['type']);
    await _peerConnection!.setRemoteDescription(offer);
    _remoteDescriptionSet = true;

    // Process any buffered ICE candidates
    for (final candidate in _pendingIceCandidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    _pendingIceCandidates.clear();

    // Create and send answer
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await _sendSignaling('answer', jsonEncode({
      'sdp': answer.sdp,
      'type': answer.type,
    }));

    AppLogger.log('WebRTC: Sent answer');
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    if (!_isInitiator) {
      AppLogger.log('WebRTC: Ignoring answer (I am not initiator)');
      return;
    }

    AppLogger.log('WebRTC: Processing answer');

    final answer = RTCSessionDescription(data['sdp'], data['type']);
    await _peerConnection!.setRemoteDescription(answer);
    _remoteDescriptionSet = true;

    // Process any buffered ICE candidates
    for (final candidate in _pendingIceCandidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    _pendingIceCandidates.clear();
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    final candidate = RTCIceCandidate(
      data['candidate'],
      data['sdpMid'],
      data['sdpMLineIndex'],
    );

    if (_remoteDescriptionSet && _peerConnection != null) {
      await _peerConnection!.addCandidate(candidate);
    } else {
      // Buffer until remote description is set
      _pendingIceCandidates.add(candidate);
    }
  }

  // ========== API HELPERS ==========

  Future<Map<String, String>> _signedHeaders({
    required String method,
    required String path,
    String? body,
  }) async {
    final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
    var bodyHash = '';
    if (method == 'POST' && body != null) {
      final bytes = utf8.encode(body);
      bodyHash = sha256.convert(bytes).toString();
    }
    final dataToSign = '$method$path$timestamp$bodyHash';
    final signature = await CryptoService.sign(dataToSign, _myMnemonic);
    return {
      'Content-Type': 'application/json',
      'X-User-PubKey': CryptoService.normalizePublicKey(_myPubKey),
      'X-Timestamp': timestamp,
      'X-Signature': signature,
    };
  }

  Future<void> _sendSignaling(String type, String payload) async {
    try {
      final bodyJson = jsonEncode({
        'toPubKey': _remotePubKey,
        'payload': payload,
      });
      final path = '/chat/signaling/$type';
      final headers = await _signedHeaders(
        method: 'POST',
        path: '/api$path',
        body: bodyJson,
      );

      final resp = await http.post(
        Uri.parse('$_apiBase$path'),
        headers: headers,
        body: bodyJson,
      );

      if (resp.statusCode == 200) {
        AppLogger.log('WebRTC: Signaling $type sent successfully');
      } else {
        AppLogger.log('WebRTC: Signaling $type failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      AppLogger.log('WebRTC: sendSignaling error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _getSignalingMessages() async {
    try {
      const path = '/chat/signaling/poll';
      final headers = await _signedHeaders(
        method: 'GET',
        path: '/api$path',
      );

      final resp = await http.get(
        Uri.parse('$_apiBase$path'),
        headers: headers,
      );

      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        return list.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      AppLogger.log('WebRTC: getSignalingMessages error: $e');
      return [];
    }
  }

  // ========== HELPERS ==========

  void _setState(P2PState newState) {
    if (_state == newState) return;
    _state = newState;
    AppLogger.log('WebRTC: State changed to $newState');
    onStateChanged?.call(newState);
  }
}
