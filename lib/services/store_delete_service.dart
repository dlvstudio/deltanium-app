import 'dart:convert';

import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/crypto_service.dart';
import 'package:deltanium_app/services/store_node_directory.dart';
import 'package:http/http.dart' as http;

/// Deletes one of the user's stored items (post, comment) from every Store that holds a copy.
///
/// An item is replicated to several Stores. Deleting it only on the Store the app read it from left the other copies
/// in place, and the item came back on the next refresh. The Stores holding it are the `storeNodeIds` of its storage
/// contract on Central; when that lookup fails, every known Store is asked (a Store without it answers 404).
class StoreDeleteService {
  /// HTTPS endpoints of the Stores holding [fileId], plus [knownEndpoint] (where the app read it).
  static Future<List<String>> holdersOf(String fileId, String knownEndpoint) async {
    final endpoints = <String>{};
    final known = StoreNodeDirectory.normalizeEndpoint(knownEndpoint);
    if (known.startsWith('https://') || known.startsWith('http://')) endpoints.add(known);
    try {
      final nodes = await StoreNodeDirectory.listNodes(requireNonEmpty: false);
      String httpsOf(Map<String, dynamic> n) => (n['httpsEndpoint'] as String? ?? '').trim();
      List<String> ids = const [];
      try {
        final resp = await http.get(Uri.parse('${AppConstants.apiBaseUrl}/storedfile/contract/$fileId'));
        if (resp.statusCode == 200) {
          final body = json.decode(resp.body);
          if (body is Map && body['storeNodeIds'] is List) {
            ids = (body['storeNodeIds'] as List).map((e) => e.toString()).toList();
          }
        }
      } catch (e) {
        AppLogger.log('StoreDeleteService: contract lookup for $fileId failed: $e');
      }
      final holders = ids.isEmpty ? nodes : nodes.where((n) => ids.contains(n['id']?.toString())).toList();
      endpoints.addAll(holders.map(httpsOf).where((e) => e.isNotEmpty));
    } catch (e) {
      AppLogger.log('StoreDeleteService: store list failed: $e');
    }
    return endpoints.toList();
  }

  /// Sends the owner-signed `DELETE {path}` to every Store holding [fileId]. True when at least one Store answered
  /// and none refused: 200 deleted its copy, 404 had none (already deleted, or never held it).
  static Future<bool> deleteEverywhere({
    required String fileId,
    required String path,
    required String knownEndpoint,
    required String userPublicKey,
    required String userMnemonic,
  }) async {
    final targets = await holdersOf(fileId, knownEndpoint);
    var answered = 0, refused = 0;
    await Future.wait(targets.map((endpoint) async {
      try {
        final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
        final signature = await CryptoService.sign('DELETE$path$timestamp', userMnemonic);
        final resp = await http.delete(
          Uri.parse('$endpoint$path'),
          headers: {
            'X-User-PubKey': CryptoService.normalizePublicKey(userPublicKey),
            'X-Timestamp': timestamp,
            'X-Signature': signature,
          },
        );
        AppLogger.log('StoreDeleteService: DELETE $endpoint$path -> ${resp.statusCode}');
        if (resp.statusCode == 200 || resp.statusCode == 404) {
          answered++;
        } else {
          refused++;
        }
      } catch (e) {
        // Unreachable Store: its copy is removed by the on-chain term cleanup once the paid period ends.
        AppLogger.log('StoreDeleteService: DELETE $endpoint$path failed: $e');
      }
    }));
    return answered > 0 && refused == 0;
  }
}
