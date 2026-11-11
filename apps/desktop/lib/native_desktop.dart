import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Physical, virtual-screen coordinates. Never use these as card logical offsets.
typedef DesktopRect = ({int left, int top, int right, int bottom});

/// Kept pure so taskbar auto-hide, negative monitor origins and maximization can
/// be tested without changing the user's foreground window.
bool isFullscreenCandidate({
  required DesktopRect window,
  required DesktopRect client,
  required DesktopRect monitor,
  required bool hasCaption,
  required bool hasSizingFrame,
  required bool maximized,
  bool ownProcess = false,
  bool shell = false,
}) {
  if (ownProcess || shell || hasCaption || (maximized && hasSizingFrame)) {
    return false;
  }
  if (monitor.right <= monitor.left || monitor.bottom <= monitor.top) {
    return false;
  }
  bool covers(DesktopRect rect) =>
      rect.left <= monitor.left + 1 &&
      rect.top <= monitor.top + 1 &&
      rect.right >= monitor.right - 1 &&
      rect.bottom >= monitor.bottom - 1;
  return covers(window) && covers(client);
}

class DesktopNativeException implements Exception {
  const DesktopNativeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The scaled report must land within this many physical pixels of the native
/// work area for the unit (logical vs physical) to be considered identified.
const double _workAreaTolerance = 2.0;

bool _matchesNative(
  ({double width, double height}) value,
  ({int width, int height}) native,
) =>
    (value.width - native.width).abs() <= _workAreaTolerance &&
    (value.height - native.height).abs() <= _workAreaTolerance;

/// Reconciles screen_retriever's work-area report against the native physical
/// work area and returns the LOGICAL rect for window_manager.setPosition.
/// Some builds report visibleSize in physical pixels, others in logical; the
/// side whose scaled value matches the native measurement wins, and dividing
/// by the scale once converts to logical. Falls back to treating the report
/// as logical (the historic PC0 assumption) when the native probe is absent.
({double left, double top, double width, double height})
resolveWorkAreaLogical({
  required ({double width, double height}) reported,
  required ({double dx, double dy}) origin,
  required double scale,
  ({int width, int height})? nativeWorkArea,
}) {
  // Degenerate scale (0 or negative) cannot convert units; treat as 1:1 so
  // placement degrades to identity instead of producing infinities.
  final effectiveScale = scale > 0 ? scale : 1.0;
  if (nativeWorkArea == null) {
    return (
      left: origin.dx / effectiveScale,
      top: origin.dy / effectiveScale,
      width: reported.width / effectiveScale,
      height: reported.height / effectiveScale,
    );
  }
  final scaled = (
    width: reported.width * effectiveScale,
    height: reported.height * effectiveScale,
  );
  // The report is physical when it matches the native measurement as-is, and
  // logical when only its scaled value does. Unknown → assume logical.
  final reportIsPhysical = _matchesNative(reported, nativeWorkArea);
  final reportIsLogical = _matchesNative(scaled, nativeWorkArea);
  final physical = reportIsPhysical
      ? reported
      : reportIsLogical
          ? scaled
          : scaled;
  final physicalOrigin = reportIsPhysical
      ? origin
      : (
          dx: origin.dx * effectiveScale,
          dy: origin.dy * effectiveScale,
        );
  return (
    left: physicalOrigin.dx / effectiveScale,
    top: physicalOrigin.dy / effectiveScale,
    width: physical.width / effectiveScale,
    height: physical.height / effectiveScale,
  );
}

/// No constructor side effects. In particular, startup registration is NEVER
/// reconciled on launch: only an explicit user setting may call the setter.
class NativeDesktop {
  const NativeDesktop();

  bool isForegroundFullscreen() {
    if (!Platform.isWindows) return false;
    return using((arena) {
      final hwnd = GetForegroundWindow();
      if (hwnd.address == 0 ||
          hwnd == GetDesktopWindow() ||
          hwnd == GetShellWindow()) {
        return false;
      }
      final processId = arena<Uint32>();
      if (GetWindowThreadProcessId(hwnd, processId) == 0) return false;
      if (processId.value == GetCurrentProcessId()) return false;

      final classBuffer = arena<Uint16>(256).cast<Utf16>();
      if (GetClassName(hwnd, PWSTR(classBuffer), 256).value == 0) return false;
      final className = classBuffer.toDartString();
      if (const {
        'Progman', 'WorkerW', 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd',
        'CabinetWClass', 'ExploreWClass',
      }.contains(className)) {
        return false;
      }
      // Exclude all Explorer-owned surfaces, not just the familiar classes.
      // An inaccessible process is unknown, not a positive fullscreen result.
      final process = OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION, false, processId.value,
      ).value;
      if (!process.isValid) return false;
      try {
        final length = arena<Uint32>()..value = 32768;
        final buffer = arena<Uint16>(length.value).cast<Utf16>();
        if (!QueryFullProcessImageName(
          process, PROCESS_NAME_WIN32, PWSTR(buffer), length,
        ).value) {
          return false;
        }
        final name = buffer.toDartString(length: length.value)
            .replaceAll('/', r'\').split(r'\').last.toLowerCase();
        if (name == 'explorer.exe') return false;
      } finally {
        CloseHandle(process);
      }

      final monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONULL);
      if (monitor.address == 0) return false;
      final info = arena<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
      final bounds = arena<RECT>();
      final client = arena<RECT>();
      if (!GetMonitorInfo(monitor, info) ||
          !GetWindowRect(hwnd, bounds).value ||
          !GetClientRect(hwnd, client).value) {
        return false;
      }
      final origin = arena<POINT>()
        ..ref.x = client.ref.left
        ..ref.y = client.ref.top;
      if (!ClientToScreen(hwnd, origin)) return false;
      final style = GetWindowLongPtr(hwnd, GWL_STYLE).value;
      return isFullscreenCandidate(
        window: _rect(bounds.ref),
        client: (
          left: origin.ref.x,
          top: origin.ref.y,
          right: origin.ref.x + client.ref.right - client.ref.left,
          bottom: origin.ref.y + client.ref.bottom - client.ref.top,
        ),
        monitor: _rect(info.ref.rcMonitor),
        hasCaption: (style & WS_CAPTION) != 0,
        hasSizingFrame: (style & WS_THICKFRAME) != 0,
        maximized: IsZoomed(hwnd),
      );
    });
  }

  static DesktopRect _rect(RECT value) => (
    left: value.left, top: value.top, right: value.right, bottom: value.bottom,
  );

  /// Primary monitor work area in PHYSICAL pixels (taskbar excluded), from
  /// SPI_GETWORKAREA. screen_retriever's visibleSize has proven ambiguous
  /// across builds (physical on some setups, logical on others), so placement
  /// anchors on this deterministic value and only uses the retriever output
  /// after [resolveWorkAreaLogical] reconciles the two.
  ({int width, int height})? primaryWorkArea() {
    if (!Platform.isWindows) return null;
    return using((arena) {
      final rect = arena<RECT>();
      if (!SystemParametersInfo(
        SPI_GETWORKAREA, 0, rect, SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
      ).value) {
        return null;
      }
      return (
        width: rect.ref.right - rect.ref.left,
        height: rect.ref.bottom - rect.ref.top,
      );
    });
  }

  /// Fingerprint of the primary monitor's physical work area. Used as the
  /// displayId for position memory: a saved position only restores while the
  /// monitor geometry matches, which also covers unplugged-monitor fallback.
  /// Multi-monitor identity comes with PC6/PC7; today the companion targets
  /// the primary display.
  String? primaryWorkAreaFingerprint() {
    final area = primaryWorkArea();
    if (area == null) return null;
    final rect = using((arena) {
      final r = arena<RECT>();
      SystemParametersInfo(
        SPI_GETWORKAREA, 0, r, SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
      );
      return (left: r.ref.left, top: r.ref.top);
    });
    return 'W${rect.left},${rect.top},${area.width},${area.height}';
  }

  static const _runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _startupName = 'FJOB';

  /// Queries only the current user's FJOB Run value; does not create keys.
  bool isStartupEnabled() {
    if (!Platform.isWindows) return false;
    return using((arena) {
      final handle = arena<Pointer>();
      final status = RegOpenKeyEx(
        HKEY_CURRENT_USER,
        PCWSTR(_runKey.toNativeUtf16(allocator: arena)),
        0, KEY_QUERY_VALUE, handle,
      );
      if (status == ERROR_FILE_NOT_FOUND) return false;
      _checkRegistry(status);
      final key = HKEY(handle.value);
      try {
        final type = arena<Uint32>();
        final size = arena<Uint32>();
        final result = RegQueryValueEx(
          key, PCWSTR(_startupName.toNativeUtf16(allocator: arena)),
          type, null, size,
        );
        if (result == ERROR_FILE_NOT_FOUND) return false;
        _checkRegistry(result);
        return type.value == REG_SZ && size.value > 2;
      } finally {
        RegCloseKey(key);
      }
    });
  }

  /// Explicit user action only. This API is not called by preferences loading,
  /// controller initialization, tests, or fullscreen polling.
  void setStartupEnabled(bool enabled, {String? executablePath}) {
    if (!Platform.isWindows) {
      throw const DesktopNativeException('当前系统不支持开机启动设置');
    }
    final command = startupCommand(executablePath ?? Platform.resolvedExecutable);
    using((arena) {
      final handle = arena<Pointer>();
      final path = PCWSTR(_runKey.toNativeUtf16(allocator: arena));
      final status = enabled
          ? RegCreateKeyEx(HKEY_CURRENT_USER, path, null,
              REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, null, handle, null)
          : RegOpenKeyEx(HKEY_CURRENT_USER, path, 0, KEY_SET_VALUE, handle);
      if (!enabled && status == ERROR_FILE_NOT_FOUND) return;
      _checkRegistry(status);
      final key = HKEY(handle.value);
      try {
        final name = PCWSTR(_startupName.toNativeUtf16(allocator: arena));
        if (enabled) {
          final data = command.toNativeUtf16(allocator: arena);
          _checkRegistry(RegSetValueEx(
            key, name, REG_SZ, data.cast<Uint8>(),
            (command.codeUnits.length + 1) * 2,
          ));
        } else {
          final result = RegDeleteValue(key, name);
          if (result != ERROR_FILE_NOT_FOUND) _checkRegistry(result);
        }
      } finally {
        RegCloseKey(key);
      }
    });
  }

  static void _checkRegistry(WIN32_ERROR result) {
    if (result != ERROR_SUCCESS) {
      throw const DesktopNativeException('开机启动设置未完成，请重试');
    }
  }
}

/// Quotes the executable, rejects injection and requires an absolute EXE path.
String startupCommand(String executablePath) {
  if (executablePath.contains(RegExp('["\x00\r\n]')) ||
      !RegExp(r'^(?:[a-zA-Z]:[\\/]|\\\\[^\\]+\\[^\\]+\\)')
          .hasMatch(executablePath) ||
      !executablePath.toLowerCase().endsWith('.exe')) {
    throw const DesktopNativeException('启动程序路径无效');
  }
  return '"$executablePath"';
}

/// Same-directory atomic replacement. Unlike deleting then renaming, failure
/// leaves the previous file intact. No shell, elevation, or startup changes.
Future<void> replaceDesktopFile(String temporaryPath, String targetPath) async {
  if (!Platform.isWindows) {
    await File(temporaryPath).rename(targetPath);
    return;
  }
  using((arena) {
    final result = MoveFileEx(
      PCWSTR(temporaryPath.toNativeUtf16(allocator: arena)),
      PCWSTR(targetPath.toNativeUtf16(allocator: arena)),
      MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
    );
    if (!result.value) {
      throw const DesktopNativeException('显示设置没存上，请重试');
    }
  });
}
