import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lan_transfer/lan_transfer.dart';
import 'package:test/test.dart';

Future<(LanTransferServer, LanTransferClient, LanAddress)> _serve({
  required LanTransferMode mode,
  Future<LanPullPayload?> Function()? onPull,
  Future<void> Function(String, Uint8List)? onPush,
  Duration ttl = const Duration(seconds: 10),
  int maxBundleBytes = defaultMaxBundleBytes,
}) async {
  final server = LanTransferServer(
    mode: mode,
    device: 'android',
    onPull: onPull ?? () async => null,
    onPush: onPush ?? (_, __) async {},
    bindAddress: InternetAddress.loopbackIPv4,
    advertisedAddress: '127.0.0.1',
    sessionTtl: ttl,
    maxBundleBytes: maxBundleBytes,
  );
  await server.start();
  final address = LanAddress.parse(server.address!);
  final client = LanTransferClient(maxBundleBytes: maxBundleBytes);
  return (server, client, address);
}

void main() {
  test('codes are 60-bit Crockford base32 and survive formatting', () {
    final codes = <String>{};
    for (var i = 0; i < 200; i++) {
      final code = LanTransferCode.generate();
      expect(code.length, lanCodeLength);
      expect(LanTransferCode.isValid(code), isTrue);
      expect(codes.add(code), isTrue, reason: '生成的配对码不应重复');
    }
    expect(LanTransferCode.format('abcd-efgh-jkmn'), 'ABCD-EFGH-JKMN');
    expect(LanTransferCode.normalize('iI-lL-oO'), '111100');
    expect(LanTransferCode.isValid('short'), isFalse);
    expect(LanTransferCode.isValid('UUUU-UUUU-UUUU'), isFalse);
  });

  test('address parsing requires IPv4 and an explicit port', () {
    expect(
        LanAddress.parse('192.168.1.5:54321').authority, '192.168.1.5:54321');
    expect(
      LanAddress.parse('http://192.168.1.5:54321/').authority,
      '192.168.1.5:54321',
    );
    expect(
      () => LanAddress.parse('192.168.1.5'),
      throwsA(isA<LanTransferException>()),
    );
    expect(
      () => LanAddress.parse('https://192.168.1.5:54321'),
      throwsA(isA<LanTransferException>()),
    );
    expect(
      () => LanAddress.parse('192.168.1.5:54321/path'),
      throwsA(isA<LanTransferException>()),
    );
  });

  test('private LAN address detection excludes carrier/VPN ranges', () {
    expect(LanTransferServer.isPrivateLanIpv4('192.168.1.5'), isTrue);
    expect(LanTransferServer.isPrivateLanIpv4('10.0.2.15'), isTrue);
    expect(LanTransferServer.isPrivateLanIpv4('172.16.0.2'), isTrue);
    expect(LanTransferServer.isPrivateLanIpv4('172.32.0.2'), isFalse);
    expect(LanTransferServer.isPrivateLanIpv4('100.64.0.2'), isFalse);
    expect(LanTransferServer.isPrivateLanIpv4('8.8.8.8'), isFalse);
    expect(LanTransferServer.isPrivateLanIpv4('not-an-ip'), isFalse);
  });

  test('file names are sanitized and bounded', () {
    expect(sanitizeLanFileName('fjob-2026-11-12.fjob'), 'fjob-2026-11-12.fjob');
    expect(sanitizeLanFileName('/etc/passwd?.fjob'), '_etc_passwd_.fjob');
    expect(sanitizeLanFileName('   '), 'fjob-lan.fjob');
    expect(sanitizeLanFileName('a' * 300).length, 120);
  });

  test('AES-GCM round trip rejects a wrong code and tampering', () async {
    final salt = List<int>.generate(16, (index) => index);
    final key = await LanCrypto.deriveKey(code: 'ABCD-EFGH-JKMN', salt: salt);
    final envelope = await LanCrypto.seal(
      key,
      {'message': 'hello'},
      context: 'transfer',
    );
    final opened = await LanCrypto.open(key, envelope, context: 'transfer');
    expect(opened['message'], 'hello');

    final wrongKey =
        await LanCrypto.deriveKey(code: 'ABCD-EFGH-JKMX', salt: salt);
    await expectLater(
      LanCrypto.open(wrongKey, envelope, context: 'transfer'),
      throwsA(isA<LanTransferException>()),
    );

    final tamperedBytes = base64Decode(envelope.cipherTextBase64);
    tamperedBytes[0] ^= 1;
    final tampered = LanEnvelope(
      nonceBase64: envelope.nonceBase64,
      cipherTextBase64: base64Encode(tamperedBytes),
      macBase64: envelope.macBase64,
    );
    await expectLater(
      LanCrypto.open(key, tampered, context: 'transfer'),
      throwsA(isA<LanTransferException>()),
    );
  });

  test('phone sends a bundle to the PC over the loopback session', () async {
    final bundle = Uint8List.fromList(utf8.encode('{"format":"fjob"}'));
    final (server, client, address) = await _serve(
      mode: LanTransferMode.send,
      onPull: () async => LanPullPayload(
        fileName: 'fjob-2026-11-12.fjob',
        bytes: bundle,
      ),
    );
    addTearDown(() async {
      client.close();
      await server.stop();
    });
    final events = <LanServerEvent>[];
    final subscription = server.events.listen(events.add);
    addTearDown(subscription.cancel);

    final info = await client.probe(address);
    expect(info.mode, LanTransferMode.send);
    expect(info.version, lanProtocolVersion);
    final pulled = await client.pull(
      address: address,
      code: server.pairingCode,
    );
    expect(pulled.fileName, 'fjob-2026-11-12.fjob');
    expect(pulled.bytes, bundle);

    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(server.isRunning, isFalse, reason: '一次性会话应自动结束');
    expect(
      events.map((event) => event.type),
      containsAll(<LanServerEventType>[
        LanServerEventType.paired,
        LanServerEventType.pulled,
        LanServerEventType.stopped,
      ]),
    );
    await expectLater(
      client.probe(address),
      throwsA(isA<LanTransferException>()),
      reason: '会话结束后不能再探测',
    );
  });

  test('PC pushes a bundle into the phone receive session', () async {
    Uint8List? received;
    String? receivedName;
    final (server, client, address) = await _serve(
      mode: LanTransferMode.receive,
      onPush: (name, bytes) async {
        receivedName = name;
        received = bytes;
      },
    );
    addTearDown(() async {
      client.close();
      await server.stop();
    });

    final bytes = Uint8List.fromList(utf8.encode('{"format":"fjob"}'));
    await client.push(
      address: address,
      code: server.pairingCode,
      fileName: 'pc.fjob',
      bytes: bytes,
    );
    expect(receivedName, 'pc.fjob');
    expect(received, bytes);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(server.isRunning, isFalse);
  });

  test('wrong code is rejected and repeated failures end the session',
      () async {
    final (server, client, address) = await _serve(
      mode: LanTransferMode.send,
      onPull: () async => LanPullPayload(
        fileName: 'x.fjob',
        bytes: Uint8List.fromList([1]),
      ),
    );
    addTearDown(() async {
      client.close();
      await server.stop();
    });

    for (var attempt = 0; attempt < 5; attempt++) {
      await expectLater(
        client.pull(address: address, code: 'ABCD-EFGH-JKMX'),
        throwsA(
          isA<LanTransferException>().having(
            (error) => error.message,
            'message',
            contains('配对码不正确'),
          ),
        ),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.isRunning, isFalse, reason: '连续错码后应结束会话');
  });

  test('mode mismatch is rejected without consuming the session', () async {
    final (server, client, address) = await _serve(
      mode: LanTransferMode.send,
      onPull: () async => LanPullPayload(
        fileName: 'x.fjob',
        bytes: Uint8List.fromList([1]),
      ),
    );
    addTearDown(() async {
      client.close();
      await server.stop();
    });
    await expectLater(
      client.push(
        address: address,
        code: server.pairingCode,
        fileName: 'x.fjob',
        bytes: Uint8List.fromList([1]),
      ),
      throwsA(
        isA<LanTransferException>().having(
          (error) => error.message,
          'message',
          contains('「发送到电脑」'),
        ),
      ),
    );
    expect(server.isRunning, isTrue);
  });

  test('oversized pushes are rejected by the server', () async {
    final (server, client, address) = await _serve(
      mode: LanTransferMode.receive,
      maxBundleBytes: 16,
    );
    addTearDown(() async {
      client.close();
      await server.stop();
    });
    // The client checks its own limit too; use a larger client limit so the
    // server's check is the one under test.
    final oversizedClient = LanTransferClient(maxBundleBytes: 1024);
    addTearDown(oversizedClient.close);
    await expectLater(
      oversizedClient.push(
        address: address,
        code: server.pairingCode,
        fileName: 'x.fjob',
        bytes: Uint8List(32),
      ),
      throwsA(isA<LanTransferException>()),
    );
  });

  test('expired sessions stop accepting connections', () async {
    final (server, client, address) = await _serve(
      mode: LanTransferMode.send,
      ttl: const Duration(milliseconds: 300),
    );
    addTearDown(() async {
      client.close();
      await server.stop();
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(server.isRunning, isFalse);
    await expectLater(
      client.probe(address),
      throwsA(isA<LanTransferException>()),
    );
  });
}
