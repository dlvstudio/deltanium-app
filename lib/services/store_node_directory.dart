import 'dart:convert';
import 'dart:math';

import 'package:deltanium_app/config/constants.dart';
import 'package:deltanium_app/services/app_logger.dart';
import 'package:deltanium_app/services/dltp/node_address.dart';
import 'package:http/http.dart' as http;

/// Resolves active Store node endpoints from Central API.
///
/// When the app points at a remote Central API, localhost / 127.0.0.1
/// endpoints registered by mistake are ignored so web builds never call
/// the developer's machine.
class StoreNodeDirectory {
  StoreNodeDirectory._();

  static bool get _apiIsLocal => AppConstants.isLocalApiBase;

  static String normalizeEndpoint(String raw) =>
      raw.trim().replaceAll(RegExp(r'/+$'), '');

  static bool isUsableEndpoint(String endpoint) {
    if (endpoint.isEmpty) return false;
    final local = endpoint.contains('localhost') || endpoint.contains('127.0.0.1');
    if (local && !_apiIsLocal) return false;
    return true;
  }

  /// Normalize and drop localhost endpoints when Central API is remote.
  static String? sanitizeEndpoint(String? raw) {
    if (raw == null) return null;
    final endpoint = normalizeEndpoint(raw);
    return isUsableEndpoint(endpoint) ? endpoint : null;
  }

  /// `endpoint` is the base URL this build uses for the node (see [NodeAddress]):
  /// its HTTPS endpoint, or on desktop / mobile a DLTP-routed URL for a node that
  /// only publishes a `tcps://` endpoint. `httpsEndpoint` is the node's real HTTPS
  /// endpoint ('' for a TCP-only node).
  static Map<String, dynamic> normalizeNode(Map<String, dynamic> node, {int index = 0}) {
    final https = normalizeEndpoint(
      (node['endpoint'] ?? node['Endpoint'] ?? '').toString(),
    );
    final tcp = (node['tcpEndpoint'] ?? node['TcpEndpoint'])?.toString();
    final endpoint = NodeAddress.of(https, tcp);
    final id = (node['id'] ?? node['Id'] ?? node['publicKey'] ?? node['PublicKey'] ?? 'node-$index')
        .toString();
    return {
      ...node,
      'id': id,
      'endpoint': endpoint,
      'httpsEndpoint': https,
    };
  }

  /// Up to [n] random nodes for a new upload. The first one (the primary, whose URL is
  /// stored in the post) has an HTTPS endpoint whenever one is available, so web
  /// readers can open the link.
  static List<Map<String, dynamic>> pickForUpload(List<Map<String, dynamic>> nodes, int n, {Random? random}) {
    if (nodes.isEmpty) return nodes;
    final shuffled = List<Map<String, dynamic>>.from(nodes)..shuffle(random ?? Random());
    final picked = shuffled.take(n.clamp(1, shuffled.length)).toList();
    bool hasHttps(Map<String, dynamic> x) => (x['httpsEndpoint'] as String? ?? x['endpoint'] as String? ?? '').isNotEmpty;
    if (hasHttps(picked.first)) return picked;
    final i = picked.indexWhere(hasHttps);
    if (i > 0) {
      final first = picked[0];
      picked[0] = picked[i];
      picked[i] = first;
      return picked;
    }
    final outside = shuffled.skip(picked.length).where(hasHttps).toList();
    if (outside.isNotEmpty) picked.insert(0, outside.first);
    return picked.take(n.clamp(1, shuffled.length)).toList();
  }

  /// Full node maps with normalized `id` + `endpoint`.
  static Future<List<Map<String, dynamic>>> listNodes({bool requireNonEmpty = true}) async {
    final url = '${AppConstants.apiBaseUrl}/storenode/list';
    AppLogger.log('StoreNodeDirectory: GET $url');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch store nodes: HTTP ${response.statusCode}');
    }

    final decoded = json.decode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected storenode/list response');
    }

    final nodes = <Map<String, dynamic>>[];
    for (var i = 0; i < decoded.length; i++) {
      final raw = Map<String, dynamic>.from(decoded[i] as Map);
      final normalized = normalizeNode(raw, index: i);
      if (!isUsableEndpoint(normalized['endpoint'] as String)) {
        AppLogger.log(
          'StoreNodeDirectory: skipping unusable endpoint ${normalized['endpoint']}',
        );
        continue;
      }
      nodes.add(normalized);
    }

    if (requireNonEmpty && nodes.isEmpty) {
      throw Exception('No reachable store nodes registered with Central API');
    }
    return nodes;
  }

  /// Endpoint strings only.
  static Future<List<String>> listEndpoints({bool requireNonEmpty = true}) async {
    final nodes = await listNodes(requireNonEmpty: requireNonEmpty);
    return nodes.map((n) => n['endpoint'] as String).toList();
  }
}
