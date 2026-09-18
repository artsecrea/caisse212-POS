import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../utils/app_localizations.dart';

class ReportIssueDialog extends ConsumerStatefulWidget {
  const ReportIssueDialog({super.key});

  @override
  ConsumerState<ReportIssueDialog> createState() => _ReportIssueDialogState();
}

class _ReportIssueDialogState extends ConsumerState<ReportIssueDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String _selectedType = 'GENERAL';
  bool _isSubmitting = false;

  final List<Map<String, String>> _issueTypes = [
    {'value': 'GENERAL', 'key': 'issue_type_general'},
    {'value': 'BUG', 'key': 'issue_type_bug'},
    {'value': 'FEATURE', 'key': 'issue_type_feature'},
    {'value': 'HARDWARE', 'key': 'issue_type_hardware'},
    {'value': 'NETWORK', 'key': 'issue_type_network'},
    {'value': 'PRINTER', 'key': 'issue_type_printer'},
    {'value': 'OTHER', 'key': 'issue_type_other'},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitIssue() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final apiService = ref.read(apiServiceProvider);
      
      // Get current user from shared preferences
      final prefs = ref.read(sharedPreferencesProvider);
      final userId = prefs.getInt('user_id');

      await apiService.submitIssue(
        title: _titleController.text.trim(),
        type: _selectedType,
        description: _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        userId: userId,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.translate('issue_submitted') ?? 
              'Issue submitted successfully'
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context)?.translate('issue_submit_failed') ?? 'Failed to submit issue'}: $e'
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.bug_report,
                    color: Theme.of(context).primaryColor,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    localizations?.translate('report_issue') ?? 'Report Issue',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.headlineSmall?.color,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    color: Theme.of(context).iconTheme.color,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Issue Type Dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: InputDecoration(
                  labelText: localizations?.translate('issue_type') ?? 'Issue Type',
                  prefixIcon: const Icon(Icons.category),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDarkMode 
                      ? Theme.of(context).colorScheme.onSurface 
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                dropdownColor: isDarkMode ? Colors.grey[850] : Colors.white,
                items: _issueTypes.map((type) {
                  return DropdownMenuItem(
                    value: type['value'],
                    child: Text(
                      localizations?.translate(type['key']!) ?? type['value']!,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedType = value);
                  }
                },
              ),
              const SizedBox(height: 20),

              // Title Field
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: localizations?.translate('issue_title') ?? 'Issue Title',
                  hintText: localizations?.translate('enter_issue_title') ?? 'Enter issue title',
                  prefixIcon: const Icon(Icons.title),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDarkMode 
                      ? Theme.of(context).colorScheme.onSurface 
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return localizations?.translate('title_required') ?? 'Title is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Description Field
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: localizations?.translate('issue_description') ?? 'Issue Description',
                  hintText: localizations?.translate('enter_issue_description') ?? 
                      'Describe the issue (optional)',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 80),
                    child: Icon(Icons.description),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDarkMode 
                      ? Theme.of(context).colorScheme.onSurface 
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  alignLabelWithHint: true,
                ),
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      localizations?.translate('cancel') ?? 'Cancel',
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitIssue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            localizations?.translate('submit_issue') ?? 'Submit Issue',
                          ),
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

