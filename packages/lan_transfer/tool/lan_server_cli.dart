// Command-line host for LAN transfer E2E checks.
//
//   dart run tool/lan_server_cli.dart send <bundle.fjob> [ttlSeconds]
//   dart run tool/lan_server_cli.dart receive <out.fjob> [ttlSeconds]
//
// Binds to loopback so the desktop UI can join via 127.0.0.1:port. It is a
// verification helper, not part of the shipped UI.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:lan_transfer/lan_transfer.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr
        .writeln('usage: lan_server_cli.dart send|receive <file> [ttlSeconds]');
    exit(64);
  }
  final mode = args[0] == 'send'
      ? LanTransferMode.send
      : args[0] == 'receive'
          ? LanTransferMode.receive
          : null;
  if (mode == null) {
    stderr.writeln('unknown mode ${args[0]}');
    exit(64);
  }
  final path = args[1];
  final ttl =
      Duration(seconds: int.tryParse(args.length > 2 ? args[2] : '') ?? 180);
  final done = Completer<void>();
  final server = LanTransferServer(
    mode: mode,
    device: 'windows-test',
    bindAddress: InternetAddress.loopbackIPv4,
    advertisedAddress: '127.0.0.1',
    sessionTtl: ttl,
    onPull: () async => LanPullPayload(
      fileName: File(path).uri.pathSegments.last,
      bytes: File(path).readAsBytesSync(),
    ),
    onPush: (fileName, Uint8List bytes) async {
      File(path).writeAsBytesSync(bytes);
      stdout.writeln('received $fileName (${bytes.length} bytes)');
    },
  );
  server.events.listen((event) {
    stdout.writeln('event ${event.type.name}');
    if (event.type == LanServerEventType.stopped && !done.isCompleted) {
      done.complete();
    }
  });
  await server.start();
  stdout.writeln('address=${server.address}');
  stdout.writeln('code=${LanTransferCode.format(server.pairingCode)}');
  await done.future;
  exit(0);
}
