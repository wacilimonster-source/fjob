import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:ledger_store/ledger_store.dart';

import '../../app/providers.dart';
import '../ledger/ledger_controller.dart';
import 'update_controller.dart';

class LedgerTransferPage extends ConsumerStatefulWidget {
  const LedgerTransferPage({super.key});

  @override
  ConsumerState<LedgerTransferPage> createState() => _LedgerTransferPageState();
}

class _LedgerTransferPageState extends ConsumerState<LedgerTransferPage> {
  bool _busy = false;
  String? _message;

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

  Future<void> _export() => _run(() async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('导出敏感账本数据？'),
            content: const Text('文件包含工资、持仓、房租和贷款信息，不含行情缓存。'
                '本版为未加密文件，校验和仅用于检查完整性，请妥善保管。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('选择保存位置')),
            ],
          ),
        );
        if (confirmed != true) return;
        final repository = await ref.read(ledgerRepositoryProvider.future);
        final now = ref.read(clockProvider).nowUtc();
        final bundle = await repository.exportBundle(
          exportedAt: now,
          appVersion: ref.read(appVersionProvider).value ?? '0.1.10',
          platform: 'android',
        );
        final uri = await FilePicker.saveFile(
          fileName: 'fjob-${now.toIso8601String().substring(0, 10)}.fjob',
          bytes: Uint8List.fromList(utf8.encode(bundle.encode())),
          dialogTitle: '保存账本文件',
        );
        if (mounted && uri != null) {
          setState(() => _message = '账本已导出；可在电脑端选择此 .fjob 文件导入。');
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
    final configured = ref.watch(effectiveLedgerProvider).value?.isConfigured ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('手机与电脑交换账本')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const PaperCard(child: Text('通过 .fjob 文件手动交换同一本账。两端不会自动同步，'
              '请以最近编辑的设备为准；同一账本的旧修订不会直接覆盖新修订。')),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || sample || !configured ? null : _export,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('导出 .fjob 文件'),
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
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          if (_message != null) Padding(
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
              Text('文件修订 #${bundle.ledgerRevision} · 本机 #${widget.currentRevision}'),
              Text('到手月薪：${formatMoney(ledger.currentSalary?.monthlyNetCny)}'),
              Text('排班时区：${ledger.settings.salaryTimezone}'),
              Text('本月排班：${snapshot.monthStats == null ? '待确认' : '${formatHours(snapshot.monthStats!.paidSeconds)} 小时'}'),
              Text('资产：${ledger.holdings.where((holding) => holding.covers(at)).length} 项'),
              Text('住房：${switch (ledger.housingMode) {
                HousingMode.mortgage => '房贷',
                HousingMode.rent => '房租',
                HousingMode.none => '暂无',
              }}'),
              Text('账单月份：${ledger.bills.map((bill) => formatMonth(bill.month)).toSet().join('、')}'),
              const SizedBox(height: 12),
              DropdownButtonFormField<LedgerImportMode>(
                initialValue: _mode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '导入方式'),
                items: const [
                  DropdownMenuItem(value: LedgerImportMode.replace, child: Text('替换本机账本')),
                  DropdownMenuItem(value: LedgerImportMode.merge, child: Text('合并无冲突数据')),
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, _mode), child: const Text('确认导入')),
      ],
    );
  }
}
