import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:lan_transfer/lan_transfer.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:ledger_store/ledger_store.dart';

import '../state/ledger_controller.dart';
import '../state/providers.dart';
import '../widgets/lan_input_dialog.dart';

class DataPage extends ConsumerStatefulWidget {
  const DataPage({super.key});

  @override
  ConsumerState<DataPage> createState() => _DataPageState();
}

class _DataPageState extends ConsumerState<DataPage> {
  bool _busy = false;
  String? _message;
  List<LedgerBackup> _backups = const [];

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    try {
      final backups = await ref
          .read(ledgerControllerProvider.notifier)
          .listBackups();
      if (mounted) setState(() => _backups = backups);
    } on Object {
      // Backup listing is best effort; the ledger itself remains usable.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      await _loadBackups();
    } on OlderLedgerRevisionException catch (e) {
      _fail('文件修订 #${e.incoming} 较旧，已保留本机 #${e.current}。');
    } on LedgerMergeConflictException {
      _fail('合并遇到双方都改过的数据，未自动覆盖；请改用替换或先在来源端整理。');
    } on RevisionConflictException {
      _fail('账本已更新，请重新核对后再试。');
    } on FormatException {
      _fail('这个账本包无法读取（格式、字段或校验和不正确），当前账本没有变化。');
    } on LedgerActionException catch (e) {
      _fail(e.message);
    } on LanTransferException catch (e) {
      _fail(e.message);
    } on Object {
      _fail('操作未完成，当前账本未被部分写入；请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _message = message);
  }

  Future<void> _export() => _run(() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出敏感账本数据？'),
        content: const Text(
          '文件包含工资、持仓、房租和贷款信息，不含行情缓存。'
          '本版为未加密文件，校验和仅用于检查完整性，请妥善保管。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('选择保存位置'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final bundle = await ref
        .read(ledgerControllerProvider.notifier)
        .exportBundle();
    final uri = await FilePicker.saveFile(
      fileName:
          'fjob-${bundle.exportedAt.toIso8601String().substring(0, 10)}.fjob',
      bytes: Uint8List.fromList(utf8.encode(bundle.encode())),
      dialogTitle: '保存账本文件',
    );
    if (mounted && uri != null) {
      setState(() => _message = '账本已导出，可在其他设备导入此 .fjob 文件。');
    }
  });

  Future<void> _import() => _run(() async {
    final file = await FilePicker.pickFile(dialogTitle: '选择 .fjob 账本文件');
    if (file == null) return;
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (buffer.length + chunk.length > LedgerBundle.maxBytes) {
        throw const FormatException('文件过大');
      }
      buffer.add(chunk);
    }
    final bundle = LedgerBundle.decode(utf8.decode(buffer.takeBytes()));
    final current = ref.read(effectiveLedgerProvider).value;
    final currentRevision = current?.settings.ledgerRevision ?? 0;
    if (!mounted) return;
    final mode = await showDialog<LedgerImportMode>(
      context: context,
      builder: (context) => _ImportDialog(
        bundle: bundle,
        fileName: file.name,
        currentRevision: currentRevision,
      ),
    );
    if (mode == null) return;
    await ref
        .read(ledgerControllerProvider.notifier)
        .importBundle(bundle, mode: mode);
    if (mounted) {
      setState(() => _message = '账本已导入；导入前的账本已保存在本机备份中。');
    }
  });

  Future<void> _receiveOverLan() => _run(() async {
    final input = await _askLanInput(
      title: '从手机接收账本',
      actionLabel: '连接并接收',
      hint: '在手机端选择「发送到电脑」，把屏幕上的地址和配对码填到这里。',
    );
    if (input == null) return;
    final client = LanTransferClient();
    try {
      final payload = await client.pull(
        address: input.address,
        code: input.code,
      );
      if (payload.bytes.length > LedgerBundle.maxBytes) {
        throw const FormatException('文件过大');
      }
      final bundle = LedgerBundle.decode(utf8.decode(payload.bytes));
      final currentRevision =
          ref.read(effectiveLedgerProvider).value?.settings.ledgerRevision ?? 0;
      if (!mounted) return;
      final mode = await showDialog<LedgerImportMode>(
        context: context,
        builder: (context) => _ImportDialog(
          bundle: bundle,
          fileName: payload.fileName,
          currentRevision: currentRevision,
        ),
      );
      if (mode == null) return;
      await ref
          .read(ledgerControllerProvider.notifier)
          .importBundle(bundle, mode: mode);
      if (mounted) {
        setState(() => _message = '已从手机接收并导入账本；导入前的账本已备份。');
      }
    } finally {
      client.close();
    }
  });

  Future<void> _sendOverLan() => _run(() async {
    final input = await _askLanInput(
      title: '发送账本到手机',
      actionLabel: '连接并发送',
      hint: '在手机端选择「从电脑接收」，把屏幕上的地址和配对码填到这里。',
    );
    if (input == null) return;
    final bundle = await ref
        .read(ledgerControllerProvider.notifier)
        .exportBundle();
    final bytes = Uint8List.fromList(utf8.encode(bundle.encode()));
    final fileName =
        'fjob-${bundle.exportedAt.toIso8601String().substring(0, 10)}.fjob';
    final client = LanTransferClient();
    try {
      await client.push(
        address: input.address,
        code: input.code,
        fileName: fileName,
        bytes: bytes,
      );
      if (mounted) {
        setState(() => _message = '账本已发送到手机，请在手机上确认导入。');
      }
    } finally {
      client.close();
    }
  });

  Future<LanInput?> _askLanInput({
    required String title,
    required String actionLabel,
    required String hint,
  }) => showDialog<LanInput>(
    context: context,
    builder: (context) =>
        LanInputDialog(title: title, actionLabel: actionLabel, hint: hint),
  );

  Future<void> _clear() => _run(() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空账本？'),
        content: const Text('清空后配置、草稿、缓存和固定窗快照都会失效，且不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(ledgerControllerProvider.notifier).clearLedger();
    if (mounted) setState(() => _message = '账本已清空。');
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sample = ref.watch(sampleModeProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      children: [
        Text(
          '数据',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 4),
        Text(
          '手机 ↔ 电脑通过 .fjob 文件或同一 Wi-Fi 直传交换同一本账；两端不会自动同步。',
          style: TextStyle(fontSize: 12, color: palette.muted),
        ),
        const SizedBox(height: 16),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('导入 / 导出'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy || sample ? null : _export,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('导出 .fjob'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy || sample ? null : _import,
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('导入 .fjob'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '导入前自动备份；较旧修订与冲突会明确拒绝，不会静默降级。'
                '金额只存本机，行情请求只发送标的 ID。',
                style: TextStyle(
                  fontSize: 12,
                  color: palette.muted,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('同一 Wi-Fi 直传'),
              const SizedBox(height: 10),
              Text(
                '手机打开「发送到电脑/从电脑接收」并显示地址与配对码；'
                '账本加密直传，不经过互联网。',
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
                    child: OutlinedButton.icon(
                      onPressed: _busy || sample ? null : _receiveOverLan,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('从手机接收'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy || sample ? null : _sendOverLan,
                      icon: const Icon(Icons.upload_outlined),
                      label: const Text('发送到手机'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PaperCard(
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('本机备份（最近 5 份）'),
                const SizedBox(height: 8),
                if (_backups.isEmpty)
                  Text(
                    '暂无备份。导入或恢复前会自动创建。',
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  )
                else
                  for (final backup in _backups)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        '修订 #${backup.ledgerRevision}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${backup.createdAt.toLocal().toString().substring(0, 19)} · ${backup.ledgerId.substring(0, 8)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: TextButton(
                        onPressed: _busy || sample
                            ? null
                            : () => _run(() async {
                                await ref
                                    .read(ledgerControllerProvider.notifier)
                                    .restoreBackup(backup.id);
                                if (mounted) {
                                  setState(
                                    () => _message = '已从备份恢复；恢复前的账本也已备份。',
                                  );
                                }
                              }),
                        child: const Text('恢复'),
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(
                '危险操作',
                trailing: Icon(
                  Icons.warning_amber,
                  size: 16,
                  color: palette.negative,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy || sample ? null : _clear,
                icon: Icon(Icons.delete_outline, color: palette.negative),
                label: Text(
                  '清空本地账本',
                  style: TextStyle(color: palette.negative),
                ),
              ),
            ],
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: PaperCard(
              color: palette.soft,
              child: Semantics(liveRegion: true, child: Text(_message!)),
            ),
          ),
        if (sample)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('示例模式不允许导入/导出/清空正式账本。'),
          ),
      ],
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({
    required this.bundle,
    required this.fileName,
    required this.currentRevision,
  });
  final LedgerBundle bundle;
  final String fileName;
  final int currentRevision;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  LedgerImportMode _mode = LedgerImportMode.replace;

  @override
  Widget build(BuildContext context) {
    final bundle = widget.bundle;
    final ledger = bundle.ledger;
    final calendar = BusinessCalendar.forZone(ledger.settings.salaryTimezone);
    final snapshot = DashboardCalculator(calendar).calculate(
      ledger.toCalculationInput(calendar: calendar, nowUtc: bundle.exportedAt),
    );
    return AlertDialog(
      title: const Text('核对导入账本'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.fileName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _row('导出时间', bundle.exportedAt.toIso8601String()),
              _row(
                '文件修订',
                '#${bundle.ledgerRevision} · 本机 #${widget.currentRevision}',
              ),
              _row(
                '来源平台',
                bundle.toJson()['app']['platform'] as String? ?? '未知',
              ),
              _row('到手月薪', formatMoney(ledger.currentSalary?.monthlyNetCny)),
              _row('排班时区', ledger.settings.salaryTimezone),
              _row(
                '本月排班',
                snapshot.monthStats == null
                    ? '待确认'
                    : '${formatHours(snapshot.monthStats!.paidSeconds)} 小时',
              ),
              _row(
                '资产数量',
                '${ledger.holdings.where((h) => h.covers(bundle.exportedAt)).length} 项',
              ),
              _row('住房方式', switch (ledger.housingMode) {
                HousingMode.mortgage => '房贷',
                HousingMode.rent => '房租',
                HousingMode.none => '暂无',
              }),
              _row(
                '账单月份',
                ledger.bills.map((b) => formatMonth(b.month)).toSet().join('、'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LedgerImportMode>(
                initialValue: _mode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '导入方式'),
                items: const [
                  DropdownMenuItem(
                    value: LedgerImportMode.replace,
                    child: Text('替换本机账本'),
                  ),
                  DropdownMenuItem(
                    value: LedgerImportMode.merge,
                    child: Text('合并无冲突数据'),
                  ),
                ],
                onChanged: (value) => setState(() => _mode = value!),
              ),
              const SizedBox(height: 12),
              const Text(
                '导入前自动备份。合并只接纳无冲突的实体，不会自行覆盖双方都改过的数据。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _mode),
          child: const Text('确认导入'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF686E61)),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}
