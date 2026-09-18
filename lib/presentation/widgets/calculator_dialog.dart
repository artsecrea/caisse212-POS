import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The till's scratch calculator.
///
/// Lived inside [CategorySelector] until the category bar became something a
/// shop can turn off — a general-purpose tool has no business being reachable
/// only from a bar about categories. Its own file, with one public way in.
void showCalculatorDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const CalculatorDialog(),
  );
}

class CalculatorDialog extends StatefulWidget {
  const CalculatorDialog({super.key});

  @override
  State<CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<CalculatorDialog> {
  String _display = '0';
  String _expression = '';
  double? _firstOperand;
  String? _operator;
  bool _shouldResetDisplay = false;

  void _onNumberPressed(String number) {
    setState(() {
      if (_shouldResetDisplay || _display == '0') {
        _display = number;
        _shouldResetDisplay = false;
      } else {
        _display += number;
      }
    });
  }

  void _onOperatorPressed(String operator) {
    setState(() {
      if (_firstOperand == null) {
        _firstOperand = double.tryParse(_display);
        _operator = operator;
        _expression = '$_display $operator';
        _shouldResetDisplay = true;
      } else {
        _calculate();
        _operator = operator;
        _expression = '$_display $operator';
        _shouldResetDisplay = true;
      }
    });
  }

  void _calculate() {
    if (_firstOperand == null || _operator == null) return;

    final secondOperand = double.tryParse(_display);
    if (secondOperand == null) return;

    double result = 0;
    switch (_operator) {
      case '+':
        result = _firstOperand! + secondOperand;
        break;
      case '-':
        result = _firstOperand! - secondOperand;
        break;
      case '×':
        result = _firstOperand! * secondOperand;
        break;
      case '÷':
        if (secondOperand != 0) {
          result = _firstOperand! / secondOperand;
        }
        break;
    }

    setState(() {
      _display = result.toString();
      if (_display.endsWith('.0')) {
        _display = _display.substring(0, _display.length - 2);
      }
      _expression = '';
      _firstOperand = result;
      _operator = null;
    });
  }

  void _onEqualsPressed() {
    _calculate();
    setState(() {
      _shouldResetDisplay = true;
    });
  }

  void _onClearPressed() {
    setState(() {
      _display = '0';
      _expression = '';
      _firstOperand = null;
      _operator = null;
      _shouldResetDisplay = false;
    });
  }

  void _onDecimalPressed() {
    setState(() {
      if (_shouldResetDisplay) {
        _display = '0.';
        _shouldResetDisplay = false;
      } else if (!_display.contains('.')) {
        _display += '.';
      }
    });
  }

  void _onBackspacePressed() {
    setState(() {
      if (_display.length > 1) {
        _display = _display.substring(0, _display.length - 1);
      } else {
        _display = '0';
      }
    });
  }

  Widget _buildButton(String text, {Color? color, VoidCallback? onPressed}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? Theme.of(context).colorScheme.surfaceContainerHigh,
            foregroundColor: color != null
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            padding: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(
              borderRadius: AppTheme.brMd,
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppTheme.brLg),
      child: Container(
        width: 350,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Calculator',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: AppTheme.brMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_expression.isNotEmpty)
                    Text(
                      _expression,
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    _display,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Buttons
            Row(
              children: [
                _buildButton('C', color: Colors.red[400], onPressed: _onClearPressed),
                _buildButton('⌫', onPressed: _onBackspacePressed),
                _buildButton('÷', color: Colors.blue[700], onPressed: () => _onOperatorPressed('÷')),
              ],
            ),
            Row(
              children: [
                _buildButton('7', onPressed: () => _onNumberPressed('7')),
                _buildButton('8', onPressed: () => _onNumberPressed('8')),
                _buildButton('9', onPressed: () => _onNumberPressed('9')),
                _buildButton('×', color: Colors.blue[700], onPressed: () => _onOperatorPressed('×')),
              ],
            ),
            Row(
              children: [
                _buildButton('4', onPressed: () => _onNumberPressed('4')),
                _buildButton('5', onPressed: () => _onNumberPressed('5')),
                _buildButton('6', onPressed: () => _onNumberPressed('6')),
                _buildButton('-', color: Colors.blue[700], onPressed: () => _onOperatorPressed('-')),
              ],
            ),
            Row(
              children: [
                _buildButton('1', onPressed: () => _onNumberPressed('1')),
                _buildButton('2', onPressed: () => _onNumberPressed('2')),
                _buildButton('3', onPressed: () => _onNumberPressed('3')),
                _buildButton('+', color: Colors.blue[700], onPressed: () => _onOperatorPressed('+')),
              ],
            ),
            Row(
              children: [
                _buildButton('0', onPressed: () => _onNumberPressed('0')),
                _buildButton('.', onPressed: _onDecimalPressed),
                _buildButton('=', color: Colors.green[700], onPressed: _onEqualsPressed),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
