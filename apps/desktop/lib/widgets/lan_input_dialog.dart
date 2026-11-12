import 'package:flutter/material.dart';
import 'package:lan_transfer/lan_transfer.dart';

final class LanInput {
  const LanInput(this.address, this.code);

  final LanAddress address;
  final String code;
}

/// Address + pairing-code form shared by both PC LAN directions.
class LanInputDialog extends StatefulWidget {
  const LanInputDialog({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.hint,
  });

  final String title;
  final String actionLabel;
  final String hint;

  @override
  State<LanInputDialog> createState() => _LanInputDialogState();
}

class _LanInputDialogState extends State<LanInputDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _code = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      LanInput(
        LanAddress.parse(_address.text),
        LanTransferCode.normalize(_code.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 430,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.hint, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '手机地址',
                  hintText: '192.168.1.5:54321',
                ),
                validator: (value) {
                  try {
                    LanAddress.parse(value ?? '');
                    return null;
                  } on LanTransferException catch (error) {
                    return error.message;
                  }
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: '配对码',
                  hintText: 'ABCD-EFGH-JKMN',
                ),
                validator: (value) => LanTransferCode.isValid(value ?? '')
                    ? null
                    : '配对码应为 12 位（可带 - 分隔）',
                onFieldSubmitted: (_) => _submit(),
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
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}
