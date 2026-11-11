import 'dart:ffi';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

/// Windows ships `winsqlite3.dll` with the same C API as SQLite; using it avoids
/// bundling a native library in the portable zip. Initialized once before any
/// database is opened.
void initDesktopDatabase() {
  if (Platform.isWindows) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('winsqlite3.dll'),
    );
  }
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}