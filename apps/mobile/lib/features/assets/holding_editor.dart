/// Add/edit sheet for one A-share or domestic open-ended fund holding.
///
/// Stocks infer the exchange from the six-digit code. Funds never infer a
/// market: the code is a fund directory key and the name/eligibility lookup is
/// debounced. A late lookup result can never overwrite a newer code or a name
/// the user typed manually.
library;

import 'dart:async';

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';

Future<HoldingDraft?> showHoldingEditor(
  BuildContext context, {
  HoldingDraft? initial,
  HoldingKind kind = HoldingKind.stock,
}) {
  return showModalBottomSheet<HoldingDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.palette.panel,
    builder: (context) => _HoldingSheet(initial: initial, kind: kind),
  );
}

class _HoldingSheet extends ConsumerStatefulWidget {
  const _HoldingSheet({this.initial, required this.kind});

  final HoldingDraft? initial;
  final HoldingKind kind;

  @override
  ConsumerState<_HoldingSheet> createState() => _HoldingSheetState();
}

class _HoldingSheetState extends ConsumerState<_HoldingSheet> {
  late final HoldingKind _kind = widget.initial?.kind ?? widget.kind;
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
  bool _lookupFailed = false;
  String? _lookupMessage;
  String? _autoName = '';
  String? _error;
  FundEligibility _eligibility = FundEligibility.unknown;
  String _eligibilityReason = '';
  int _lookupGeneration = 0;

  bool get _isFund => _kind == HoldingKind.fund;

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
    _lookupGeneration++;
    final code = value.trim();
    final inferred = _isFund ? null : marketForCode(code);
    setState(() {
      if (!_isFund) _market = inferred;
      _error = null;
      _lookupMessage = null;
      _lookupFailed = false;
      _eligibility = FundEligibility.unknown;
      _eligibilityReason = '';
    });
    // A name that was auto-filled for the old code must not label the new one;
    // a manually typed name is always preserved.
    if (_name.text.trim().isEmpty || _name.text == _autoName) {
      _name.clear();
      _autoName = '';
    }
    if (code.length != 6 || (!_isFund && inferred == null)) return;
    setState(() => _looking = true);
    final generation = _lookupGeneration;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      await _lookup(code, generation);
    });
  }

  Future<void> _lookup(String code, int generation) async {
    try {
      if (_isFund) {
        final info = await ref.read(marketClientProvider).fetchFundInfo(code);
        if (!_isCurrent(code, generation)) return;
        _applyFundInfo(code, info);
        return;
      }
      final results = await ref
          .read(marketClientProvider)
          .searchInstruments(code);
      if (!_isCurrent(code, generation)) return;
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
          _lookupFailed = true;
          _lookupMessage = '未查到名称，可手动填写。保存后标记待联网确认。';
        });
        return;
      }
      final name = match.name.trim();
      _maybeAutofillName(name);
      setState(() {
        _market = match!.market;
        _looking = false;
        _lookupFailed = name.isEmpty;
        _lookupMessage = name.isEmpty
            ? '已识别为${match.market.label}市，名称待联网确认，可手动填写。'
            : '已识别：${match.market.label}市 · $name';
      });
    } on Object {
      if (!_isCurrent(code, generation)) return;
      setState(() {
        _looking = false;
        _lookupFailed = true;
        _lookupMessage = _isFund
            ? '名称查询暂时不可用，可手动填写。保存后标记待联网确认。'
            : '名称查询暂时不可用，可手动填写。';
      });
    }
  }

  bool _isCurrent(String code, int generation) =>
      mounted &&
      generation == _lookupGeneration &&
      _code.text.trim() == code;

  void _applyFundInfo(String code, FundInfo? info) {
    if (info == null) {
      setState(() {
        _looking = false;
        _lookupFailed = true;
        _eligibility = FundEligibility.unknown;
        _eligibilityReason = '目录未收录';
        _lookupMessage = '目录里暂时没有这个基金，可先保存并待联网确认。';
      });
      return;
    }
    final name = info.name.trim();
    _maybeAutofillName(name);
    setState(() {
      _looking = false;
      _eligibility = info.eligibility;
      _eligibilityReason = info.reason;
      _lookupFailed = name.isEmpty || !info.supported;
      _lookupMessage = switch (info.eligibility) {
        FundEligibility.supported =>
          name.isEmpty ? '已识别为场外基金，名称待联网确认。' : '已识别：$name',
        FundEligibility.unsupported =>
          '不支持按普通场外基金计算：${info.reason}',
        FundEligibility.unknown =>
          '暂无法确认品种或持有口径：${info.reason}，保存后待联网确认。',
      };
    });
  }

  void _maybeAutofillName(String name) {
    if (name.isEmpty) return;
    if (_name.text.trim().isEmpty || _name.text == _autoName) {
      _name.text = name;
      _autoName = name;
    }
  }

  void _save() {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error =
          _isFund ? '基金代码是 6 位数字，请核对。' : '证券代码是 6 位数字，请核对。');
      return;
    }
    final quantityText = _quantity.text.trim();
    final costText = _cost.text.trim();
    if (quantityText.isEmpty || costText.isEmpty) {
      setState(() => _error =
          _isFund ? '请填写持有份额和单位成本。' : '请填写股数和每股成本。');
      return;
    }
    if (_isFund) {
      if (_eligibility == FundEligibility.unsupported) {
        setState(() => _error =
            '该基金暂不支持：$_eligibilityReason');
        return;
      }
      final quantity = _decimal(quantityText, maxScale: 4);
      if (quantity == null ||
          quantity.isNegative ||
          quantity > Rational.parse('10000000')) {
        setState(() => _error = '份额需要是 0 到 10,000,000 之间的数字，最多四位小数。');
        return;
      }
      final cost = _decimal(costText, maxScale: 4);
      if (cost == null || cost.isNegative || cost > Rational.parse('100000')) {
        setState(() => _error = '单位成本需要是 0 到 100,000 之间的数字，最多四位小数。');
        return;
      }
      final name = _name.text.trim();
      Navigator.of(context).pop(
        HoldingDraft(
          kind: HoldingKind.fund,
          code: code,
          name: name,
          quantityText: quantityText,
          costText: costText,
          pendingQuote: name.isEmpty ||
              _lookupFailed ||
              _eligibility != FundEligibility.supported,
        ),
      );
      return;
    }

    final inferred = marketForCode(code);
    if (inferred == null) {
      setState(() => _error = '暂不认识这个代码对应的市场，请核对。');
      return;
    }
    final quantity = _decimal(quantityText, maxScale: 0);
    if (quantity == null || quantity.isNegative) {
      setState(() => _error = '股数需要是非负整数。');
      return;
    }
    final cost = _decimal(costText, maxScale: 3);
    if (cost == null || cost.isNegative || cost > Rational.parse('100000')) {
      setState(() => _error = '每股成本需要是 0 到 100,000 之间的数字，最多三位小数。');
      return;
    }
    final name = _name.text.trim();
    Navigator.of(context).pop(
      HoldingDraft(
        kind: HoldingKind.stock,
        market: _market ?? inferred,
        code: code,
        name: name,
        quantityText: quantityText,
        costText: costText,
        pendingQuote: name.isEmpty || _lookupFailed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final market = _market;
    final quantityLabel = _isFund ? '持有份额 / 份' : '持仓 / 股';
    final costLabel = _isFund ? '单位成本 / 元每份' : '成本 / 元';
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
                _isFund
                    ? (widget.initial == null ? '添加基金持仓' : '修改基金持仓')
                    : (widget.initial == null ? '添加A股持仓' : '修改持仓'),
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
            _isFund
                ? '输入 6 位基金代码后查询名称与品种；份额和单位成本最多四位小数。'
                : '输入 6 位代码后自动识别市场并尝试获取名称。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('holding-code'),
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _isFund ? '基金代码' : '证券代码',
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
                  _isFund
                      ? '场外基金'
                      : (market == null ? '市场待识别' : '${market.label}市'),
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
            decoration: InputDecoration(
              labelText: _isFund ? '基金名称（可修改）' : '名称（自动获取，可修改）',
              hintText: _isFund ? '例如 华夏成长混合' : '例如 平安银行',
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
                  inputFormatters: [
                    _isFund
                        ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                        : FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(labelText: quantityLabel),
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
                  decoration: InputDecoration(labelText: costLabel),
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
            onPressed: _save,
            child: const Text('保存持仓'),
          ),
        ],
      ),
    );
  }
}

Rational? _decimal(String raw, {required int maxScale}) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final pattern = maxScale == 0
      ? RegExp(r'^\d+$')
      : RegExp('^\\d+(\\.\\d{1,$maxScale})?\$');
  if (!pattern.hasMatch(text)) return null;
  return Rational.parse(text);
}
