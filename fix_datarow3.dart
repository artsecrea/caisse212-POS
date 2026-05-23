import 'dart:io';
void main() {
  final file = File('lib/presentation/widgets/orders_management_screen.dart');
  var lines = file.readAsLinesSync();
  // Find where `DataRow _buildDataRow` is declared
  int startIdx = lines.indexWhere((line) => line.contains('DataRow _buildDataRow('));
  // Look for the end. It should end with `      ],` followed by `    );`
  // We want to rewrite the cells completely inside _buildDataRow to ensure we don't have duplicates.
}
