import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/order_models.dart';
import '../providers/settings_provider.dart';
import '../providers/database_providers.dart';

/// Service that manages the customer-facing display.
/// Serves a web-based customer display via an embedded HTTP server.
/// The display can be opened in any browser on a second screen.
class CustomerDisplayService {
  final Ref _ref;
  HttpServer? _server;
  bool _isOpen = false;
  int _port = 8899;

  // Current order state (serialized for the web display)
  Map<String, dynamic> _currentOrderData = {'action': 'clear'};

  // SSE (Server-Sent Events) clients
  final List<HttpResponse> _sseClients = [];
  Timer? _heartbeatTimer;

  CustomerDisplayService(this._ref);

  bool get isOpen => _isOpen;
  String get displayUrl => 'http://localhost:$_port';

  /// Check if platform supports customer display
  bool get isSupported =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  /// Open the customer display (starts an HTTP server serving the display page)
  Future<void> open() async {
    if (!isSupported) {
      debugPrint('Customer display not supported on this platform');
      return;
    }

    if (_isOpen && _server != null) {
      debugPrint('Customer display already running at $displayUrl');
      return;
    }

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      _isOpen = true;
      debugPrint('✅ Customer display server started at $displayUrl');

      _server!.listen((request) {
        _handleRequest(request);
      });

      // Start heartbeat to keep SSE connections alive
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _sendHeartbeat();
      });

      // Auto-open browser on Linux/Windows
      _openBrowser();
    } catch (e) {
      debugPrint('❌ Failed to start customer display server: $e');
      _isOpen = false;
      _server = null;
    }
  }

  /// Close the customer display server
  Future<void> close() async {
    if (!_isOpen || _server == null) return;

    try {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;

      // Close all SSE connections
      for (final client in _sseClients) {
        try {
          client.close();
        } catch (_) {}
      }
      _sseClients.clear();

      await _server!.close(force: true);
      _server = null;
      _isOpen = false;
      debugPrint('🛑 Customer display server stopped');
    } catch (e) {
      debugPrint('Error closing customer display server: $e');
      _server = null;
      _isOpen = false;
    }
  }

  /// Handle HTTP requests
  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;

    switch (path) {
      case '/':
      case '/index.html':
        _serveDisplayPage(request);
        break;
      case '/events':
        _handleSSE(request);
        break;
      case '/data':
        _serveCurrentData(request);
        break;
      default:
        request.response
          ..statusCode = 404
          ..write('Not Found')
          ..close();
    }
  }

  /// Serve current order data as JSON
  void _serveCurrentData(HttpRequest request) {
    request.response
      ..headers.contentType = ContentType.json
      ..headers.add('Access-Control-Allow-Origin', '*')
      ..write(jsonEncode(_currentOrderData))
      ..close();
  }

  /// Handle SSE connection for real-time updates
  void _handleSSE(HttpRequest request) {
    final response = request.response;
    response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
    response.headers.add('Cache-Control', 'no-cache');
    response.headers.add('Connection', 'keep-alive');
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.bufferOutput = false; // Critical: disable buffering for SSE

    // Send current state immediately
    response.write('data: ${jsonEncode(_currentOrderData)}\n\n');

    _sseClients.add(response);
    debugPrint('📺 SSE client connected (total: ${_sseClients.length})');

    // Remove on disconnect
    response.done.then((_) {
      _sseClients.remove(response);
      debugPrint('📺 SSE client disconnected (total: ${_sseClients.length})');
    }).catchError((_) {
      _sseClients.remove(response);
      debugPrint('📺 SSE client error-disconnected (total: ${_sseClients.length})');
    });
  }

  /// Broadcast data to all SSE clients
  void _broadcastToClients(Map<String, dynamic> data) {
    final message = 'data: ${jsonEncode(data)}\n\n';
    final deadClients = <HttpResponse>[];

    debugPrint('📺 Broadcasting to ${_sseClients.length} SSE clients');

    for (final client in _sseClients) {
      try {
        client.write(message);
      } catch (e) {
        debugPrint('📺 SSE write error: $e');
        deadClients.add(client);
      }
    }

    // Clean up dead connections
    for (final dead in deadClients) {
      _sseClients.remove(dead);
    }
  }

  /// Send heartbeat to keep SSE connections alive
  void _sendHeartbeat() {
    final deadClients = <HttpResponse>[];

    for (final client in _sseClients) {
      try {
        client.write(':heartbeat\n\n');
      } catch (e) {
        deadClients.add(client);
      }
    }

    for (final dead in deadClients) {
      _sseClients.remove(dead);
    }
  }

  /// Send current order data to the customer display
  Future<void> sendOrderUpdate(CurrentOrder order) async {
    if (!_isOpen) return;

    _currentOrderData = {
      'action': 'update',
      'orderCode': order.orderCode,
      'orderType': order.type,
      'items': order.items.map((item) => {
        'name': item.displayName,
        'quantity': item.quantity,
        'price': item.totalPrice,
        'components': item.components.map((c) => {
          'name': c.name,
          'quantity': c.quantity,
        }).toList(),
        'note': item.note,
        'isPaid': item.ticketId != null,
      }).toList(),
      'subtotal': order.subtotal,
      'tax': order.tax,
      'discount': order.totalDiscount,
      'total': order.total,
    };

    _broadcastToClients(_currentOrderData);
  }

  /// Clear the customer display (show welcome screen)
  Future<void> clearDisplay() async {
    if (!_isOpen) return;

    _currentOrderData = {'action': 'clear'};
    _broadcastToClients(_currentOrderData);
  }

  /// Send business name to the customer display
  Future<void> sendBusinessName(String? name) async {
    if (!_isOpen) return;

    final data = {
      'action': 'update_business',
      'businessName': name,
    };
    _broadcastToClients(data);
  }

  /// Open browser to display URL
  void _openBrowser() {
    try {
      if (Platform.isLinux) {
        Process.run('xdg-open', [displayUrl]);
      } else if (Platform.isWindows) {
        Process.run('start', [displayUrl], runInShell: true);
      } else if (Platform.isMacOS) {
        Process.run('open', [displayUrl]);
      }
    } catch (e) {
      debugPrint('Could not auto-open browser: $e');
    }
  }

  /// Serve the HTML customer display page
  void _serveDisplayPage(HttpRequest request) {
    final settings = _ref.read(settingsProvider);
    final prefs = _ref.read(sharedPreferencesProvider);
    final businessName = prefs.getString('business_name') ?? '';
    final lang = settings.language;
    final currency = settings.currency;
    final isDark = settings.isDarkMode;

    final html = _buildHtmlPage(
      lang: lang,
      currency: currency,
      isDark: isDark,
      businessName: businessName,
    );

    request.response
      ..headers.contentType = ContentType.html
      ..write(html)
      ..close();
  }

  /// Build the full HTML page for the customer display
  String _buildHtmlPage({
    required String lang,
    required String currency,
    required bool isDark,
    required String businessName,
  }) {
    final isRtl = lang == 'ar';
    final t = _getTranslations(lang);

    final bgColor = isDark ? '#1A1A2E' : '#F5F7FA';
    final cardColor = isDark ? '#16213E' : '#FFFFFF';
    final textColor = isDark ? '#FFFFFF' : '#2D3436';
    final subtextColor = isDark ? '#B2BEC3' : '#636E72';
    final accentColor = '#0984E3';
    final borderColor = isDark ? '#2D3748' : '#E2E8F0';

    return '''<!DOCTYPE html>
<html lang="$lang" dir="${isRtl ? 'rtl' : 'ltr'}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${t['your_order']}</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  background: $bgColor;
  color: $textColor;
  height: 100vh;
  overflow: hidden;
}
.container { display: flex; flex-direction: column; height: 100vh; padding: 24px; gap: 16px; }
.header {
  background: $cardColor;
  border-radius: 16px;
  padding: 16px 24px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  box-shadow: 0 4px 10px rgba(0,0,0,0.05);
}
.header-left { display: flex; align-items: center; gap: 16px; }
.header-icon { font-size: 32px; color: $accentColor; }
.header-title { font-size: 24px; font-weight: 700; }
.header-code { font-size: 14px; color: $subtextColor; }
.order-type {
  background: ${accentColor}1A;
  color: $accentColor;
  padding: 8px 16px;
  border-radius: 20px;
  font-weight: 600;
  font-size: 14px;
}
.items-container {
  flex: 1;
  background: $cardColor;
  border-radius: 16px;
  box-shadow: 0 4px 10px rgba(0,0,0,0.05);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
.items-header {
  display: flex;
  padding: 12px 24px;
  background: ${accentColor}0D;
  border-bottom: 1px solid $borderColor;
  font-weight: 600;
  font-size: 13px;
  color: $subtextColor;
}
.items-list { flex: 1; overflow-y: auto; }
.item {
  display: flex;
  padding: 10px 24px;
  border-bottom: 1px solid $borderColor;
  align-items: flex-start;
  transition: background 0.2s;
}
.item.paid { background: rgba(0,184,148,0.05); }
.item-qty { width: 50px; flex-shrink: 0; }
.item-qty span {
  display: inline-block;
  background: ${accentColor}1A;
  color: $accentColor;
  font-weight: 700;
  font-size: 16px;
  padding: 4px 8px;
  border-radius: 6px;
  text-align: center;
  min-width: 36px;
}
.item-details { flex: 1; margin: 0 12px; }
.item-name { font-size: 16px; font-weight: 500; }
.item-comp { font-size: 12px; color: $subtextColor; margin-top: 4px; }
.item-note { font-size: 12px; font-style: italic; color: $subtextColor; margin-top: 4px; }
.item-price { font-size: 16px; font-weight: 600; text-align: end; flex-shrink: 0; min-width: 0; white-space: nowrap; }
.summary {
  background: $cardColor;
  border-radius: 16px;
  padding: 24px;
  box-shadow: 0 4px 10px rgba(0,0,0,0.05);
}
.summary-row {
  display: flex;
  justify-content: space-between;
  margin-bottom: 8px;
  font-size: 16px;
  color: $subtextColor;
}
.summary-row span:last-child { font-weight: 500; }
.summary-divider { border: none; border-top: 1px solid $borderColor; margin: 12px 0; }
.total-box {
  background: $accentColor;
  border-radius: 12px;
  padding: 16px 24px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: 12px;
}
.total-label { color: #FFF; font-size: 24px; font-weight: 700; }
.total-value { color: #FFF; font-size: 28px; font-weight: 700; }
.welcome {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100vh;
  gap: 24px;
}
.welcome-icon { font-size: 120px; color: ${accentColor}99; }
.welcome-title { font-size: 48px; font-weight: 700; letter-spacing: 1.2px; }
.welcome-sub { font-size: 20px; color: $subtextColor; }
.col-qty { width: 50px; }
.col-item { flex: 1; }
.col-price { text-align: end; min-width: 100px; }
#order-view { display: none; }
#welcome-view { display: flex; }
.discount-row { color: #E17055 !important; }
.discount-row span { color: #E17055 !important; }
@keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: none; } }
.fade-in { animation: fadeIn 0.4s ease; }

/* === Responsive: tablets & big phones in portrait === */
@media (max-width: 720px) {
  .container { padding: 14px; gap: 10px; }
  .header { padding: 12px 14px; flex-direction: column; align-items: stretch; gap: 8px; }
  .header-left { gap: 12px; }
  .header-icon { font-size: 24px; }
  .header-title { font-size: 18px; }
  .header-code { font-size: 12px; }
  .order-type { padding: 6px 12px; font-size: 12px; align-self: flex-start; }
  .items-header { padding: 10px 12px; font-size: 12px; }
  .item { padding: 8px 12px; }
  .item-qty, .col-qty { width: 36px; }
  .item-qty span { min-width: 28px; font-size: 14px; padding: 3px 6px; }
  .item-details { margin: 0 10px; }
  .item-name { font-size: 14px; }
  .item-comp, .item-note { font-size: 11px; }
  .item-price, .col-price { min-width: 68px; font-size: 14px; }
  .summary { padding: 14px; }
  .summary-row { font-size: 14px; }
  .total-box { padding: 12px 14px; }
  .total-label { font-size: 18px; }
  .total-value { font-size: 22px; }
  .welcome { gap: 14px; }
  .welcome-icon { font-size: 80px; }
  .welcome-title { font-size: 28px; letter-spacing: 0.6px; }
  .welcome-sub { font-size: 14px; }
}

/* === Responsive: phones in portrait / split-screen === */
@media (max-width: 420px) {
  .container { padding: 10px; gap: 8px; }
  .header { padding: 10px 12px; gap: 6px; }
  .header-left { gap: 10px; }
  .header-icon { font-size: 22px; }
  .header-title { font-size: 16px; }
  .header-code { font-size: 11px; }
  .order-type { padding: 4px 10px; font-size: 11px; }
  .items-header { padding: 8px 10px; font-size: 11px; }
  .item { padding: 8px 10px; }
  .item-qty, .col-qty { width: 30px; }
  .item-qty span { min-width: 28px; font-size: 12px; padding: 2px 5px; }
  .item-details { margin: 0 8px; }
  .item-name { font-size: 13px; }
  .item-comp, .item-note { font-size: 10px; }
  .item-price, .col-price { min-width: 56px; font-size: 13px; }
  .summary { padding: 12px; }
  .summary-row { font-size: 13px; }
  .summary-divider { margin: 8px 0; }
  .total-box { padding: 10px 12px; }
  .total-label { font-size: 16px; }
  .total-value { font-size: 20px; }
  .welcome-icon { font-size: 56px; }
  .welcome-title { font-size: 22px; letter-spacing: 0.4px; }
  .welcome-sub { font-size: 12px; }
}

/* === Responsive: landscape phones — trim vertical space only === */
@media (max-height: 480px) {
  .container { padding-top: 10px; padding-bottom: 10px; gap: 8px; }
  .header { padding-top: 10px; padding-bottom: 10px; }
  .summary { padding-top: 10px; padding-bottom: 10px; }
  .total-box { padding-top: 8px; padding-bottom: 8px; }
  .welcome { gap: 12px; }
  .welcome-icon { font-size: 56px; }
  .welcome-title { font-size: 24px; }
  .welcome-sub { font-size: 13px; }
}
</style>
</head>
<body>

<div id="welcome-view" class="welcome">
  <div class="welcome-icon">🏪</div>
  <div class="welcome-title" id="welcome-name">${businessName.isNotEmpty ? _escapeHtml(businessName) : t['welcome']}</div>
  ${businessName.isNotEmpty ? "<div class='welcome-sub'>${t['thank_you'] ?? ''}</div>" : ''}
</div>

<div id="order-view" class="container">
  <div class="header">
    <div class="header-left">
      <div class="header-icon">🧾</div>
      <div>
        <div class="header-title">${t['your_order']}</div>
        <div class="header-code" id="order-code"></div>
      </div>
    </div>
    <div class="order-type" id="order-type"></div>
  </div>

  <div class="items-container">
    <div class="items-header">
      <div class="col-qty">${t['qty']}</div>
      <div class="col-item">${t['item']}</div>
      <div class="col-price">${t['price']}</div>
    </div>
    <div class="items-list" id="items-list"></div>
  </div>

  <div class="summary">
    <div class="summary-row">
      <span>${t['subtotal']}</span>
      <span id="subtotal">0.00 $currency</span>
    </div>
    <div class="summary-row">
      <span>${t['tax']}</span>
      <span id="tax">0.00 $currency</span>
    </div>
    <div class="summary-row discount-row" id="discount-row" style="display:none">
      <span>${t['discount']}</span>
      <span id="discount">-0.00 $currency</span>
    </div>
    <hr class="summary-divider">
    <div class="total-box">
      <span class="total-label">${t['total']}</span>
      <span class="total-value" id="total">0.00 $currency</span>
    </div>
  </div>
</div>

<script>
const currency = '$currency';
const typeLabels = {
  'DINE_IN': '${t['dine_in']}',
  'TAKE_AWAY': '${t['take_away']}',
  'DELIVERY': '${t['delivery']}'
};

function fmt(n) { return n.toFixed(2) + ' ' + currency; }

function renderOrder(d) {
  if (d.action === 'clear') {
    document.getElementById('order-view').style.display = 'none';
    document.getElementById('welcome-view').style.display = 'flex';
    return;
  }
  if (d.action === 'update_business') {
    document.getElementById('welcome-name').textContent = d.businessName || '${t['welcome']}';
    return;
  }

  document.getElementById('welcome-view').style.display = 'none';
  document.getElementById('order-view').style.display = 'flex';
  document.getElementById('order-view').classList.add('fade-in');

  document.getElementById('order-code').textContent = d.orderCode ? '#' + d.orderCode : '';
  document.getElementById('order-type').textContent = typeLabels[d.orderType] || '';

  var list = document.getElementById('items-list');
  list.innerHTML = '';
  (d.items || []).forEach(function(item) {
    var div = document.createElement('div');
    div.className = 'item' + (item.isPaid ? ' paid' : '');
    var comps = '';
    if (item.components && item.components.length) {
      comps = item.components.map(function(c) { return '+ ' + c.name + ' (' + c.quantity + ')'; }).join('<br>');
      comps = '<div class="item-comp">' + comps + '</div>';
    }
    var note = '';
    if (item.note) {
      note = '<div class="item-note">' + item.note + '</div>';
    }
    div.innerHTML =
      '<div class="item-qty"><span>' + item.quantity + '</span></div>' +
      '<div class="item-details"><div class="item-name">' + item.name + '</div>' + comps + note + '</div>' +
      '<div class="item-price">' + fmt(item.price) + '</div>';
    list.appendChild(div);
  });

  document.getElementById('subtotal').textContent = fmt(d.subtotal || 0);
  document.getElementById('tax').textContent = fmt(d.tax || 0);
  if (d.discount && d.discount > 0) {
    document.getElementById('discount-row').style.display = 'flex';
    document.getElementById('discount').textContent = '-' + fmt(d.discount);
  } else {
    document.getElementById('discount-row').style.display = 'none';
  }
  document.getElementById('total').textContent = fmt(d.total || 0);
}

var evtSource = new EventSource('/events');
var sseWorking = false;
evtSource.onmessage = function(e) {
  try {
    sseWorking = true;
    var data = JSON.parse(e.data);
    renderOrder(data);
  } catch(err) { console.error('Parse error:', err); }
};
evtSource.onerror = function() {
  sseWorking = false;
  console.log('SSE connection lost, reconnecting...');
};

// Polling fallback: if SSE is not working, poll every 1 second
setInterval(function() {
  if (!sseWorking) {
    fetch('/data').then(function(r) { return r.json(); }).then(renderOrder).catch(function(){});
  }
}, 1000);

// Also poll periodically as a safety net even if SSE is working
setInterval(function() {
  fetch('/data').then(function(r) { return r.json(); }).then(renderOrder).catch(function(){});
}, 3000);

fetch('/data').then(function(r) { return r.json(); }).then(renderOrder).catch(console.error);
</script>
</body>
</html>''';
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  Map<String, String> _getTranslations(String lang) {
    switch (lang) {
      case 'ar':
        return {
          'welcome': 'مرحبا بكم',
          'your_order': 'طلبكم',
          'subtotal': 'المجموع الفرعي',
          'tax': 'الضريبة',
          'discount': 'الخصم',
          'total': 'المجموع',
          'thank_you': 'شكراً لزيارتكم',
          'qty': 'الكمية',
          'item': 'المنتج',
          'price': 'السعر',
          'dine_in': 'في المطعم',
          'take_away': 'للأخذ',
          'delivery': 'توصيل',
        };
      case 'fr':
        return {
          'welcome': 'Bienvenue',
          'your_order': 'Votre commande',
          'subtotal': 'Sous-total',
          'tax': 'TVA',
          'discount': 'Remise',
          'total': 'Total',
          'thank_you': 'Merci de votre visite',
          'qty': 'Qté',
          'item': 'Article',
          'price': 'Prix',
          'dine_in': 'Sur place',
          'take_away': 'À emporter',
          'delivery': 'Livraison',
        };
      default:
        return {
          'welcome': 'Welcome',
          'your_order': 'Your Order',
          'subtotal': 'Subtotal',
          'tax': 'Tax',
          'discount': 'Discount',
          'total': 'Total',
          'thank_you': 'Thank you for your visit',
          'qty': 'Qty',
          'item': 'Item',
          'price': 'Price',
          'dine_in': 'Dine In',
          'take_away': 'Take Away',
          'delivery': 'Delivery',
        };
    }
  }
}

/// Provider for the customer display service
final customerDisplayServiceProvider = Provider<CustomerDisplayService>((ref) {
  return CustomerDisplayService(ref);
});

/// Provider to track if customer display window is open
final customerDisplayOpenProvider = StateProvider<bool>((ref) => false);







