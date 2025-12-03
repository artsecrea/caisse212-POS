// filepath: /home/arecrea/prj/posecrea/lib/presentation/widgets/devices_management_screen.dart

import 'package:cmdecrea/cmdecrea.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:loggecrea/loggecrea.dart';
import '../../providers/device_providers.dart';
import '../../providers/socket_order_providers.dart';
import '../../data/database/app_database.dart';
import '../../services/socket_service.dart';
import '../../providers/database_providers.dart';

class DevicesManagementScreen extends ConsumerStatefulWidget {
  const DevicesManagementScreen({super.key});

  @override
  ConsumerState<DevicesManagementScreen> createState() => _DevicesManagementScreenState();
}

class _DevicesManagementScreenState extends ConsumerState<DevicesManagementScreen> {
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    final kdsListAsync = ref.watch(kdsListProvider);
    final kioskListAsync = ref.watch(kioskListProvider);
    final connectedDevices = ref.watch(discoveredDevicesProvider);
    
    Logger.instance.debug('Rebuilding DevicesManagementScreen ${connectedDevices.length}');

    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildActionsBar(),
          Expanded(
            child: kdsListAsync.when(
              data: (kdsList) => kioskListAsync.when(
                data: (kioskList) {
                  return FutureBuilder<List<DeviceRowData>>(
                    future: _combineDevices(kdsList, kioskList, connectedDevices),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == widgets.ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return _buildErrorView(snapshot.error.toString());
                      }
                      final allDevices = snapshot.data ?? [];
                      if (allDevices.isEmpty) {
                        return _buildEmptyView();
                      }
                      return _buildDevicesTable(allDevices);
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => _buildErrorView(err.toString()),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => _buildErrorView(err.toString()),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Devices Management'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(() {}),
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildActionsBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: _isScanning ? null : _scanNetwork,
            icon: _isScanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.radar),
            label: Text(_isScanning ? 'Scanning...' : 'Scan Network'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: _showAddDeviceDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Device'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesTable(List<DeviceRowData> devices) {
    return DataTable2(
      columnSpacing: 12,
      horizontalMargin: 12,
      minWidth: 1000,
      headingRowColor: MaterialStateProperty.all(Colors.grey[200]),
      columns: const [
        DataColumn2(label: Text('ID', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S),
        DataColumn2(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.M),
        DataColumn2(label: Text('Type', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S),
        DataColumn2(label: Text('Station', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.M),
        DataColumn2(label: Text('IP Address', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.M),
        DataColumn2(label: Text('Port', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S),
        DataColumn2(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.M),
        DataColumn2(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S),
        DataColumn2(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.L, fixedWidth: 180),
      ],
      rows: devices.map((device) => _buildDataRow(device)).toList(),
    );
  }

  DataRow _buildDataRow(DeviceRowData device) {
    return DataRow(
      cells: [
        DataCell(Text(device.id.toString())),
        DataCell(Text(device.name)),
        DataCell(_buildTypeChip(device.type)),
        DataCell(Text(device.stationName ?? (device.type == 'KDS' ? 'Not assigned' : 'N/A'))),
        DataCell(Text(device.ip ?? 'N/A')),
        DataCell(Text(device.port?.toString() ?? 'N/A')),
        DataCell(Text(device.location ?? 'N/A')),
        DataCell(_buildStatusChip(device.isConnected)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility, size: 20),
                onPressed: () => _showDeviceDetails(device),
                tooltip: 'View Details',
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _showEditDeviceDialog(device),
                tooltip: 'Edit Device',
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                onPressed: () => _deleteDevice(device),
                tooltip: 'Delete Device',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeChip(String type) {
    final color = type == 'KDS' ? Colors.purple : Colors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        type,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isConnected) {
    final color = isConnected ? Colors.green : Colors.grey;
    final text = isConnected ? 'Connected' : 'Disconnected';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.devices, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No devices found',
            style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Click "Scan Network" to discover devices or "Add Device" to add manually',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            'Error loading devices',
            style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Helper Functions

  Future<List<DeviceRowData>> _combineDevices(
    List<KDS> kdsList,
    List<Kiosk> kioskList,
    List<DeviceInfo> connectedDevices,
  ) async {
    final devices = <DeviceRowData>[];
    final database = ref.read(databaseProvider);

    for (final kds in kdsList) {
      String? stationName;
      if (kds.stationId != null) {
        final station = await (database.select(database.stations)
              ..where((tbl) => tbl.id.equals(kds.stationId!)))
            .getSingleOrNull();
        stationName = station?.name;
      }

      devices.add(DeviceRowData(
        id: kds.id,
        name: kds.name,
        type: 'KDS',
        ip: kds.ip,
        port: kds.port,
        location: kds.location,
        isActive: kds.isActive,
        isConnected: connectedDevices.any((item) => item.name == kds.name),
        description: kds.description,
        stationId: kds.stationId,
        stationName: stationName,
      ));
    }

    for (final kiosk in kioskList) {
      devices.add(DeviceRowData(
        id: kiosk.id,
        name: kiosk.name,
        type: 'KIOSK',
        ip: kiosk.ip,
        port: kiosk.port,
        location: kiosk.location,
        isActive: kiosk.isActive,
        isConnected: connectedDevices.contains('KIOSK_${kiosk.id}'),
        description: kiosk.description,
      ));
    }

    return devices;
  }

  // CRUD Operations

  void _scanNetwork() async {
    setState(() => _isScanning = true);

    try {
      final socketService = ref.read(socketServiceProvider);

      if (mounted) {
        final discoveredDevices = await socketService.scanNetwork();

        if (discoveredDevices.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No devices found on network')),
          );
        } else {
          _showDiscoveredDevicesDialog(discoveredDevices);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning network: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  void _showDiscoveredDevicesDialog(List<DeviceInfo> devices) {
    showDialog(
      context: context,
      builder: (context) => _DiscoveredDevicesDialog(devices: devices),
    );
  }

  void _showAddDeviceDialog() {
    showDialog(
      context: context,
      builder: (context) => const _DeviceFormDialog(),
    );
  }

  void _showEditDeviceDialog(DeviceRowData device) {
    showDialog(
      context: context,
      builder: (context) => _DeviceFormDialog(device: device),
    );
  }

  void _showDeviceDetails(DeviceRowData device) {
    showDialog(
      context: context,
      builder: (context) => _DeviceDetailsDialog(device: device),
    );
  }

  void _deleteDevice(DeviceRowData device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Device'),
        content: Text('Are you sure you want to delete device "${device.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final deviceRepo = ref.read(deviceRepositoryProvider);
        await deviceRepo.deleteDevice(device.id, device.type);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Device deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting device: $e')),
          );
        }
      }
    }
  }
}

// Device Row Data Model
class DeviceRowData {
  final int id;
  final String name;
  final String type;
  final String? ip;
  final int? port;
  final String? location;
  final bool isActive;
  final bool isConnected;
  final String? description;
  final int? stationId;
  final String? stationName;

  DeviceRowData({
    required this.id,
    required this.name,
    required this.type,
    this.ip,
    this.port,
    this.location,
    required this.isActive,
    required this.isConnected,
    this.description,
    this.stationId,
    this.stationName,
  });
}

// Device Form Dialog
class _DeviceFormDialog extends ConsumerStatefulWidget {
  final DeviceRowData? device;

  const _DeviceFormDialog({this.device});

  @override
  ConsumerState<_DeviceFormDialog> createState() => _DeviceFormDialogState();
}

class _DeviceFormDialogState extends ConsumerState<_DeviceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _ipController;
  late TextEditingController _portController;
  late TextEditingController _locationController;
  late TextEditingController _descriptionController;
  late String _type;
  late bool _isActive;
  int? _selectedStationId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device?.name ?? '');
    _ipController = TextEditingController(text: widget.device?.ip ?? '');
    _portController = TextEditingController(text: widget.device?.port?.toString() ?? '');
    _locationController = TextEditingController(text: widget.device?.location ?? '');
    _descriptionController = TextEditingController(text: widget.device?.description ?? '');
    _type = widget.device?.type ?? 'KDS';
    _isActive = widget.device?.isActive ?? true;
    _selectedStationId = widget.device?.stationId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.device == null ? 'Add Device' : 'Edit Device',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'Device Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'KDS', child: Text('KDS (Kitchen Display System)')),
                  DropdownMenuItem(value: 'KIOSK', child: Text('KIOSK')),
                ],
                onChanged: widget.device == null ? (value) => setState(() => _type = value!) : null,
              ),
              const SizedBox(height: 16),
              if (_type == 'KDS')
                _buildStationDropdown(),
              if (_type == 'KDS')
                const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty ?? true ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'IP Address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Active'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _saveDevice,
                    child: Text(widget.device == null ? 'Add' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStationDropdown() {
    final stationsAsync = ref.watch(stationListProvider);

    return stationsAsync.when(
      data: (stations) {
        return DropdownButtonFormField<int?>(
          value: _selectedStationId,
          decoration: const InputDecoration(
            labelText: 'Station',
            border: OutlineInputBorder(),
            helperText: 'Optional - Assign this KDS to a station',
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Not assigned'),
            ),
            ...stations.map((station) => DropdownMenuItem<int?>(
              value: station.id,
              child: Text(station.name),
            )),
          ],
          onChanged: (value) => setState(() => _selectedStationId = value),
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (err, stack) => Text('Error loading stations: $err'),
    );
  }

  void _saveDevice() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final deviceRepo = ref.read(deviceRepositoryProvider);

      final port = _portController.text.isEmpty ? null : int.tryParse(_portController.text);

      if (widget.device == null) {
        // Add new device
        await deviceRepo.addDevice(
          name: _nameController.text,
          type: _type,
          ip: _ipController.text.isEmpty ? null : _ipController.text,
          port: port,
          location: _locationController.text.isEmpty ? null : _locationController.text,
          description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
          isActive: _isActive,
          stationId: _type == 'KDS' ? _selectedStationId : null,
        );
      } else {
        // Update existing device
        await deviceRepo.updateDevice(
          id: widget.device!.id,
          type: widget.device!.type,
          name: _nameController.text,
          ip: _ipController.text.isEmpty ? null : _ipController.text,
          port: port,
          location: _locationController.text.isEmpty ? null : _locationController.text,
          description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
          isActive: _isActive,
          stationId: widget.device!.type == 'KDS' ? _selectedStationId : null,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.device == null ? 'Device added successfully' : 'Device updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving device: $e')),
        );
      }
    }
  }
}

// Device Details Dialog
class _DeviceDetailsDialog
    extends StatelessWidget {
  final DeviceRowData device;

  const _DeviceDetailsDialog({required this.device});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  device.type == 'KDS' ? Icons.tv : Icons.tablet,
                  size: 32,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        device.type,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(height: 32),
            _buildDetailRow('ID', device.id.toString()),
            if (device.type == 'KDS')
              _buildDetailRow('Station', device.stationName ?? 'Not assigned'),
            _buildDetailRow('IP Address', device.ip ?? 'Not set'),
            _buildDetailRow('Port', device.port?.toString() ?? 'Not set'),
            _buildDetailRow('Location', device.location ?? 'Not set'),
            _buildDetailRow('Description', device.description ?? 'Not set'),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Status: ',
                  style: TextStyle(color: Colors.grey[700], fontSize: 14),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: device.isConnected ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: device.isConnected ? Colors.green : Colors.grey),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: device.isConnected ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        device.isConnected ? 'Connected' : 'Disconnected',
                        style: TextStyle(
                          color: device.isConnected ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  'Active: ',
                  style: TextStyle(color: Colors.grey[700], fontSize: 14),
                ),
                Icon(
                  device.isActive ? Icons.check_circle : Icons.cancel,
                  color: device.isActive ? Colors.green : Colors.red,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// Discovered Devices Dialog
class _DiscoveredDevicesDialog extends ConsumerWidget {
  final List<DeviceInfo> devices;

  const _DiscoveredDevicesDialog({required this.devices});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceRepo = ref.read(deviceRepositoryProvider);
    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 500),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.radar, size: 32),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Discovered Devices',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.devices),
                      title: Text(device.toString()),
                      trailing: ElevatedButton(
                        onPressed: () async {
                          // Add device logic here
                          print(device.metadata);
                          await deviceRepo.addDevice(
                              ip: device.address,
                              port: device.port,
                              name: device.name,
                              type: "KDS"
                          );

                        },
                        child: const Text('Add'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

