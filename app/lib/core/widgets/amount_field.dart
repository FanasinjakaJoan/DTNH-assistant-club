import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../utils/money.dart';

/// Champ montant en Ariary avec séparateur de milliers automatique.
///
/// Clavier numérique, pas de virgule acceptée, et une typographie volontairement
/// large : c'est le champ le plus saisi de l'application (bord de terrain).
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    required this.amount,
    required this.onChanged,
    this.label = 'Montant',
    this.autofocus = false,
  });

  final int amount;
  final ValueChanged<int> onChanged;
  final String label;
  final bool autofocus;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.amount > 0 ? groupDigits(widget.amount.toString()) : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _ThousandsFormatter(),
      ],
      onChanged: (value) => widget.onChanged(parseAriary(value) ?? 0),
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: '0',
        suffixText: 'Ar',
        suffixStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
    );
  }
}

class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final grouped = groupDigits(digits);
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: grouped.length),
    );
  }
}
