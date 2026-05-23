import 'dart:io';
void main() {
  final file = File('lib/presentation/widgets/orders_management_screen.dart');
  var content = file.readAsStringSync();
  // Find the LAST popup_menu_button data cell
  final searchStr = '''        DataCell(
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: l10n.translate('actions'),
            onSelected: (value) {
              if (value == 'view') _showOrderDetails(order);
              else if (value == 'pay') _payOrder(order);
              else if (value == 'edit') _editOrder(order);
              else if (value == 'status') _showChangeStatusDialog(order);
              else if (value == 'cancel') _cancelOrder(order);
              else if (value == 'delete') _deleteOrder(order);
            },
            itemBuilder: (context) {
              final permissionService = ref.read(permissionServiceProvider);
              final canUpdate = permissionService.hasPermission(Permissions.ordersUpdate);
              final canDelete = permissionService.hasPermission(Permissions.ordersDelete);
              return [
                PopupMenuItem(
                  value: 'view',
                  child: Row(
                    children: [
                      const Icon(Icons.visibility, size: 18),
                      const SizedBox(width: 8),
                      Text(l10n.translate('view')),
                    ],
                  ),
                ),
                if (isUnpaid)
                  PopupMenuItem(
                    value: 'pay',
                    child: Row(
                      children: [
                        const Icon(Icons.payment, size: 18, color: Colors.teal),
                        const SizedBox(width: 8),
                        Text(l10n.translate('pay')),
                      ],
                    ),
                  )
                else if (!isZLocked) ...[
                  if (canUpdate)
                    PopupMenuItem(
                       value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit, size: 18, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(l10n.translate('edit')),
                        ],
                      ),
                    ),
                  if (canUpdate)
                    PopupMenuItem(
                      value: 'status',
                      child: Row(
                        children: [
                          const Icon(Icons.swap_horiz, size: 18, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(l10n.translate('status')),
                        ],
                      ),
                    ),
                  if (canUpdate)
                    PopupMenuItem(
                      value: 'cancel',
                      child: Row(
                        children: [
                          const Icon(Icons.cancel, size: 18, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(l10n.translate('cancel_order')),
                        ],
                      ),
                    ),
                  if (canDelete)
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_forever, size: 18, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(l10n.translate('delete')),
                        ],
                      ),
                    ),
                ],
              ];
            },
          ),
        ),''';
  // Find all matches of searchStr 
  final allMatches = searchStr.allMatches(content);
  // Actually wait, let's just do it directly.
}
