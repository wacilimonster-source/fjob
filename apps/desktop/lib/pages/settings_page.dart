import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:http/http.dart' as http;
import 'package:ledger_model/ledger_model.dart';
import 'package:market_data/market_data.dart';

import '../state/providers.dart';
import '../update/update_service.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final ledger = ref.watch(effectiveLedgerProvider).value;
    final settings = ledger?.settings ?? const AppSettings();
    final client = ref.watch(marketClientProvider);
    final dataDir = ref.watch(dataDirectoryProvider);
    final sourceLabel = client is FixtureMarketClient
        ? '模拟适配器（fixture）· 未接入真实报价'
        : client is EastmoneyMarketClient
            ? '东方财富公开接口 · developmentOnly（非官方授权）'
            : '行情网关 · ${AppConfig.gatewayBaseUrl}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      children: [
        Text('设置', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 22)),
        const SizedBox(height: 16),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('关于'),
              const SizedBox(height: 8),
              _row('版本', desktopAppVersion),
              _row('平台', 'Windows x64 · 便携版'),
              _row('统计时区', settings.salaryTimezone),
              _row('账本修订', '#${settings.ledgerRevision}'),
              _row('行情来源', sourceLabel),
              _row('数据目录', dataDir),
              const SizedBox(height: 8),
              Text('个人账本保存在本机。行情请求只包含标的 ID，工资、持仓数量、成本、'
                  '租金与贷款金额不上传。界面固定浅色纸感，不跟随系统深色。',
                  style: TextStyle(fontSize: 12, color: palette.muted, height: 1.7)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _UpdateSection(),
        const SizedBox(height: 16),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('诊断与许可'),
              const SizedBox(height: 8),
              Text('日志默认不含金额、持仓、房租与贷款。角色、房车、办公室、硬币、图标与'
                  '拍肩/离场动效均来自共享 fjob_ui 包，与手机端同源。'
                  '真实行情来源的公开展示许可仍为外部依赖，发布前需关闭。',
                  style: TextStyle(fontSize: 12, color: palette.muted, height: 1.7)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 84, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF686E61)))),
            Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

/// 更新区：检查 GitHub Releases 的 desktop-v* 通道，发现新版本后下载并
/// 校验 SHA-256，再由用户确认运行安装包。请求只含仓库与版本元数据。
class _UpdateSection extends ConsumerStatefulWidget {
  const _UpdateSection();

  @override
  ConsumerState<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends ConsumerState<_UpdateSection> {
  http.Client? _httpClient;
  PcUpdateService? _service;
  bool _checking = false;
  bool _downloading = false;
  UpdateCheckResult? _result;
  String? _error;
  File? _downloaded;
  int _received = 0;
  int _total = 0;

  @override
  void dispose() {
    _httpClient?.close();
    super.dispose();
  }

  PcUpdateService get _api => _service ??= PcUpdateService(
        client: _httpClient ??= http.Client(),
      );

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
      _result = null;
      _downloaded = null;
    });
    try {
      final result = await _api.checkForUpdate(desktopAppVersion);
      if (mounted) setState(() => _result = result);
    } on UpdateException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(() => _error = '检查更新失败，请确认网络可用。');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _download() async {
    final release = _result?.latest;
    if (release == null) return;
    setState(() {
      _downloading = true;
      _error = null;
      _downloaded = null;
      _received = 0;
      _total = release.installerSize;
    });
    try {
      final file = await _api.downloadInstaller(
        release,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _received = received;
              _total = total;
            });
          }
        },
      );
      if (mounted) setState(() => _downloaded = file);
    } on UpdateException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(() => _error = '下载失败，请确认网络可用。');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _launchInstaller() async {
    final file = _downloaded;
    if (file == null) return;
    try {
      await Process.start(file.path, const [],
          mode: ProcessStartMode.detached);
    } on Object {
      if (mounted) setState(() => _error = '无法启动安装程序。');
    }
  }

  String get _progressLabel {
    const mb = 1024 * 1024;
    final received = (_received / mb).toStringAsFixed(1);
    final total = (_total / mb).toStringAsFixed(1);
    return '$received MB / $total MB';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('更新'),
          const SizedBox(height: 8),
          Text('PC 端使用独立的 desktop-v* 发布通道，与手机 APK 互不误装。'
              '安装包下载后会校验 SHA-256，校验通过才可运行。',
              style: TextStyle(fontSize: 12, color: palette.muted, height: 1.7)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _checking ? null : _check,
                icon: _checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: Text(_checking ? '正在检查…' : '检查更新'),
              ),
              if (_downloaded != null)
                FilledButton.icon(
                  onPressed: _launchInstaller,
                  icon: const Icon(Icons.install_desktop, size: 16),
                  label: const Text('运行安装程序'),
                ),
              if (_result?.hasUpdate == true && !_downloading)
                OutlinedButton.icon(
                  onPressed: _download,
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('下载安装包'),
                ),
            ],
          ),
          if (_downloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null,
              minHeight: 6,
              backgroundColor: palette.line,
              valueColor: AlwaysStoppedAnimation<Color>(palette.positive),
            ),
            const SizedBox(height: 4),
            Text(_progressLabel,
                style: TextStyle(fontSize: 11, color: palette.muted)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(fontSize: 12, color: palette.negative)),
          ],
          if (_result != null && !_downloading) ...[
            const SizedBox(height: 10),
            _resultView(_result!),
          ],
        ],
      ),
    );
  }

  Widget _resultView(UpdateCheckResult result) {
    final palette = context.palette;
    final latest = result.latest;
    if (latest == null) {
      return Text('暂时没有可用的 PC 发布版本。',
          style: TextStyle(fontSize: 12, color: palette.muted));
    }
    if (!result.hasUpdate) {
      return Text('已是最新版本（${result.currentVersion}）。',
          style: TextStyle(fontSize: 12, color: palette.muted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.new_releases_outlined,
                size: 16, color: palette.positive),
            const SizedBox(width: 6),
            Text('发现新版本 ${latest.tag}（${latest.sizeLabel}）',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
        if (latest.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 120),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.paper,
              border: Border.all(color: palette.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: Text(latest.notes.trim(),
                  style: TextStyle(fontSize: 11, color: palette.muted, height: 1.6)),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text('安装包：${latest.installerName}（SHA-256 已随发布提供）',
            style: TextStyle(fontSize: 11, color: palette.muted)),
        const SizedBox(height: 4),
        SelectableText(latest.pageUrl.toString(),
            style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
