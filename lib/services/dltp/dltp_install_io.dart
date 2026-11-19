import 'package:http/http.dart' as http;

import 'dltp_client_io.dart';
import 'node_address.dart';

/// Desktop / mobile: every `http` call made inside [body] goes through the DLTP
/// routing client, so nodes with a TCP endpoint are reached over DLTP.
R runWithDltp<R>(R Function() body) {
  NodeAddress.enabled = true;
  return http.runWithClient(body, () => DltpRoutingClient());
}
