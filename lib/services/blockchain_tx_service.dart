import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:uuid/uuid.dart';

class BlockchainTxService {
  static Future<bool> submitTx({
    required String type,
    required String from,
    String? to,
    Map<String, dynamic>? data,
    num fee = 0,
    required String mnemonic,
  }) async {
    try {
      final txId = const Uuid().v4().replaceAll('-', '');
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
      final payloadToSign = jsonEncode({
        'id': txId,
        'type': type,
        'from': from,
        'to': to,
        'data': data ?? {},
        'timestamp': timestamp,
        'fee': fee.toStringAsFixed(10),
      });

      final signature = await CryptoService.sign(payloadToSign, mnemonic);
      final txBody = jsonEncode({
        'id': txId,
        'type': type,
        'from': from,
        'to': to,
        'data': data ?? {},
        'timestamp': timestamp,
        'fee': fee.toStringAsFixed(10),
        'signature': signature,
        'signPayload': payloadToSign,
      });

      final blockerEndpoint = await _selectBlockerEndpoint();
      if (blockerEndpoint == null) {
        AppLogger.log('BlockchainTxService: no blocker endpoint available');
        return false;
      }

      AppLogger.log('BlockchainTxService: sending tx to $blockerEndpoint/api/tx/submit');
      AppLogger.log('BlockchainTxService: txId=$txId type=$type from=${from.substring(0, 10)}... fee=$fee');

      final resp = await http.post(
        Uri.parse('$blockerEndpoint/api/tx/submit'),
        headers: {'Content-Type': 'application/json'},
        body: txBody,
      );

      if (resp.statusCode == 200) {
        AppLogger.log('BlockchainTxService: submitted tx type=$type');
        return true;
      }

      AppLogger.log('BlockchainTxService: tx submit failed ${resp.statusCode}: ${resp.body}');
      return false;
    } catch (e) {
      AppLogger.log('BlockchainTxService: tx submit error: $e');
      return false;
    }
  }

  static Future<String?> _selectBlockerEndpoint() async {
    try {
      final resp = await http.get(Uri.parse('${AppConstants.apiBaseUrl}/blockcreatornode/list'));
      if (resp.statusCode != 200) {
        AppLogger.log('BlockchainTxService: blocker list failed ${resp.statusCode}: ${resp.body}');
        return null;
      }
      final list = jsonDecode(resp.body) as List<dynamic>;
      if (list.isEmpty) return null;
      final choice = list[Random().nextInt(list.length)] as Map<String, dynamic>;
      final endpoint = choice['endpoint']?.toString() ?? choice['Endpoint']?.toString();
      return endpoint;
    } catch (e) {
      AppLogger.log('BlockchainTxService: blocker list error: $e');
      return null;
    }
  }
}
