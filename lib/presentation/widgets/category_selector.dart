import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../domain/models/app_settings.dart';

class CategorySelector extends ConsumerWidget {
  const CategorySelector({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final displayMode = ref.watch(categoryDisplayModeProvider);

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Calculator button
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 6, top: 8, bottom: 8),
            child: InkWell(
              onTap: () {
                _showCalculator(context);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 54,
                decoration: BoxDecoration(
                  color: Colors.blue[700],
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calculate,
                      size: 24,
                      color: Colors.white,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Calc',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Categories list or "Select Category" button based on display mode
          Expanded(
            child: displayMode == CategoryDisplayMode.topBar
                ? _buildTopBarCategories(context, ref, categoriesAsync, selectedCategory)
                : _buildFullPageModeButton(context, ref, categoriesAsync, selectedCategory),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBarCategories(BuildContext context, WidgetRef ref,
      AsyncValue<List<dynamic>> categoriesAsync, int? selectedCategory) {
    return categoriesAsync.when(
      data: (categories) {
        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
          itemCount: categories.length + 1, // +1 for "All" category
          itemBuilder: (context, index) {
            if (index == 0) {
              // "All" category
              return _CategoryChip(
                name: 'All',
                imageUrl: null,
                isSelected: selectedCategory == null,
                onTap: () {
                  ref.read(selectedCategoryProvider.notifier).state = null;
                },
              );
            }

            final category = categories[index - 1];
            return _CategoryChip(
              name: category.name,
              imageUrl: category.imageUrl,
              isSelected: selectedCategory == category.id,
              colorHex: category.color,
              onTap: () {
                ref.read(selectedCategoryProvider.notifier).state = category.id;
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text('Error loading categories: $error'),
      ),
    );
  }

  Widget _buildFullPageModeButton(BuildContext context, WidgetRef ref,
      AsyncValue<List<dynamic>> categoriesAsync, int? selectedCategory) {
    return Padding(
      padding: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
      child: categoriesAsync.when(
        data: (categories) {
          String selectedCategoryName = 'All Categories';

          if (selectedCategory != null && categories.isNotEmpty) {
            if (selectedCategory == -1) {
              selectedCategoryName = 'All Products';
            } else {
              final foundCategory = categories.where((c) => c.id == selectedCategory).firstOrNull;
              if (foundCategory != null) {
                selectedCategoryName = foundCategory.name;
              }
            }
          }

          return Row(
            children: [
              if (selectedCategory != null) ...[
                // Back button to show all categories
                InkWell(
                  onTap: () {
                    ref.read(selectedCategoryProvider.notifier).state = null;
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 20, color: Theme.of(context).colorScheme.onSurface),
                        const SizedBox(width: 4),
                        Text(
                          'Back',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              // Current category indicator / Select category button
              Expanded(
                child: InkWell(
                  onTap: selectedCategory == null
                      ? null // Don't do anything when in category selection mode
                      : () {
                          // Go back to category selection
                          ref.read(selectedCategoryProvider.notifier).state = null;
                        },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).primaryColor,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selectedCategory == null ? Icons.category : Icons.label,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            selectedCategoryName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Theme.of(context).primaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (selectedCategory != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.swap_horiz,
                            size: 20,
                            color: Theme.of(context).primaryColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error loading categories: $error'),
        ),
      ),
    );
  }

  void _showCalculator(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _CalculatorDialog(),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final bool isSelected;
  final String? colorHex;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.name,
    this.imageUrl,
    required this.isSelected,
    this.colorHex,
    required this.onTap,
  });

  Color? _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return null;
    try {
      String hex = colorStr.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}
    return null;
  }

  Color _textColorFor(Color? bg) {
    if (bg == null) return Colors.black;
    return bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final chipColor = _parseColor(colorHex);
    final bgColor = isSelected
        ? Theme.of(context).primaryColor
        : chipColor ?? Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = isSelected
        ? Colors.white
        : chipColor != null
            ? _textColorFor(chipColor)
            : Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 90,
          constraints: const BoxConstraints(
            minWidth: 70,
            maxWidth: 90,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).primaryColor
                  : chipColor ?? Colors.grey[300]!,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalculatorDialog extends StatefulWidget {
  const _CalculatorDialog();

  @override
  State<_CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<_CalculatorDialog> {
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
              borderRadius: BorderRadius.circular(8),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_expression.isNotEmpty)
                    Text(
                      _expression,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
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
