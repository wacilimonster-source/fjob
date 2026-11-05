/// Add/edit sheet for one A-share holding.
///
/// The market is inferred from the six-digit code and the name is looked up
/// through the configured market client. The sheet is scrollable so the
/// keyboard cannot hide the name or cost fields on short screens.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/instrument.dart';
import '../../domain/setup_draft.dart';

Future<HoldingDraft?> showHoldingEditor(
  BuildContext context, {
  HoldingDraft? initial,
}) {
  return showModalBottomSheet<HoldingDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.palette.panel,
    builder: (context) => _HoldingSheet(initial: initial),
  );
}

class _HoldingSheet extends ConsumerStatefulWidget {
  const _HoldingSheet({this.initial});

  final HoldingDraft? initial;

  @override
  ConsumerState<_HoldingSheet> createState() => _HoldingSheetState();
}

class _HoldingSheetState extends ConsumerState<_HoldingSheet> {
  late final TextEditingController _code =
      TextEditingController(text: widget.initial?.code ?? '');
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _quantity =
      TextEditingController(text: widget.initial?.quantityText ?? '');
  late final TextEditingController _cost =
      TextEditingController(text: widget.initial?.costText ?? '');
  late StockMarket? _market =
      widget.initial?.market ?? marketForCode(widget.initial?.code ?? '');
  Timer? _debounce;
  bool _looking = false;
  String? _lookupMessage;
  String? _autoName = '';
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _code.dispose();
    _name.dispose();
    _quantity.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _onCodeChanged(String value) {
    _debounce?.cancel();
    final inferred = marketForCode(value.trim());
    setState(() {
      _market = inferred;
      _error = null;
      _lookupMessage = null;
    });
    if (value.trim().length != 6 || inferred == null) return;
    setState(() => _looking = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      await _lookup(value.trim());
    });
  }

  Future<void> _lookup(String code) async {
    try {
      final results = await ref.read(marketClientProvider).searchInstruments(code);
      if (!mounted) return;
      InstrumentInfo? match;
      for (final result in results) {
        if (result.code == code) {
          match = result;
          break;
        }
      }
      if (match == null) {
        setState(() {
          _looking = false;
          _lookupMessage = '未查到名称，可手动填写。保存后标记待联网确认。';
        });
        return;
      }
      final name = match.name.trim();
      if (name.isNotEmpty &&
          (_name.text.trim().isEmpty || _name.text == _autoName)) {
        _name.text = name;
        _autoName = name;
      }
      setState(() {
        _market = match!.market;
        _looking = false;
        _lookupMessage = name.isEmpty
            ? '已识别为${match.market.label}市，名称待联网确认，可手动填写。'
            : '已识别：${match.market.label}市 · $name';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _looking = false;
        _lookupMessage = '名称查询暂时不可用，可手动填写。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final market = _market;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                widget.initial == null ? '添加A股持仓' : '修改持仓',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            '输入 6 位代码后自动识别市场并尝试获取名称。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('holding-code'),
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '证券代码',
              hintText: '例如 000001',
              counterText: '',
            ),
            onChanged: _onCodeChanged,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.soft,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  market == null ? '市场待识别' : '${market.label}市',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              if (_looking)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _lookupMessage ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('holding-name'),
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '名称（自动获取，可修改）',
              hintText: '例如 平安银行',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('holding-quantity'),
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '持仓 / 股'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('holding-cost'),
                  controller: _cost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(labelText: '成本 / 元'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: palette.negative, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              final code = _code.text.trim();
              if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                setState(() => _error = '证券代码是 6 位数字，请核对。');
                return;
              }
              final inferred = marketForCode(code);
              if (inferred == null) {
                setState(() => _error = '暂不认识这个代码对应的市场，请核对。');
                return;
              }
              if (_quantity.text.trim().isEmpty || _cost.text.trim().isEmpty) {
                setState(() => _error = '请填写股数和每股成本。');
                return;
              }
              Navigator.of(context).pop(
                HoldingDraft(
                  market: _market ?? inferred,
                  code: code,
                  name: _name.text.trim(),
                  quantityText: _quantity.text.trim(),
                  costText: _cost.text.trim(),
                ),
              );
            },
            child: const Text('保存持仓'),
          ),
        ],
      ),
    );
  }
}
