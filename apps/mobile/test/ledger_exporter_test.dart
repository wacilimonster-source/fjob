import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/data/ledger_exporter.dart';
import 'package:todayagain/data/ledger_files.dart';

void main() {
  final bytes = Uint8List.fromList(<int>[1, 2, 3]);

  test('system picker result wins and does not touch Downloads', () async {
    var downloads = 0;
    final exporter = LedgerExporter(
      pickFile: ({required fileName, required bytes}) async =>
          Uri.parse('content://downloads/fjob.fjob'),
      saveToDownloads: ({required fileName, required bytes}) async {
        downloads++;
        return 'Download/FJOB/fjob.fjob';
      },
    );
    final result = await exporter.export(fileName: 'fjob.fjob', bytes: bytes);
    expect(result.target, LedgerExportTarget.picked);
    expect(result.path, 'content://downloads/fjob.fjob');
    expect(downloads, 0);
  });

  test('cancelled picker is not treated as a failure or fallback', () async {
    var downloads = 0;
    final exporter = LedgerExporter(
      pickFile: ({required fileName, required bytes}) async => null,
      saveToDownloads: ({required fileName, required bytes}) async {
        downloads++;
        return 'Download/FJOB/fjob.fjob';
      },
    );
    final result = await exporter.export(fileName: 'fjob.fjob', bytes: bytes);
    expect(result.target, LedgerExportTarget.cancelled);
    expect(result.path, isNull);
    expect(downloads, 0, reason: '用户取消不能偷偷改存到下载目录');
  });

  test('picker platform failure falls back to Downloads', () async {
    final exporter = LedgerExporter(
      pickFile: ({required fileName, required bytes}) async =>
          throw PlatformException(code: 'picker_failed', message: 'no activity'),
      saveToDownloads: ({required fileName, required bytes}) async =>
          'Download/FJOB/fjob.fjob',
    );
    final result = await exporter.export(fileName: 'fjob.fjob', bytes: bytes);
    expect(result.target, LedgerExportTarget.downloads);
    expect(result.path, 'Download/FJOB/fjob.fjob');
    expect(result.fallbackReason, 'picker_failed');
  });

  test('missing picker plugin falls back to Downloads', () async {
    final exporter = LedgerExporter(
      pickFile: ({required fileName, required bytes}) async =>
          throw MissingPluginException('no picker'),
      saveToDownloads: ({required fileName, required bytes}) async =>
          'Download/FJOB/fjob.fjob',
    );
    final result = await exporter.export(fileName: 'fjob.fjob', bytes: bytes);
    expect(result.target, LedgerExportTarget.downloads);
    expect(result.fallbackReason, 'picker_unavailable');
  });

  test('download failure is surfaced instead of being swallowed', () async {
    final exporter = LedgerExporter(
      pickFile: ({required fileName, required bytes}) async =>
          throw PlatformException(code: 'picker_failed'),
      saveToDownloads: ({required fileName, required bytes}) async =>
          throw const LedgerFileSaveException('没有可写空间'),
    );
    await expectLater(
      exporter.export(fileName: 'fjob.fjob', bytes: bytes),
      throwsA(
        isA<LedgerFileSaveException>().having(
          (error) => error.message,
          'message',
          '没有可写空间',
        ),
      ),
    );
  });

  test('bridge forwards the file and maps platform errors', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final channel = MethodChannel('test/ledger_files');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return 'Download/FJOB/fjob.fjob';
    });
    final bridge = LedgerFilesBridge(channel: channel);
    final path = await bridge.saveToDownloads(fileName: 'fjob.fjob', bytes: bytes);
    expect(path, 'Download/FJOB/fjob.fjob');
    expect(received?.method, 'saveToDownloads');
    expect(received?.arguments['fileName'], 'fjob.fjob');
    expect(received?.arguments['bytes'], bytes);

    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'save_failed', message: '磁盘已满');
    });
    await expectLater(
      bridge.saveToDownloads(fileName: 'fjob.fjob', bytes: bytes),
      throwsA(
        isA<LedgerFileSaveException>().having(
          (error) => error.message,
          'message',
          '磁盘已满',
        ),
      ),
    );
  });
}
