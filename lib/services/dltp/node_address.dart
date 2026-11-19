/// Where a node can be reached: its HTTPS endpoint, its DLTP (TCP) endpoint, or both.
///
/// Callers keep building ordinary `https://` URLs. When this build can speak DLTP
/// (desktop / mobile, see [enabled]) and a node publishes a `tcps://host:port`
/// endpoint, the node's base URL is mapped to that endpoint and the routing HTTP
/// client sends its requests over DLTP. A node with both keeps its real HTTPS
/// URL (stored links stay readable on the web) and falls back to HTTPS when
/// DLTP fails. A TCP-only node gets the base URL `https://host:port`, which
/// only the routing client can reach; the web build skips such nodes.
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
  static String of(String? https, String? tcp) {
    final h = (https ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    final t = enabled ? parseTcp(tcp) : null;
    if (t == null) return h;
    final base = h.isNotEmpty ? h : 'https://${t.host}:${t.port}';
    _routes[_key(Uri.parse(base))] = DltpRoute(t, hasHttps: h.isNotEmpty);
    return base;
  }

  /// The DLTP route for a request URL, if its node publishes one.
  static DltpRoute? routeFor(Uri url) => _routes[_key(url)];

  static void clear() => _routes.clear();

  static String _key(Uri u) => '${u.scheme}://${u.host.toLowerCase()}:${u.hasPort ? u.port : 443}';
}

class DltpRoute {
  final Uri tcp;

  /// The node also has an HTTPS endpoint, so a failed DLTP call may retry there.
  final bool hasHttps;

  const DltpRoute(this.tcp, {required this.hasHttps});

  bool get tls => tcp.scheme == 'tcps';
  String get authority => '${tcp.host}:${tcp.port}';
}
