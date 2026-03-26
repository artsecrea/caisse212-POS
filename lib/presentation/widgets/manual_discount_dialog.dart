import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _formKey = GlobalKey<FormState>();

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
    super.dispose();
  }

  void _applyDiscount() {
    if (_formKey.currentState!.validate()) {
      final percentage = double.tryParse(_percentageController.text) ?? 0.0;
      final note = _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
      Navigator.of(context).pop({'percentage': percentage, 'note': note});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
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

              const Text(
                'Enter discount percentage to apply to all items',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 20),

              // Percentage input
              TextFormField(
                controller: _percentageController,
                decoration: InputDecoration(
                  labelText: 'Discount Percentage',
                  hintText: '0.0',
                  suffixText: '%',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.percent),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) return null;
                  final percentage = double.tryParse(value);
                  if (percentage == null) return 'Please enter a valid number';
                  if (percentage < 0 || percentage > 100) return 'Percentage must be between 0 and 100';
                  return null;
                },
                autofocus: true,
                onFieldSubmitted: (_) => _applyDiscount(),
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
                      backgroundColor: isSelected ? Theme.of(context).primaryColor : Colors.grey[200],
                      foregroundColor: isSelected ? Colors.white : Colors.black87,
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
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: 'Note (reason for discount)',
                  hintText: 'e.g. Loyalty customer, manager approval…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.note_alt_outlined),
                ),
                maxLines: 2,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _applyDiscount(),
              ),

              const SizedBox(height: 16),

              // Info box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This discount will be applied to every ticket product when calculating payments.',
                        style: TextStyle(fontSize: 12, color: Colors.orange[900]),
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
      ),
    );
  }
}

