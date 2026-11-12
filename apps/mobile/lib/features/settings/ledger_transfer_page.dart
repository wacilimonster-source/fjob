import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:lan_transfer/lan_transfer.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:ledger_store/ledger_store.dart';

import '../../app/providers.dart';
import '../../data/ledger_exporter.dart';
import '../../data/ledger_files.dart';
import '../ledger/ledger_controller.dart';
import 'update_controller.dart';

class LedgerTransferPage extends ConsumerStatefulWidget {
  const LedgerTransferPage({super.key});

  @override
  ConsumerState<LedgerTransferPage> createState() => _LedgerTransferPageState();
}

enum _LanPhase { idle, waiting, transferring, sent, received }

class _LedgerTransferPageState extends ConsumerState<LedgerTransferPage> {
  bool _busy = false;
  String? _message;

  LanTransferServer? _lanServer;
  StreamSubscription<LanServerEvent>? _lanEvents;
  LanTransferMode? _lanMode;
  _LanPhase _lanPhase = _LanPhase.idle;
  String? _lanAddress;
  String? _lanCode;
  String? _lanError;
  bool _lanStarting = false;
  bool _importingIncoming = false;
  LedgerBundle? _incomingBundle;
  String? _incomingFileName;

  @override
  void dispose() {
    unawaited(_lanEvents?.cancel());
    unawaited(_lanServer?.stop());
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on RevisionConflictException {
      if (mounted) setState(() => _message = '账本已更新，请重新选择文件并核对摘要。');
    } on FormatException {
      if (mounted) setState(() => _message = '账本包格式、字段或校验和不正确，未更改当前账本。');
    } on Object {
      if (mounted) {
        setState(() => _message = '操作未完成。较旧修订或冲突不能覆盖本机，请核对文件后重试。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runExport(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on LedgerFileSaveException catch (error) {
      if (mounted) setState(() => _message = '导出未完成：${error.message}。');
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = '导出未完成：${error.code}。');
    } on Object {
      if (mounted) {
        setState(() => _message = '导出未完成；账本未改变，请重试。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Starts a one-shot encrypted LAN session. The phone hosts; the PC joins
  /// with the address/code shown on this screen.
  Future<void> _startLan(LanTransferMode mode) async {
    if (_lanStarting || _lanServer != null) return;
    final ledger = ref.read(effectiveLedgerProvider).value;
    if (ledger == null || !ledger.isConfigured) {
      setState(() => _lanError = '请先完成账本配置再使用局域网互传。');
      return;
    }
    setState(() {
      _lanStarting = true;
      _lanError = null;
      _lanMode = mode;
    });
    try {
      final server = LanTransferServer(
        mode: mode,
        device: 'android',
        onPull: () async {
          if (mounted) setState(() => _lanPhase = _LanPhase.transferring);
          final repository = await ref.read(ledgerRepositoryProvider.future);
          final now = ref.read(clockProvider).nowUtc();
          final bundle = await repository.exportBundle(
            exportedAt: now,
            appVersion: ref.read(appVersionProvider).value ?? '0.1.13',
            platform: 'android',
          );
          return LanPullPayload(
            fileName: 'fjob-${now.toIso8601String().substring(0, 10)}.fjob',
            bytes: Uint8List.fromList(utf8.encode(bundle.encode())),
          );
        },
        onPush: (fileName, bytes) async {
          if (bytes.length > LedgerBundle.maxBytes) {
            throw const FormatException('文件过大');
          }
          final bundle = LedgerBundle.decode(utf8.decode(bytes));
          _incomingBundle = bundle;
          _incomingFileName = fileName;
          if (mounted) setState(() => _lanPhase = _LanPhase.received);
        },
      );
      _lanEvents = server.events.listen(_onLanEvent);
      await server.start();
      if (!mounted) {
        await server.stop();
        return;
      }
      setState(() {
        _lanServer = server;
        _lanAddress = server.address;
        _lanCode = LanTransferCode.format(server.pairingCode);
        _lanPhase = _LanPhase.waiting;
      });
    } on LanTransferException catch (error) {
      if (mounted) setState(() => _lanError = error.message);
    } on Object {
      if (mounted) {
        setState(() => _lanError = '无法启动局域网互传，请确认手机已连接 Wi-Fi。');
      }
    } finally {
      if (_lanServer == null) {
        await _lanEvents?.cancel();
        _lanEvents = null;
        if (mounted) setState(() => _lanPhase = _LanPhase.idle);
      }
      if (mounted) setState(() => _lanStarting = false);
    }
  }

  void _onLanEvent(LanServerEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case LanServerEventType.paired:
        setState(() => _lanPhase = _LanPhase.transferring);
      case LanServerEventType.pulled:
        setState(() => _lanPhase = _LanPhase.sent);
      case LanServerEventType.pushed:
        setState(() => _lanPhase = _LanPhase.received);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_confirmIncoming());
        });
      case LanServerEventType.failed:
        setState(() => _lanError = event.message ?? '互传失败，请重试。');
      case LanServerEventType.stopped:
        if (_lanPhase == _LanPhase.waiting ||
            _lanPhase == _LanPhase.transferring) {
          setState(() => _lanPhase = _LanPhase.idle);
        }
      case LanServerEventType.listening:
        break;
    }
  }

  Future<void> _confirmIncoming() async {
    final bundle = _incomingBundle;
    if (bundle == null || _importingIncoming) return;
    setState(() => _importingIncoming = true);
    try {
      final current = ref.read(effectiveLedgerProvider).value;
      final currentRevision = current?.settings.ledgerRevision ?? 0;
      if (!mounted) return;
      final mode = await showDialog<LedgerImportMode>(
        context: context,
        builder: (context) => LedgerImportDialog(
          bundle: bundle,
          fileName: _incomingFileName ?? 'fjob-lan.fjob',
          currentRevision: currentRevision,
        ),
      );
      if (mode == null) {
        if (mounted) setState(() => _message = '已放弃导入电脑发来的账本。');
        return;
      }
      await ref.read(ledgerControllerProvider.notifier).importBundle(
            bundle,
            expectedRevision: currentRevision,
            mode: mode,
          );
      if (mounted) {
        setState(() => _message = '已从电脑接收并导入账本；导入前的账本已备份。');
      }
    } on RevisionConflictException {
      if (mounted) setState(() => _message = '账本已更新，请让电脑重新发送。');
    } on FormatException {
      if (mounted) {
        setState(() => _message = '收到的账本格式或校验和不正确，当前账本未改变。');
      }
    } on Object {
      if (mounted) setState(() => _message = '导入未完成，当前账本未被部分写入。');
    } finally {
      if (mounted) setState(() => _importingIncoming = false);
      await _stopLan();
    }
  }

  Future<void> _stopLan() async {
    final server = _lanServer;
    final subscription = _lanEvents;
    _lanServer = null;
    _lanEvents = null;
    await subscription?.cancel();
    await server?.stop();
    if (!mounted) return;
    setState(() {
      _lanPhase = _LanPhase.idle;
      _lanAddress = null;
      _lanCode = null;
      _lanMode = null;
      _lanError = null;
      _incomingBundle = null;
      _incomingFileName = null;
    });
  }

  String get _lanStatusText {
    if (_lanError != null) return _lanError!;
    return switch (_lanPhase) {
      _LanPhase.idle => '',
      _LanPhase.waiting => _lanMode == LanTransferMode.send
          ? '等待电脑输入地址和配对码…'
          : '等待电脑发送账本；收到后请在这里核对并导入。',
      _LanPhase.transferring => '正在传输，请勿关闭页面…',
      _LanPhase.sent => '已发送到电脑；电脑端会显示导入预览。',
      _LanPhase.received => '已收到电脑发来的账本，正在等待你核对导入…',
    };
  }

  /// Both export buttons share the same confirmation and bundle so the two
  /// paths can never produce different ledger revisions.
  Future<({String fileName, Uint8List bytes})?> _prepareExport({
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出敏感账本数据？'),
        content: const Text('文件包含工资、持仓、房租和贷款信息，不含行情缓存。'
            '本版为未加密文件，校验和仅用于检查完整性，请妥善保管。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel)),
        ],
      ),
    );
    if (confirmed != true) return null;
    final repository = await ref.read(ledgerRepositoryProvider.future);
    final now = ref.read(clockProvider).nowUtc();
    final bundle = await repository.exportBundle(
      exportedAt: now,
      appVersion: ref.read(appVersionProvider).value ?? '0.1.13',
      platform: 'android',
    );
    return (
      fileName: 'fjob-${now.toIso8601String().substring(0, 10)}.fjob',
      bytes: Uint8List.fromList(utf8.encode(bundle.encode())),
    );
  }

  Future<void> _export() => _runExport(() async {
        final prepared = await _prepareExport(confirmLabel: '选择保存位置');
        if (prepared == null) return;
        final result = await ref.read(ledgerExporterProvider).export(
              fileName: prepared.fileName,
              bytes: prepared.bytes,
            );
        if (!mounted) return;
        switch (result.target) {
          case LedgerExportTarget.picked:
            setState(() => _message = '账本已导出；可在电脑端选择此 .fjob 文件导入。');
          case LedgerExportTarget.downloads:
            setState(() {
              _message = '系统保存对话框不可用，已保存到 ${result.path}；'
                  '可在电脑端从下载目录选择此文件导入。';
            });
          case LedgerExportTarget.cancelled:
            break;
        }
      });

  Future<void> _saveToDownloads() => _runExport(() async {
        final prepared = await _prepareExport(confirmLabel: '保存到下载目录');
        if (prepared == null) return;
        final path = await ref.read(ledgerExporterProvider).saveToDownloads(
              fileName: prepared.fileName,
              bytes: prepared.bytes,
            );
        if (mounted) {
          setState(() {
            _message = '账本已保存到 $path；可在电脑端从下载目录选择此文件导入。';
          });
        }
      });

  Future<void> _import() => _run(() async {
        final file = await FilePicker.pickFile(dialogTitle: '选择 .fjob 账本文件');
        if (file == null) return;
        final length = await file.length();
        if (length != null && length > 16 * 1024 * 1024) {
          throw const FormatException('文件过大');
        }
        final buffer = BytesBuilder(copy: false);
        await for (final chunk in file.readAsByteStream()) {
          if (buffer.length + chunk.length > 16 * 1024 * 1024) {
            throw const FormatException('文件过大');
          }
          buffer.add(chunk);
        }
        final bundle = LedgerBundle.decode(utf8.decode(buffer.takeBytes()));
        final repository = await ref.read(ledgerRepositoryProvider.future);
        final current = await repository.read();
        final expectedRevision = current.settings.ledgerRevision;
        if (!mounted) return;
        final mode = await showDialog<LedgerImportMode>(
          context: context,
          builder: (context) => LedgerImportDialog(
            bundle: bundle,
            fileName: file.name,
            currentRevision: expectedRevision,
          ),
        );
        if (mode == null) return;
        await ref.read(ledgerControllerProvider.notifier).importBundle(
              bundle,
              expectedRevision: expectedRevision,
              mode: mode,
            );
        if (mounted) setState(() => _message = '账本已导入；导入前的账本已保存在本机备份中。');
      });

  @override
  Widget build(BuildContext context) {
    final sample = ref.watch(sampleModeProvider);
    final configured =
        ref.watch(effectiveLedgerProvider).value?.isConfigured ?? false;
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('手机与电脑交换账本')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const PaperCard(
              child: Text('通过 .fjob 文件手动交换同一本账。两端不会自动同步，'
                  '请以最近编辑的设备为准；同一账本的旧修订不会直接覆盖新修订。')),
          const SizedBox(height: 16),
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('同一 Wi-Fi 直传'),
                const SizedBox(height: 8),
                if (_lanServer == null && _lanPhase == _LanPhase.idle) ...[
                  Text(
                    '手机开一次性会话，电脑输入地址和配对码；账本加密传输，'
                    '不经过互联网，也不写入日志。',
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.muted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              _busy || _lanStarting || sample || !configured
                                  ? null
                                  : () => _startLan(LanTransferMode.send),
                          icon: const Icon(Icons.upload_outlined),
                          label: const Text('发送到电脑'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _busy || _lanStarting || sample || !configured
                                  ? null
                                  : () => _startLan(LanTransferMode.receive),
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('从电脑接收'),
                        ),
                      ),
                    ],
                  ),
                  if (_lanStarting)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: LinearProgressIndicator(),
                    ),
                  if (_lanError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _lanError!,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.negative,
                          height: 1.5,
                        ),
                      ),
                    ),
                ] else ...[
                  Row(
                    children: [
                      Icon(
                        _lanMode == LanTransferMode.send
                            ? Icons.upload_outlined
                            : Icons.download_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _lanMode == LanTransferMode.send ? '发送到电脑' : '从电脑接收',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    '地址  ${_lanAddress ?? ''}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    '配对码  ${_lanCode ?? ''}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _lanStatusText,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          _lanError == null ? palette.muted : palette.negative,
                      height: 1.5,
                    ),
                  ),
                  if (_lanPhase == _LanPhase.transferring)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy || _importingIncoming ? null : _stopLan,
                      child: Text(
                        _lanPhase == _LanPhase.waiting ? '取消会话' : '完成',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || sample || !configured ? null : _export,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('导出 .fjob 文件'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed:
                  _busy || sample || !configured ? null : _saveToDownloads,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('保存到下载目录'),
            ),
          ),
          Text(
            '系统保存对话框打不开时使用；文件位于「下载 / FJOB」。',
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy || sample ? null : _import,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('导入 .fjob 文件'),
          ),
          const SizedBox(height: 12),
          const Text('导入时先核对摘要，再选择替换或合并。合并只接纳无冲突的实体，'
              '不会自行覆盖双方都改过的数据。失败时整笔回滚。'),
          if (_busy)
            const Padding(
                padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Semantics(liveRegion: true, child: Text(_message!)),
            ),
          if (sample) const Text('示例模式不允许导入或导出正式账本。'),
        ],
      ),
    );
  }
}

class LedgerImportDialog extends StatefulWidget {
  const LedgerImportDialog({
    super.key,
    required this.bundle,
    required this.fileName,
    required this.currentRevision,
  });

  final LedgerBundle bundle;
  final String fileName;
  final int currentRevision;

  @override
  State<LedgerImportDialog> createState() => _LedgerImportDialogState();
}

class _LedgerImportDialogState extends State<LedgerImportDialog> {
  LedgerImportMode _mode = LedgerImportMode.replace;

  @override
  Widget build(BuildContext context) {
    final bundle = widget.bundle;
    final ledger = bundle.ledger;
    final calendar = BusinessCalendar.forZone(ledger.settings.salaryTimezone);
    final at = bundle.exportedAt;
    final snapshot = DashboardCalculator(calendar).calculate(
      ledger.toCalculationInput(calendar: calendar, nowUtc: at),
    );
    return AlertDialog(
      title: const Text('核对导入账本'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.fileName),
              Text('导出时间：${bundle.exportedAt.toIso8601String()}'),
              Text(
                  '文件修订 #${bundle.ledgerRevision} · 本机 #${widget.currentRevision}'),
              Text('到手月薪：${formatMoney(ledger.currentSalary?.monthlyNetCny)}'),
              Text('排班时区：${ledger.settings.salaryTimezone}'),
              Text(
                  '本月排班：${snapshot.monthStats == null ? '待确认' : '${formatHours(snapshot.monthStats!.paidSeconds)} 小时'}'),
              Text(
                  '资产：${ledger.holdings.where((holding) => holding.covers(at)).length} 项'),
              Text('住房：${switch (ledger.housingMode) {
                HousingMode.mortgage => '房贷',
                HousingMode.rent => '房租',
                HousingMode.none => '暂无',
              }}'),
              Text(
                  '账单月份：${ledger.bills.map((bill) => formatMonth(bill.month)).toSet().join('、')}'),
              const SizedBox(height: 12),
              DropdownButtonFormField<LedgerImportMode>(
                initialValue: _mode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '导入方式'),
                items: const [
                  DropdownMenuItem(
                      value: LedgerImportMode.replace, child: Text('替换本机账本')),
                  DropdownMenuItem(
                      value: LedgerImportMode.merge, child: Text('合并无冲突数据')),
                ],
                onChanged: (value) => setState(() => _mode = value!),
              ),
              const SizedBox(height: 12),
              const Text('导入前自动备份。金额只存本机；旧修订与冲突会明确拒绝，不会静默降级。'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _mode),
            child: const Text('确认导入')),
      ],
    );
  }
}
