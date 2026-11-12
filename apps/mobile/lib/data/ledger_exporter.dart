import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'ledger_files.dart';

typedef LedgerSaveFilePicker = Future<Uri?> Function({
  required String fileName,
  required Uint8List bytes,
});

typedef LedgerSaveToDownloads = Future<String> Function({
  required String fileName,
  required Uint8List bytes,
});

enum LedgerExportTarget { picked, downloads, cancelled }

final class LedgerExportResult {
  const LedgerExportResult(
    this.target, {
    this.path,
    this.fallbackReason,
  });

  final LedgerExportTarget target;

  /// Picked URI or the Downloads-relative path, depending on [target].
  final String? path;

  /// Platform error code that triggered the Downloads fallback, when any.
  final String? fallbackReason;
}

/// Chooses the system save dialog first and falls back to the Downloads writer
/// when the picker itself fails. A null picker result is a deliberate cancel
/// and must not silently save somewhere else.
final class LedgerExporter {
  LedgerExporter({
    LedgerSaveFilePicker? pickFile,
    LedgerSaveToDownloads? saveToDownloads,
  })  : _pickFile = pickFile ?? _defaultPickFile,
        _saveToDownloads =
            saveToDownloads ?? const LedgerFilesBridge().saveToDownloads;

  final LedgerSaveFilePicker _pickFile;
  final LedgerSaveToDownloads _saveToDownloads;

  static Future<Uri?> _defaultPickFile({
    required String fileName,
    required Uint8List bytes,
  }) =>
      FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        dialogTitle: '保存账本文件',
      );

  Future<LedgerExportResult> export({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final uri = await _pickFile(fileName: fileName, bytes: bytes);
      if (uri == null) {
        return const LedgerExportResult(LedgerExportTarget.cancelled);
      }
      return LedgerExportResult(
        LedgerExportTarget.picked,
        path: uri.toString(),
      );
    } on PlatformException catch (error) {
      final path = await saveToDownloads(fileName: fileName, bytes: bytes);
      return LedgerExportResult(
        LedgerExportTarget.downloads,
        path: path,
        fallbackReason: error.code,
      );
    } on MissingPluginException {
      final path = await saveToDownloads(fileName: fileName, bytes: bytes);
      return LedgerExportResult(
        LedgerExportTarget.downloads,
        path: path,
        fallbackReason: 'picker_unavailable',
      );
    }
  }

  Future<String> saveToDownloads({
    required String fileName,
    required Uint8List bytes,
  }) =>
      _saveToDownloads(fileName: fileName, bytes: bytes);
}
