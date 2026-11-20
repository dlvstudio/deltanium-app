/// Where a node can be reached: its HTTPS endpoint, its DLTP (TCP) endpoint, or both.
///
/// Callers keep building ordinary `https://` URLs. When this build can speak DLTP
/// (desktop / mobile, see [enabled]) and a node publishes a `tcps://host:port`
/// endpoint, the node's base URL is mapped to that endpoint and the routing HTTP
/// client sends its requests over DLTP. A node with both keeps its real HTTPS
/// URL (stored links stay readable on the web) and falls back to HTTPS when
/// DLTP fails. A TCP-only node gets the base URL `https://host:port`, which
/// only the routing client can reach; the web build skips such nodes.
///
/// A DLTP endpoint names a host (`tcps://store.example.com:7333`, TLS checked against the public CA like
/// HTTPS) or a public IP (`tcps://203.0.113.7:7333`, a node on a home or personal computer with no domain).
/// For an IP the node proves itself with its registered key instead (see `node_proof.dart`), so [of]
/// needs the node's public key.
class NodeAddress {
  NodeAddress._();

  /// True once the DLTP routing client is installed (never on the web).
  static bool enabled = false;

  static final Map<String, DltpRoute> _routes = {};

  /// `tcps://host:port`, or `tcp://localhost:port` for local development.
  static Uri? parseTcp(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || !uri.hasPort || uri.port <= 0) return null;
    if (uri.scheme == 'tcps') return uri;
    final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (uri.scheme == 'tcp' && local) return uri;
    return null;
  }

  /// Base URL the app should use for a node, or '' when this build cannot reach it.
  static String of(String? https, String? tcp, {String? publicKey}) {
    final h = (https ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    final t = enabled ? parseTcp(tcp) : null;
    if (t == null) return h;
    final key = (publicKey ?? '').trim();
    final route = DltpRoute(t, hasHttps: h.isNotEmpty, nodePublicKey: key.isEmpty ? null : key);
    // An IP endpoint without a key to check it against cannot be trusted: use HTTPS only.
    if (route.keyMode && route.nodePublicKey == null) return h;
    final base = h.isNotEmpty ? h : 'https://${_hostForUrl(t.host)}:${t.port}';
    _routes[_key(Uri.parse(base))] = route;
    return base;
  }

  /// True for an IPv4 or IPv6 literal (a node without a domain).
  static bool isIpLiteral(String host) =>
      RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host.contains(':');

  static String _hostForUrl(String host) => host.contains(':') ? '[$host]' : host;

  /// The DLTP route for a request URL, if its node publishes one.
  static DltpRoute? routeFor(Uri url) => _routes[_key(url)];

  static void clear() => _routes.clear();

  static String _key(Uri u) => '${u.scheme}://${u.host.toLowerCase()}:${u.hasPort ? u.port : 443}';
}

class DltpRoute {
  final Uri tcp;

  /// The node also has an HTTPS endpoint, so a failed DLTP call may retry there.
  final bool hasHttps;

  /// The node's registered public key (hex), checked on IP endpoints.
  final String? nodePublicKey;

  const DltpRoute(this.tcp, {required this.hasHttps, this.nodePublicKey});

  bool get tls => tcp.scheme == 'tcps';

  /// IP endpoints authenticate with the node key instead of a CA certificate.
  bool get keyMode => tls && NodeAddress.isIpLiteral(tcp.host);

  String get authority => '${NodeAddress._hostForUrl(tcp.host)}:${tcp.port}';
}
