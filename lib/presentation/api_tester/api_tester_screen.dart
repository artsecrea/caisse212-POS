import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import '../../services/api_service.dart';
import '../../providers/database_providers.dart';

class ApiTesterScreen extends ConsumerStatefulWidget {
  const ApiTesterScreen({super.key});

  @override
  ConsumerState<ApiTesterScreen> createState() => _ApiTesterScreenState();
}

class _ApiTesterScreenState extends ConsumerState<ApiTesterScreen> {
  // Available endpoints
  final List<ApiEndpoint> _endpoints = [
    ApiEndpoint(
      name: 'Login',
      method: 'POST',
      path: '/pos/login',
      requiresAuth: false,
      defaultBody: {
        'username': 'admin',
        'password': 'admin123',
        'posName': 'POS-1',
      },
    ),
    ApiEndpoint(
      name: 'Health Check',
      method: 'GET',
      path: '/health',
      requiresAuth: false,
    ),
    ApiEndpoint(
      name: 'Fetch Categories',
      method: 'GET',
      path: '/pos/categories',
      requiresAuth: true,
    ),
    ApiEndpoint(
      name: 'Fetch Products',
      method: 'GET',
      path: '/pos/products',
      requiresAuth: true,
    ),
    ApiEndpoint(
      name: 'Fetch Components',
      method: 'GET',
      path: '/pos/components',
      requiresAuth: true,
    ),
    ApiEndpoint(
      name: 'Fetch Component Groups',
      method: 'GET',
      path: '/pos/component-groups',
      requiresAuth: true,
    ),
    ApiEndpoint(
      name: 'Fetch Product Components',
      method: 'GET',
      path: '/pos/product-components',
      requiresAuth: true,
    ),
    ApiEndpoint(
      name: 'Fetch Areas',
      method: 'GET',
      path: '/pos/areas',
      requiresAuth: true,
    ),
    ApiEndpoint(
      name: 'Fetch Tables',
      method: 'GET',
      path: '/pos/tables',
      requiresAuth: true,
    ),
    ApiEndpoint(
      name: 'Fetch Users',
      method: 'GET',
      path: '/pos/users',
      requiresAuth: true,
    ),
    ApiEndpoint(
      name: 'Fetch Stations',
      method: 'GET',
      path: '/pos/stations',
      requiresAuth: true,
    ),
    ApiEndpoint(
      name: 'Fetch Commercials',
      method: 'GET',
      path: '/pos/commercials',
      requiresAuth: true,
    ),
    ApiEndpoint(
      name: 'Fetch Customers',
      method: 'GET',
      path: '/pos/customers',
      requiresAuth: true,
    ),
    ApiEndpoint(
      name: 'Sync Orders',
      method: 'POST',
      path: '/pos/sync/orders',
      requiresAuth: true,
      defaultBody: {
        'orders': [
          {
            'id': 1,
            'orderCode': 'ORD-001',
            'totalAmount': 100.50,
            'status': 'COMPLETED',
          }
        ]
      },
    ),
    ApiEndpoint(
      name: 'Sync Tickets',
      method: 'POST',
      path: '/pos/sync/tickets',
      requiresAuth: true,
      defaultBody: {
        'tickets': [
          {
            'id': 1,
            'ticketNumber': 'TKT-001',
            'amount': 50.25,
          }
        ]
      },
    ),
  ];

  ApiEndpoint? _selectedEndpoint;
  final _pathController = TextEditingController();
  final _bodyController = TextEditingController();
  final _headersController = TextEditingController();

  bool _isLoading = false;
  String? _response;
  int? _statusCode;
  String? _error;
  Duration? _requestDuration;

  @override
  void dispose() {
    _pathController.dispose();
    _bodyController.dispose();
    _headersController.dispose();
    super.dispose();
  }

  void _selectEndpoint(ApiEndpoint endpoint) {
    setState(() {
      _selectedEndpoint = endpoint;
      _pathController.text = endpoint.path;
      _bodyController.text = endpoint.defaultBody != null
          ? const JsonEncoder.withIndent('  ').convert(endpoint.defaultBody)
          : '';
      _updateDefaultHeaders();
      _response = null;
      _error = null;
      _statusCode = null;
      _requestDuration = null;
    });
  }

  void _updateDefaultHeaders() {
    final prefs = ref.read(sharedPreferencesProvider);
    final apiService = ApiService(prefs);

    final headers = <String, String>{};

    if (_selectedEndpoint?.requiresAuth ?? false) {
      final token = apiService.getAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    final posName = apiService.getPosName();
    if (posName != null) {
      headers['X-POS-Name'] = posName;
    }

    final tenantId = apiService.getTenantId();
    if (tenantId != null) {
      // headers['X-Tenant-ID'] = tenantId;
    }

    if (_selectedEndpoint?.method == 'POST') {
      headers['Content-Type'] = 'application/json';
    }

    _headersController.text = const JsonEncoder.withIndent('  ').convert(headers);
  }

  Future<void> _sendRequest() async {
    if (_selectedEndpoint == null) {
      setState(() {
        _error = 'Please select an endpoint';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _response = null;
      _error = null;
      _statusCode = null;
      _requestDuration = null;
    });

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);

      // Parse custom headers
      Map<String, dynamic>? customHeaders;
      if (_headersController.text.trim().isNotEmpty) {
        try {
          customHeaders = jsonDecode(_headersController.text);
        } catch (e) {
          throw Exception('Invalid headers JSON: $e');
        }
      }

      // Parse body for POST requests
      Map<String, dynamic>? body;
      if (_selectedEndpoint!.method == 'POST' && _bodyController.text.trim().isNotEmpty) {
        try {
          body = jsonDecode(_bodyController.text);
        } catch (e) {
          throw Exception('Invalid body JSON: $e');
        }
      }

      final startTime = DateTime.now();

      // Make the request using the API service's Dio instance
      final dio = apiService.dio;
      final baseUrl = apiService.getBaseUrl() ?? '';
      final fullUrl = '$baseUrl/api${_pathController.text}';

      final response = await dio.request(
        fullUrl,
        data: body,
        options: Options(
          method: _selectedEndpoint!.method,
          headers: customHeaders,
          validateStatus: (status) => true, // Accept all status codes
        ),
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      setState(() {
        _statusCode = response.statusCode;
        _response = const JsonEncoder.withIndent('  ').convert(response.data);
        _requestDuration = duration;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final apiService = ApiService(prefs);
    final baseUrl = apiService.getBaseUrl() ?? 'Not set';
    final isDemoMode = apiService.isDemoMode();

    return Scaffold(
      appBar: AppBar(
        title: const Text('API Tester'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('API Configuration'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Base URL', baseUrl),
                      _buildInfoRow('POS Name', apiService.getPosName() ?? 'Not set'),
                      // _buildInfoRow('Tenant ID', apiService.getTenantId() ?? 'Not set'),
                      _buildInfoRow('Demo Mode', isDemoMode ? 'Yes' : 'No'),
                      _buildInfoRow('Auth Token', apiService.getAccessToken() != null ? 'Set' : 'Not set'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // Left panel - Endpoint list
          Container(
            width: 280,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppTheme.bar(Theme.of(context).colorScheme),
                  child: const Row(
                    children: [
                      Icon(Icons.api, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Endpoints',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _endpoints.length,
                    itemBuilder: (context, index) {
                      final endpoint = _endpoints[index];
                      final isSelected = _selectedEndpoint == endpoint;

                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        leading: _buildMethodBadge(endpoint.method),
                        title: Text(
                          endpoint.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          endpoint.path,
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        trailing: endpoint.requiresAuth
                            ? Icon(Icons.lock, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)
                            : null,
                        onTap: () => _selectEndpoint(endpoint),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Right panel - Request/Response
          Expanded(
            child: _selectedEndpoint == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.api, size: 80, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(
                          'Select an endpoint to test',
                          style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Request section
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Request header
                              Container(
                                padding: const EdgeInsets.all(16),
                                color: AppTheme.tintFill(context, Colors.blue),
                                child: Row(
                                  children: [
                                    _buildMethodBadge(_selectedEndpoint!.method),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _selectedEndpoint!.name,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _isLoading ? null : _sendRequest,
                                      icon: _isLoading
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.send),
                                      label: Text(_isLoading ? 'Sending...' : 'Send Request'),
                                    ),
                                  ],
                                ),
                              ),

                              // Path
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Endpoint Path',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _pathController,
                                      decoration: InputDecoration(
                                        border: const OutlineInputBorder(),
                                        hintText: '/api/endpoint',
                                        isDense: true,
                                        prefixText: '$baseUrl/api',
                                        prefixStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Headers
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Request Headers',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const Spacer(),
                                        TextButton.icon(
                                          onPressed: _updateDefaultHeaders,
                                          icon: const Icon(Icons.refresh, size: 16),
                                          label: const Text('Reset'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _headersController,
                                      maxLines: 6,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: '{\n  "Header-Name": "value"\n}',
                                        isDense: true,
                                      ),
                                      style: const TextStyle(fontSize: 12, fontFamily: 'Courier'),
                                    ),
                                  ],
                                ),
                              ),

                              // Body (for POST requests)
                              if (_selectedEndpoint!.method == 'POST') ...[
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Request Body (JSON)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _bodyController,
                                        maxLines: 10,
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          hintText: '{\n  "key": "value"\n}',
                                          isDense: true,
                                        ),
                                        style: const TextStyle(fontSize: 12, fontFamily: 'Courier'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),

                      // Divider
                      const Divider(height: 1, thickness: 2),

                      // Response section
                      Expanded(
                        child: Container(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Response header
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(),
                                  border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                                ),
                                child: Row(
                                  children: [
                                    const Text(
                                      'Response',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    if (_statusCode != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'Status: $_statusCode',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: _getStatusColor(),
                                          ),
                                        ),
                                      ),
                                    if (_requestDuration != null) ...[
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${_requestDuration!.inMilliseconds}ms',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: _getStatusColor(),
                                          ),
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    if (_response != null)
                                      IconButton(
                                        icon: const Icon(Icons.copy, color: Colors.white),
                                        tooltip: 'Copy response',
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: _response!));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Response copied to clipboard')),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),

                              // Response body
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: _error != null
                                      ? Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: AppTheme.tintFill(context, Colors.red),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppTheme.tintBorder(context, Colors.red)),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.error_outline, color: AppTheme.tintOn(context, Colors.red)),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  _error!,
                                                  style: TextStyle(
                                                    color: Colors.red[700],
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : _response != null
                                          ? SelectableText(
                                              _response!,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontFamily: 'monospace',
                                              ),
                                            )
                                          : Center(
                                              child: Text(
                                                'No response yet. Click "Send Request" to test the endpoint.',
                                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                              ),
                                            ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodBadge(String method) {
    Color color;
    switch (method) {
      case 'GET':
        color = Colors.blue;
        break;
      case 'POST':
        color = Colors.green;
        break;
      case 'PUT':
        color = Colors.orange;
        break;
      case 'DELETE':
        color = Colors.red;
        break;
      default:
        color = Theme.of(context).colorScheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        method,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (_statusCode == null) return Theme.of(context).colorScheme.onSurfaceVariant;
    if (_statusCode! >= 200 && _statusCode! < 300) return Colors.green;
    if (_statusCode! >= 400 && _statusCode! < 500) return Colors.orange;
    if (_statusCode! >= 500) return Colors.red;
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

class ApiEndpoint {
  final String name;
  final String method;
  final String path;
  final bool requiresAuth;
  final Map<String, dynamic>? defaultBody;

  ApiEndpoint({
    required this.name,
    required this.method,
    required this.path,
    this.requiresAuth = false,
    this.defaultBody,
  });
}

