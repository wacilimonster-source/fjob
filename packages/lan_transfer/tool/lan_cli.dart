// Command-line guest for LAN transfer E2E checks.
//
//   dart run tool/lan_cli.dart pull <address> <code> <out.fjob>
//   dart run tool/lan_cli.dart push <address> <code> <file.fjob>
//
// It uses the same encrypted protocol as the PC app; it is a verification
// helper, not part of the shipped UI.
import 'dart:io';

import 'package:lan_transfer/lan_transfer.dart';

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    stderr.writeln('usage: lan_cli.dart pull|push <address> <code> <file>');
    exit(64);
  }
  final client = LanTransferClient();
  try {
    final address = LanAddress.parse(args[1]);
    if (args[0] == 'pull') {
      final pulled = await client.pull(address: address, code: args[2]);
      File(args[3]).writeAsBytesSync(pulled.bytes);
      stdout.writeln(
        'pulled ${pulled.fileName} (${pulled.bytes.length} bytes)',
      );
    } else if (args[0] == 'push') {
      final file = File(args[3]);
      final bytes = file.readAsBytesSync();
      await client.push(
        address: address,
        code: args[2],
        fileName: file.uri.pathSegments.last,
        bytes: bytes,
      );
      stdout.writeln('pushed ${bytes.length} bytes');
    } else {
      stderr.writeln('unknown action ${args[0]}');
      exit(64);
    }
  } on LanTransferException catch (error) {
    stderr.writeln(error.message);
    exit(2);
  } finally {
    client.close();
  }
}
