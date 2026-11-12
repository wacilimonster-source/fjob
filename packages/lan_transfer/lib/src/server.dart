import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'code.dart';
import 'crypto.dart';
import 'protocol.dart';

/// A short-lived LAN server hosted by the phone.
///
/// The user starts a session (send or receive), reads the address and pairing
/// code aloud/over to the PC, and the PC performs exactly one encrypted
/// transfer. The server stops after one success, [sessionTtl], or
/// [maxAuthFailures] wrong pairing codes.
final class LanTransferServer {
  LanTransferServer({
    required this.mode,
    required this.device,
    required this.onPull,
    required this.onPush,
    this.sessionTtl = const Duration(minutes: 10),
    this.maxBundleBytes = defaultMaxBundleBytes,
    this.maxAuthFailures = 5,
    this.advertisedAddress,
    InternetAddress? bindAddress,
  }) : _bindAddress = bindAddress ?? InternetAddress.anyIPv4;

  final LanTransferMode mode;
  final String device;

  /// Returns the phone's bundle for a pull, or null when the ledger is not
  /// ready. Implementations must not throw for a normal unavailable state.
  final Future<LanPullPayload?> Function() onPull;

  /// Called after a successful authenticated push. The implementation should
  /// queue the bundle for user confirmation; it must not import silently.
  final Future<void> Function(String fileName, Uint8List bytes) onPush;

  final Duration sessionTtl;
  final int maxBundleBytes;
  final int maxAuthFailures;
  final String? advertisedAddress;

  final InternetAddress _bindAddress;
  final StreamController<LanServerEvent> _events =
      StreamController<LanServerEvent>.broadcast();

  final Random _random = Random.secure();
  HttpServer? _server;
  Timer? _ttlTimer;
  Timer? _stopTimer;
  List<int> _salt = const [];
  List<int> _challenge = const [];
  late String _code;
  DateTime? _expiresAt;
  String? _address;
  int _authFailures = 0;
  bool _completed = false;
  bool _stopped = false;

  Stream<LanServerEvent> get events => _events.stream;

  String get pairingCode => _code;

  String? get address => _address;

  DateTime? get expiresAt => _expiresAt;

  bool get isRunning => _server != null;

  int get encodedBodyLimit => (maxBundleBytes * 4 ~/ 3) + 64 * 1024;

  Future<void> start() async {
    if (_server != null) return;
    _code = LanTransferCode.generate();
    _salt = _randomBytes(16);
    _challenge = _randomBytes(16);
    _expiresAt = DateTime.now().toUtc().add(sessionTtl);
    final ip = advertisedAddress ?? await selectLanIpv4();
    if (ip == null) {
      throw const LanTransferException('没有可用的局域网地址，请先连接与电脑相同的 Wi-Fi。');
    }
    final server = await HttpServer.bind(_bindAddress, 0);
    _server = server;
    _address = '$ip:${server.port}';
    _ttlTimer = Timer(sessionTtl, () => unawaited(_finish()));
    server.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object _) {},
      cancelOnError: false,
    );
    _emit(LanServerEventType.listening);
  }

  Future<void> stop() => _finish();

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    try {
      if (_completed) {
        await _json(response, HttpStatus.gone, {'error': 'finished'});
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/session') {
        await _json(response, HttpStatus.ok, {
          'v': lanProtocolVersion,
          'mode': mode.name,
          'device': device,
          'salt': base64Encode(_salt),
          'challenge': base64Encode(_challenge),
          'expiresAt': _expiresAt!.toIso8601String(),
        });
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/transfer') {
        await _transfer(request, response);
        return;
      }
      await _json(response, HttpStatus.notFound, {'error': 'not_found'});
    } on Object {
      try {
        await _json(response, HttpStatus.internalServerError, {
          'error': 'server',
        });
      } on Object {
        // The peer may have disconnected; nothing else to do.
      }
    }
  }

  Future<void> _transfer(HttpRequest request, HttpResponse response) async {
    final body = await _readBody(request, encodedBodyLimit);
    if (body == null) {
      await _json(response, HttpStatus.requestEntityTooLarge, {
        'error': 'too_large',
      });
      return;
    }
    final LanEnvelope envelope;
    try {
      envelope = LanEnvelope.fromJson(jsonDecode(utf8.decode(body)));
    } on Object {
      await _json(response, HttpStatus.badRequest, {'error': 'format'});
      return;
    }
    final key = await LanCrypto.deriveKey(code: _code, salt: _salt);
    final Map<String, dynamic> payload;
    try {
      payload = await LanCrypto.open(key, envelope, context: 'transfer');
    } on LanTransferException {
      _authFailures++;
      await _json(response, HttpStatus.unauthorized, {'error': 'auth'});
      if (_authFailures >= maxAuthFailures) await _finish();
      return;
    }
    _emit(LanServerEventType.paired);
    if (payload['v'] != lanProtocolVersion ||
        payload['challenge'] != base64Encode(_challenge)) {
      await _json(response, HttpStatus.conflict, {'error': 'session'});
      return;
    }
    switch (payload['action']) {
      case 'pull':
        await _pull(key, response);
      case 'push':
        await _push(key, payload, response);
      default:
        await _json(response, HttpStatus.badRequest, {'error': 'action'});
    }
  }

  Future<void> _pull(SecretKey key, HttpResponse response) async {
    if (mode != LanTransferMode.send) {
      await _json(response, HttpStatus.conflict, {'error': 'mode'});
      return;
    }
    final result = await onPull();
    if (result == null) {
      await _json(response, HttpStatus.serviceUnavailable, {
        'error': 'unavailable',
      });
      return;
    }
    final sealed = await LanCrypto.seal(
        key,
        {
          'ok': true,
          'fileName': sanitizeLanFileName(result.fileName),
          'bundle': base64Encode(result.bytes),
        },
        context: 'transfer');
    _completed = true;
    await _json(response, HttpStatus.ok, sealed.toJson());
    _emit(LanServerEventType.pulled);
    _scheduleStop();
  }

  Future<void> _push(
    SecretKey key,
    Map<String, dynamic> payload,
    HttpResponse response,
  ) async {
    if (mode != LanTransferMode.receive) {
      await _json(response, HttpStatus.conflict, {'error': 'mode'});
      return;
    }
    final fileName = payload['fileName'];
    final bundle = payload['bundle'];
    if (fileName is! String || bundle is! String) {
      await _json(response, HttpStatus.badRequest, {'error': 'format'});
      return;
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(bundle);
    } on FormatException {
      await _json(response, HttpStatus.badRequest, {'error': 'format'});
      return;
    }
    if (bytes.length > maxBundleBytes) {
      await _json(response, HttpStatus.requestEntityTooLarge, {
        'error': 'too_large',
      });
      return;
    }
    await onPush(sanitizeLanFileName(fileName), bytes);
    final sealed = await LanCrypto.seal(key, {'ok': true}, context: 'transfer');
    _completed = true;
    await _json(response, HttpStatus.ok, sealed.toJson());
    _emit(LanServerEventType.pushed);
    _scheduleStop();
  }

  Future<Uint8List?> _readBody(HttpRequest request, int limit) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > limit) return null;
    }
    return builder.takeBytes();
  }

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));

  void _emit(LanServerEventType type, {String? message}) {
    if (!_events.isClosed) {
      _events.add(LanServerEvent(type, message: message));
    }
  }

  void _scheduleStop() {
    _stopTimer?.cancel();
    _stopTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_finish());
    });
  }

  Future<void> _finish() async {
    if (_stopped) return;
    _stopped = true;
    _ttlTimer?.cancel();
    _stopTimer?.cancel();
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
    _emit(LanServerEventType.stopped);
    await _events.close();
  }

  static Future<String?> selectLanIpv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final candidates = <String>[
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (isPrivateLanIpv4(address.address)) address.address,
    ];
    int score(String ip) {
      if (ip.startsWith('192.168.')) return 3;
      if (ip.startsWith('10.')) return 2;
      if (ip.startsWith('172.')) return 1;
      return 0;
    }

    candidates.sort((a, b) => score(b).compareTo(score(a)));
    return candidates.isEmpty ? null : candidates.first;
  }

  static bool isPrivateLanIpv4(String ip) {
    final parts = ip.split('.').map(int.tryParse).toList();
    if (parts.length != 4 ||
        parts.any((part) => part == null || part < 0 || part > 255)) {
      return false;
    }
    final a = parts[0]!;
    final b = parts[1]!;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }
}
