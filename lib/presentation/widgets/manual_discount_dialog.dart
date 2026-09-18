import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import './adaptive_text_field.dart';

class ManualDiscountDialog extends StatefulWidget {
  final double currentPercentage;
  final String? currentNote;

  const ManualDiscountDialog({
    Key? key,
    this.currentPercentage = 0.0,
    this.currentNote,
  }) : super(key: key);

  @override
  State<ManualDiscountDialog> createState() => _ManualDiscountDialogState();
}

class _ManualDiscountDialogState extends State<ManualDiscountDialog> {
  late TextEditingController _percentageController;
  late TextEditingController _noteController;
  final _percentageFocus = FocusNode();
  final _noteFocus = FocusNode();
  // Manual validation error (the onscreen-keyboard field is a TextField, not a
  // FormField, so we surface errors via the decoration's errorText instead).
  String? _percentageError;

  @override
  void initState() {
    super.initState();
    _percentageController = TextEditingController(
      text: widget.currentPercentage > 0 ? widget.currentPercentage.toStringAsFixed(1) : '',
    );
    _noteController = TextEditingController(text: widget.currentNote ?? '');
  }

  @override
  void dispose() {
    _percentageController.dispose();
    _noteController.dispose();
    _percentageFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _applyDiscount() {
    final raw = _percentageController.text.trim();
    if (raw.isNotEmpty) {
      final percentage = double.tryParse(raw);
      if (percentage == null) {
        setState(() => _percentageError = 'Please enter a valid number');
        return;
      }
      if (percentage < 0 || percentage > 100) {
        setState(() => _percentageError = 'Percentage must be between 0 and 100');
        return;
      }
    }
    final percentage = double.tryParse(raw) ?? 0.0;
    final note =
        _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
    Navigator.of(context).pop({'percentage': percentage, 'note': note});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.percent, color: Theme.of(context).primaryColor, size: 28),
                  const SizedBox(width: 12),
                  const Text(
                    'Manual Discount',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(height: 24),

              Text(
                'Enter discount percentage to apply to all items',
                style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),

              // Percentage input
              AdaptiveKeyboardTextField(
                controller: _percentageController,
                focusNode: _percentageFocus,
                decoration: InputDecoration(
                  labelText: 'Discount Percentage',
                  hintText: '0.0',
                  suffixText: '%',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.percent),
                  errorText: _percentageError,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                autofocus: true,
                onChanged: (_) {
                  if (_percentageError != null) {
                    setState(() => _percentageError = null);
                  }
                },
                onSubmitted: (_) => _applyDiscount(),
              ),

              const SizedBox(height: 20),

              // Quick percentage buttons
              const Text('Quick Select', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [5.0, 10.0, 15.0, 20.0, 25.0, 50.0].map((percentage) {
                  final isSelected = double.tryParse(_percentageController.text) == percentage;
                  return ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _percentageController.text = percentage.toStringAsFixed(1);
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      foregroundColor: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                      elevation: isSelected ? 2 : 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('${percentage.toInt()}%'),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),

              // Note / reason field
              AdaptiveKeyboardTextField(
                controller: _noteController,
                focusNode: _noteFocus,
                decoration: InputDecoration(
                  labelText: 'Note (reason for discount)',
                  hintText: 'e.g. Loyalty customer, manager approval…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.note_alt_outlined),
                ),
                maxLines: 2,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _applyDiscount(),
              ),

              const SizedBox(height: 16),

              // Info box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.tintFill(context, Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.tintBorder(context, Colors.orange)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.tintOn(context, Colors.orange), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This discount will be applied to every ticket product when calculating payments.',
                        style: TextStyle(fontSize: 12, color: AppTheme.tintOn(context, Colors.orange)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.currentPercentage > 0)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop({'percentage': 0.0, 'note': null}),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Remove Discount'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _applyDiscount,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
      ),
    );
  }
}

