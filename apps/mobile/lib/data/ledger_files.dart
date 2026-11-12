import 'package:flutter/services.dart';

/// A user-facing failure while writing an exported bundle outside the system
/// picker. Messages never include ledger contents.
final class LedgerFileSaveException implements Exception {
  const LedgerFileSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Native bridge for the no-picker export fallback.
///
/// Android 10+ writes into the public Downloads/FJOB folder through MediaStore
/// without any storage permission; Android 8/9 writes into the app-specific
/// external Downloads folder. This keeps export working when an OEM file
/// picker cannot return a writable document.
final class LedgerFilesBridge {
  const LedgerFilesBridge({
    this.channel = const MethodChannel('cn.fjob.todayagain/files'),
  });

  final MethodChannel channel;

  Future<String> saveToDownloads({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final path = await channel.invokeMethod<String>('saveToDownloads', {
        'fileName': fileName,
        'bytes': bytes,
      });
      if (path == null || path.trim().isEmpty) {
        throw const LedgerFileSaveException('系统未返回下载位置');
      }
      return path;
    } on PlatformException catch (error) {
      throw LedgerFileSaveException(
        error.message ?? '无法写入下载目录（${error.code}）',
      );
    } on MissingPluginException {
      throw const LedgerFileSaveException('当前设备不支持保存到下载目录');
    }
  }
}
