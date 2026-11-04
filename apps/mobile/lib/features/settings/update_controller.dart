/// Update-check state machine and providers shared by the settings screen.
library;


import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/update_service.dart';

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  installed,
  error,
  unsupported,
}

final class UpdateUiState {
  const UpdateUiState({
    this.phase = UpdatePhase.idle,
    this.message,
    this.release,
    this.currentVersion,
    this.progress = 0,
    this.localPath,
    this.needsInstallPermission = false,
  });

  final UpdatePhase phase;
  final String? message;
  final AppRelease? release;
  final String? currentVersion;
  final double progress;
  final String? localPath;
  final bool needsInstallPermission;

  bool get isBusy =>
      phase == UpdatePhase.checking || phase == UpdatePhase.downloading;

  UpdateUiState copyWith({
    UpdatePhase? phase,
    Object? message = _unset,
    Object? release = _unset,
    Object? currentVersion = _unset,
    double? progress,
    Object? localPath = _unset,
    bool? needsInstallPermission,
  }) =>
      UpdateUiState(
        phase: phase ?? this.phase,
        message: identical(message, _unset) ? this.message : message as String?,
        release: identical(release, _unset)
            ? this.release
            : release as AppRelease?,
        currentVersion: identical(currentVersion, _unset)
            ? this.currentVersion
            : currentVersion as String?,
        progress: progress ?? this.progress,
        localPath:
            identical(localPath, _unset) ? this.localPath : localPath as String?,
        needsInstallPermission:
            needsInstallPermission ?? this.needsInstallPermission,
      );
}

const Object _unset = Object();

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

final updateServiceProvider = Provider<UpdateService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return UpdateService(client: client, temporaryDirectory: getTemporaryDirectory);
});

final apkInstallBridgeProvider = Provider<ApkInstallBridge>(
  (ref) => const MethodChannelApkInstallBridge(),
);

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateUiState>(UpdateController.new);

final class UpdateController extends Notifier<UpdateUiState> {
  DownloadCancelToken? _token;
  bool _disposed = false;

  @override
  UpdateUiState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _token?.cancel();
      _token = null;
    });
    return const UpdateUiState();
  }

  Future<void> check() async {
    if (state.isBusy) return;
    state = state.copyWith(
      phase: UpdatePhase.checking,
      message: '正在检查更新…',
      needsInstallPermission: false,
    );
    try {
      final info = await PackageInfo.fromPlatform();
      final result =
          await ref.read(updateServiceProvider).checkForUpdate(info.version);
      if (_disposed) return;
      state = UpdateUiState(
        phase: result.hasUpdate ? UpdatePhase.available : UpdatePhase.upToDate,
        currentVersion: info.version,
        release: result.latest,
        message: result.hasUpdate
            ? '发现新版本 ${result.latest!.version}'
            : '已是最新版本 ${info.version}',
      );
    } on UpdateException catch (error) {
      if (_disposed) return;
      state = UpdateUiState(
        phase: UpdatePhase.error,
        message: error.message,
        currentVersion: state.currentVersion,
      );
    } on Object {
      if (_disposed) return;
      state = state.copyWith(
        phase: UpdatePhase.error,
        message: '检查更新失败，请稍后再试。',
      );
    }
  }

  Future<void> downloadAndInstall() async {
    final release = state.release;
    if (release == null || state.phase == UpdatePhase.downloading) return;
    if (defaultTargetPlatform != TargetPlatform.android) {
      state = state.copyWith(
        phase: UpdatePhase.unsupported,
        message: 'iOS 版本通过 TestFlight 更新，App 内不直接安装安装包。',
      );
      return;
    }
    final bridge = ref.read(apkInstallBridgeProvider);
    if (!await bridge.canRequestInstall()) {
      if (_disposed) return;
      state = state.copyWith(
        phase: UpdatePhase.available,
        needsInstallPermission: true,
        message: '需要先允许本应用安装未知应用。',
      );
      return;
    }
    final token = DownloadCancelToken();
    _token = token;
    state = state.copyWith(
      phase: UpdatePhase.downloading,
      progress: 0,
      message: '正在下载 ${release.apkName}…',
      needsInstallPermission: false,
    );
    try {
      final file = await ref
          .read(updateServiceProvider)
          .downloadApk(
            release,
            cancelToken: token,
            onProgress: (progress) {
              if (_disposed) return;
              state = state.copyWith(progress: progress);
            },
          );
      if (_disposed) return;
      state = state.copyWith(
        phase: UpdatePhase.installing,
        message: '安装包已校验，正在打开安装器…',
        localPath: file.path,
      );
      final opened = await bridge.installApk(file.path);
      if (_disposed) return;
      state = state.copyWith(
        phase: opened ? UpdatePhase.installed : UpdatePhase.error,
        message: opened
            ? '安装器已打开，请按系统提示完成安装。'
            : '无法打开安装器，请检查“安装未知应用”权限。',
      );
    } on UpdateException catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        phase: token.isCancelled ? UpdatePhase.available : UpdatePhase.error,
        message: error.message,
        progress: 0,
      );
    } on Object {
      if (_disposed) return;
      state = state.copyWith(
        phase: UpdatePhase.error,
        message: '下载失败，请稍后重试。',
        progress: 0,
      );
    } finally {
      if (identical(_token, token)) _token = null;
    }
  }

  Future<void> openInstallPermissionSettings() async {
    await ref.read(apkInstallBridgeProvider).openInstallPermissionSettings();
    if (_disposed) return;
    state = state.copyWith(
      needsInstallPermission: false,
      message: '授权后请再次点击“下载并安装”。',
    );
  }

  void cancelDownload() {
    _token?.cancel();
  }
}
