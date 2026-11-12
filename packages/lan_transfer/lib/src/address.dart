import 'dart:io';

import 'protocol.dart';

/// The address a PC types after reading it from the phone.
///
/// Accepts `192.168.1.5:54321` and `http://192.168.1.5:54321/`; a port is
/// mandatory. Only IPv4 literals (or `localhost` for loopback tests) are
/// accepted; the phone advertises an IPv4 LAN address.
final class LanAddress {
  const LanAddress({required this.host, required this.port});

  final String host;
  final int port;

  String get authority => '$host:$port';

  static LanAddress parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const LanTransferException('请填写手机屏幕上显示的地址。');
    }
    final raw = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const LanTransferException('地址格式不正确，应为 192.168.x.x:端口。');
    }
    final host = uri.host;
    final isLoopbackName = host == 'localhost';
    final parsed = InternetAddress.tryParse(host);
    if (!isLoopbackName &&
        (parsed == null || parsed.type != InternetAddressType.IPv4)) {
      throw const LanTransferException('只支持局域网 IPv4 地址。');
    }
    final port = uri.port;
    if (port < 1 || port > 65535) {
      throw const LanTransferException('端口不正确。');
    }
    return LanAddress(host: host, port: port);
  }

  @override
  String toString() => authority;
}
