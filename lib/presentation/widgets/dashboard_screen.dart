import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/app_localizations.dart';
import '../../utils/error_text.dart';
import 'package:intl/intl.dart';
import '../../data/database/app_database.dart';
import '../../domain/models/order_money.dart';
import '../../domain/models/order_money_rows.dart';
import '../../providers/catalogue_repository.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../providers/ticket_provider.dart';
import '../../utils/currency_formatter.dart';
import 'kds_stats_dialog.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Data model
// ═══════════════════════════════════════════════════════════════════════════

class DashboardStats {
  final int totalOrders;
  final int canceledOrders;
  final Map<String, int> ordersByStatus;
  final Map<String, int> ordersByType;
  final int paidTickets;
  final int unpaidOrders;
  final double paidRevenue;
  final double unpaidRevenue;
  final Map<String, double> revenueByMethod;
  final Map<String, int> countByMethod;
  final List<_TopProduct> topProducts;
  final int totalItems;
  final double avgOrderValue;
  final List<double> hourlyRevenue;
  final double totalItemAutoDiscount;
  final double totalItemManualDiscount;
  final double totalOrderDiscount;

  double get totalDiscount =>
      totalItemAutoDiscount + totalItemManualDiscount + totalOrderDiscount;

  const DashboardStats({
    required this.totalOrders,
    required this.canceledOrders,
    required this.ordersByStatus,
    required this.ordersByType,
    required this.paidTickets,
    required this.unpaidOrders,
    required this.paidRevenue,
    required this.unpaidRevenue,
    required this.revenueByMethod,
    required this.countByMethod,
    required this.topProducts,
    required this.totalItems,
    required this.avgOrderValue,
    required this.hourlyRevenue,
    required this.totalItemAutoDiscount,
    required this.totalItemManualDiscount,
    required this.totalOrderDiscount,
  });
}

class _TopProduct {
  final String name;
  final int qty;
  final double revenue;
  const _TopProduct(this.name, this.qty, this.revenue);
}

// ═══════════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════════

final _dashboardStatsProvider =
    FutureProvider.autoDispose.family<DashboardStats, _DashboardKey>(
        (ref, key) async {
  final orderRepo = ref.watch(orderRepositoryProvider);
  final ticketRepo = ref.watch(ticketRepositoryProvider);
  final catalogue = ref.watch(catalogueRepositoryProvider);
  final dayStart = DateTime(key.date.year, key.date.month, key.date.day);
  final dayEnd = dayStart.add(const Duration(days: 1));

  // 1. Orders for the user on that day (createdBy OR takenBy)
  final allOrders = await orderRepo.ordersCreatedBetween(dayStart, dayEnd,
      userId: key.userId);

  // statuses
  final Map<String, int> byStatus = {};
  final Map<String, int> byType = {};
  int canceled = 0;
  for (final o in allOrders) {
    byStatus[o.status] = (byStatus[o.status] ?? 0) + 1;
    byType[o.type] = (byType[o.type] ?? 0) + 1;
    if (o.status == 'CANCELED') canceled++;
  }

  final orderIds = allOrders.map((o) => o.id).toList();

  // 2. Tickets linked to these orders
  final tickets = await ticketRepo.ticketsForOrders(orderIds);

  // Which orders have at least one non-cancelled paid ticket
  final Set<int> paidOrderIds = {};
  int paid = 0;
  double paidRev = 0;
  final Map<String, double> revByMethod = {};
  final Map<String, int> cntByMethod = {};
  final List<double> hourlyRev = List.filled(24, 0.0);

  for (final tk in tickets) {
    if (tk.isCancelled) continue;
    if (tk.isPaid) {
      paidOrderIds.add(tk.orderId);
      paid++;
      paidRev += tk.amount;
      revByMethod[tk.paymentMethod] =
          (revByMethod[tk.paymentMethod] ?? 0) + tk.amount;
      cntByMethod[tk.paymentMethod] =
          (cntByMethod[tk.paymentMethod] ?? 0) + 1;
      hourlyRev[tk.date.hour] += tk.amount;
    }
  }

  // 3. Order products + their components
  final orderProducts = await orderRepo.linesForOrders(orderIds);

  // Build a map: orderProductId → total component cost
  final Map<int, double> componentCostById = {};
  final comps =
      await orderRepo.componentsOfLines(orderProducts.map((op) => op.id));
  for (final c in comps) {
    componentCostById[c.orderProductId] =
        (componentCostById[c.orderProductId] ?? 0.0) + c.price * c.quantity;
  }

  // unitaryPrice is already post-auto-discount (finalPrice stored at order time).
  // manualDiscount is an additional cashier-applied discount per unit.
  // Do NOT subtract unitaryDiscount again here — it is already baked into unitaryPrice.
  double opLineTotal(OrderProduct op) =>
      op.amounts(componentsPerUnit: componentCostById[op.id] ?? 0.0).net;

  // Map orderId → Order for discount-percentage lookup
  final orderById = {for (final o in allOrders) o.id: o};

  // Per-order line subtotals (before order-level %)
  final Map<int, double> orderLineSubtotals = {};
  // A cancelled line is neither sold nor owed — unless it was paid first.
  final owedProducts = orderProducts
      .where((op) => lineCountsInTotal(op.state, paid: op.ticketId != null))
      .toList();
  for (final op in owedProducts) {
    orderLineSubtotals[op.orderId] =
        (orderLineSubtotals[op.orderId] ?? 0.0) + opLineTotal(op);
  }

  // Unpaid revenue: apply order-level discount percentage
  int unpaid = 0;
  double unpaidRev = 0;
  final Set<int> unpaidOrderIds =
      orderIds.where((id) => !paidOrderIds.contains(id)).toSet();
  for (final orderId in unpaidOrderIds) {
    final lineTotal = orderLineSubtotals[orderId] ?? 0.0;
    final pct = orderById[orderId]?.discountPercentage ?? 0.0;
    unpaidRev += applyOrderDiscount(lineTotal, pct);
  }
  unpaid = unpaidOrderIds.length;

  // Discount accumulation (all non-cancelled orders)
  double itemAutoDisc = 0.0;
  double itemManualDisc = 0.0;
  double orderPercentDisc = 0.0;
  for (final op in owedProducts) {
    final order = orderById[op.orderId];
    if (order?.status == 'CANCELED') continue;
    itemAutoDisc += op.unitaryDiscount * op.quantity;
    itemManualDisc += op.manualDiscount * op.quantity;
  }
  for (final order in allOrders) {
    if (order.status == 'CANCELED') continue;
    if (order.discountPercentage > 0) {
      final lineTotal = orderLineSubtotals[order.id] ?? 0.0;
      orderPercentDisc +=
          orderDiscountAmount(lineTotal, order.discountPercentage);
    }
  }

  // Top products map (gross line total per product, before order-level %)
  final Map<int, _MutableProduct> prodMap = {};
  for (final op in owedProducts) {
    prodMap[op.productId] ??= _MutableProduct();
    prodMap[op.productId]!.qty += op.quantity.round();
    prodMap[op.productId]!.rev += opLineTotal(op);
  }
  // Resolve names
  final topProds = <_TopProduct>[];
  for (final entry in prodMap.entries) {
    final prod = await catalogue.productById(entry.key);
    topProds.add(_TopProduct(
        prod?.name ?? '#${entry.key}', entry.value.qty, entry.value.rev));
  }
  topProds.sort((a, b) => b.qty.compareTo(a.qty));

  final totalItems = orderProducts.fold<int>(0, (s, op) => s + op.quantity.round());

  return DashboardStats(
    totalOrders: allOrders.length,
    canceledOrders: canceled,
    ordersByStatus: byStatus,
    ordersByType: byType,
    paidTickets: paid,
    unpaidOrders: unpaid,
    paidRevenue: paidRev,
    unpaidRevenue: unpaidRev,
    revenueByMethod: revByMethod,
    countByMethod: cntByMethod,
    topProducts: topProds.take(6).toList(),
    totalItems: totalItems,
    avgOrderValue: paid == 0 ? 0 : paidRev / paid,
    hourlyRevenue: hourlyRev,
    totalItemAutoDiscount: itemAutoDisc,
    totalItemManualDiscount: itemManualDisc,
    totalOrderDiscount: orderPercentDisc,
  );
});

class _DashboardKey {
  final DateTime date;
  final int? userId;
  const _DashboardKey(this.date, this.userId);
  @override
  bool operator ==(Object other) =>
      other is _DashboardKey &&
      other.date == date &&
      other.userId == userId;
  @override
  int get hashCode => Object.hash(date, userId);
}

class _MutableProduct {
  int qty = 0;
  double rev = 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// Color constants
// ═══════════════════════════════════════════════════════════════════════════

const _methodColors = {
  'CASH': Color(0xFF4CAF50),
  'CARD': Color(0xFF2196F3),
  'MOBILE': Color(0xFF9C27B0),
  'OTHER': Color(0xFF607D8B),
};
const _methodIcons = {
  'CASH': Icons.payments_outlined,
  'CARD': Icons.credit_card_outlined,
  'MOBILE': Icons.phone_android_outlined,
  'OTHER': Icons.more_horiz_outlined,
};
const _statusColors = {
  'ONHOLD': Color(0xFF78909C),
  'PENDING': Color(0xFF2196F3),
  'PREPARING': Color(0xFFFF9800),
  'READY': Color(0xFF8BC34A),
  'DELIVERED': Color(0xFF4CAF50),
  'CANCELED': Color(0xFFF44336),
};
const _typeColors = {
  'DINE_IN': Color(0xFF3F51B5),
  'TAKE_AWAY': Color(0xFF009688),
  'DELIVERY': Color(0xFFFF5722),
};
final _chartPalette = [
  const Color(0xFF5C6BC0),
  const Color(0xFF26A69A),
  const Color(0xFFEF5350),
  const Color(0xFFFFCA28),
  const Color(0xFF66BB6A),
  const Color(0xFFAB47BC),
];

// ═══════════════════════════════════════════════════════════════════════════
// Screen
// ═══════════════════════════════════════════════════════════════════════════

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DateTime _date = DateTime.now();
  int _hoveredTypeIndex = -1;

  void _changeDay(int delta) =>
      setState(() => _date = _date.add(Duration(days: delta)));

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final key = _DashboardKey(
        DateTime(_date.year, _date.month, _date.day), currentUser?.id);
    final statsAsync = ref.watch(_dashboardStatsProvider(key));
    final fmt = ref.watch(currencyFormatterProvider);
    final cs = Theme.of(context).colorScheme;
    final isToday = _isSameDay(_date, DateTime.now());

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.dashboard_outlined, color: cs.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              currentUser != null
                  ? 'Dashboard — ${currentUser.effectiveDisplayName}'
                  : 'Dashboard',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface),
            ),
          ],
        ),
        backgroundColor: cs.surface,
        elevation: 1,
        actions: [
          IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous day',
              onPressed: () => _changeDay(-1)),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isToday
                    ? cs.primaryContainer
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 14,
                      color: isToday ? cs.primary : cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    isToday
                        ? 'Today'
                        : DateFormat('dd MMM yyyy').format(_date),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isToday ? cs.primary : cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next day',
              onPressed: _isSameDay(_date, DateTime.now())
                  ? null
                  : () => _changeDay(1)),
          IconButton(
              icon: const Icon(Icons.insights_outlined),
              tooltip: 'Kitchen stats (current shift)',
              onPressed: () => showKdsStatsDialog(context)),
          IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(_dashboardStatsProvider(key))),
          const SizedBox(width: 8),
        ],
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(errorText(e, AppLocalizations.of(context)!)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => ref.invalidate(_dashboardStatsProvider(key)),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (stats) => _buildBody(context, stats, fmt, cs),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DashboardStats stats,
      CurrencyFormatter fmt, ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── KPI tiles ────────────────────────────────────────
          _sectionLabel('Overview'),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _KpiTile(
                label: 'Total Orders',
                value: '${stats.totalOrders}',
                icon: Icons.receipt_long_outlined,
                color: cs.primary,
                sub: '${stats.canceledOrders} canceled'),
            _KpiTile(
                label: 'Total Items',
                value: '${stats.totalItems}',
                icon: Icons.shopping_bag_outlined,
                color: Colors.indigo),
            _KpiTile(
                label: 'Paid Revenue',
                value: fmt.format(stats.paidRevenue),
                icon: Icons.payments_outlined,
                color: Colors.green.shade600,
                sub: '${stats.paidTickets} ticket(s)'),
            _KpiTile(
                label: 'Unpaid Revenue',
                value: fmt.format(stats.unpaidRevenue),
                icon: Icons.pending_actions_outlined,
                color: Colors.orange.shade700,
                sub: '${stats.unpaidOrders} order(s)'),
            _KpiTile(
                label: 'Avg Order Value',
                value: fmt.format(stats.avgOrderValue),
                icon: Icons.trending_up_outlined,
                color: Colors.teal.shade600,
                sub: 'paid only'),
            if (stats.totalDiscount > 0)
              _KpiTile(
                  label: 'Total Discounts',
                  value: fmt.format(stats.totalDiscount),
                  icon: Icons.local_offer_outlined,
                  color: Colors.deepOrange.shade400,
                  sub: 'given today'),
          ]),
          const SizedBox(height: 24),

          // ── Discount breakdown ────────────────────────────────
          if (stats.totalDiscount > 0) ...[
            _sectionLabel('Discount Breakdown'),
            const SizedBox(height: 10),
            _card(child: _DiscountBreakdownCard(stats: stats, fmt: fmt, cs: cs)),
            const SizedBox(height: 24),
          ],

          // ── Hourly revenue line chart ─────────────────────────
          if (stats.paidRevenue > 0) ...[
            _sectionLabel('Revenue by Hour'),
            const SizedBox(height: 10),
            _card(child: _HourlyRevenueChart(stats: stats, fmt: fmt, cs: cs)),
            const SizedBox(height: 24),
          ],

          // ── Payment breakdown ──────────────────────────────────
          _sectionLabel('Payment Breakdown'),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: _card(
                    child: _PaidDonutChart(
                        stats: stats, fmt: fmt, cs: cs))),
            const SizedBox(width: 14),
            Expanded(
                flex: 2,
                child: _card(
                    child: _PaymentMethodChart(
                        stats: stats, fmt: fmt, cs: cs))),
          ]),
          const SizedBox(height: 24),

          // ── Orders ─────────────────────────────────────────────
          _sectionLabel('Orders'),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                flex: 2,
                child: _card(
                    child: _StatusBarChart(stats: stats, cs: cs))),
            const SizedBox(width: 14),
            Expanded(
                child: _card(
                    child: _TypeDonutChart(
                        stats: stats,
                        cs: cs,
                        hoveredIndex: _hoveredTypeIndex,
                        onHover: (i) =>
                            setState(() => _hoveredTypeIndex = i)))),
          ]),
          const SizedBox(height: 24),

          // ── Top products ───────────────────────────────────────
          if (stats.topProducts.isNotEmpty) ...[
            _sectionLabel('Top Products (by qty sold)'),
            const SizedBox(height: 10),
            _card(
                child: _TopProductsChart(
                    stats: stats, fmt: fmt, cs: cs)),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.6),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// KPI Tile
// ═══════════════════════════════════════════════════════════════════════════

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? sub;

  const _KpiTile(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      this.sub});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface)),
            if (sub != null)
              Text(sub!,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Hourly Revenue Line Chart
// ═══════════════════════════════════════════════════════════════════════════

class _HourlyRevenueChart extends StatelessWidget {
  final DashboardStats stats;
  final CurrencyFormatter fmt;
  final ColorScheme cs;
  const _HourlyRevenueChart(
      {required this.stats, required this.fmt, required this.cs});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var h = 0; h < 24; h++) {
      if (stats.hourlyRevenue[h] > 0) {
        spots.add(FlSpot(h.toDouble(), stats.hourlyRevenue[h]));
      }
    }
    if (spots.isEmpty) spots.add(const FlSpot(0, 0));
    final maxY =
        stats.hourlyRevenue.fold<double>(0, (m, v) => v > m ? v : m) * 1.25;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Hourly Revenue'),
      const SizedBox(height: 16),
      SizedBox(
        height: 170,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: 23,
            minY: 0,
            maxY: maxY == 0 ? 100 : maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY == 0 ? 50 : maxY / 4,
              getDrawingHorizontalLine: (v) => FlLine(
                color: cs.outlineVariant.withValues(alpha: 0.4),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 56,
                  getTitlesWidget: (v, _) => Text(
                    fmt.format(v),
                    style:
                        TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 3,
                  getTitlesWidget: (v, _) => Text(
                    '${v.toInt()}h',
                    style:
                        TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: cs.primary,
                barWidth: 2.5,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                    radius: 3,
                    color: cs.primary,
                    strokeWidth: 1.5,
                    strokeColor: cs.surface,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.25),
                      cs.primary.withValues(alpha: 0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => cs.inverseSurface,
                getTooltipItems: (touchedSpots) => touchedSpots
                    .map((s) => LineTooltipItem(
                          '${s.x.toInt()}:00\n${fmt.format(s.y)}',
                          TextStyle(
                              color: cs.onInverseSurface,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Paid vs Unpaid donut
// ═══════════════════════════════════════════════════════════════════════════

class _PaidDonutChart extends StatefulWidget {
  final DashboardStats stats;
  final CurrencyFormatter fmt;
  final ColorScheme cs;
  const _PaidDonutChart(
      {required this.stats, required this.fmt, required this.cs});
  @override
  State<_PaidDonutChart> createState() => _PaidDonutChartState();
}

class _PaidDonutChartState extends State<_PaidDonutChart> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final total = widget.stats.paidRevenue + widget.stats.unpaidRevenue;
    final hasUnpaid = widget.stats.unpaidRevenue > 0;
    final sections = [
      PieChartSectionData(
        value: widget.stats.paidRevenue == 0 ? (total == 0 ? 1 : 0) : widget.stats.paidRevenue,
        color: Colors.green.shade500,
        title: total == 0 ? '' : '${(widget.stats.paidRevenue / total * 100).toStringAsFixed(0)}%',
        radius: _touched == 0 ? 54 : 44,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      PieChartSectionData(
        value: hasUnpaid ? widget.stats.unpaidRevenue : (total == 0 ? 1 : 0),
        color: hasUnpaid ? Colors.orange.shade400 : Theme.of(context).colorScheme.surfaceContainerHighest,
        title: (total == 0 || !hasUnpaid) ? '' : '${(widget.stats.unpaidRevenue / total * 100).toStringAsFixed(0)}%',
        radius: _touched == 1 ? 54 : 44,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Paid vs Unpaid'),
      const SizedBox(height: 12),
      SizedBox(
        height: 160,
        child: PieChart(
          PieChartData(
            sections: sections,
            centerSpaceRadius: 38,
            sectionsSpace: 2,
            pieTouchData: PieTouchData(
              touchCallback: (ev, res) => setState(() {
                _touched = (!ev.isInterestedForInteractions ||
                        res == null ||
                        res.touchedSection == null)
                    ? -1
                    : res.touchedSection!.touchedSectionIndex;
              }),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      _legend(Colors.green.shade500, 'Paid',
          widget.fmt.format(widget.stats.paidRevenue),
          '${widget.stats.paidTickets} tickets'),
      const SizedBox(height: 4),
      _legend(Colors.orange.shade400, 'Unpaid',
          widget.fmt.format(widget.stats.unpaidRevenue),
          '${widget.stats.unpaidOrders} orders'),
    ]);
  }

  Widget _legend(Color dot, String label, String amount, String sub) => Row(
        children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              Text(sub,
                  style: TextStyle(
                      fontSize: 9, color: widget.cs.onSurfaceVariant)),
            ],
          ),
        ],
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Payment Method bar chart
// ═══════════════════════════════════════════════════════════════════════════

class _PaymentMethodChart extends StatelessWidget {
  final DashboardStats stats;
  final CurrencyFormatter fmt;
  final ColorScheme cs;
  const _PaymentMethodChart(
      {required this.stats, required this.fmt, required this.cs});

  @override
  Widget build(BuildContext context) {
    final methods = stats.revenueByMethod.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = methods.isEmpty ? 1.0 : methods.first.value;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('By Payment Method'),
      const SizedBox(height: 14),
      if (methods.isEmpty)
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No paid transactions',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        )
      else ...[
        SizedBox(
          height: max(160.0, methods.length * 60.0),
          child: BarChart(
            BarChartData(
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => cs.inverseSurface,
                  getTooltipItem: (group, _, rod, __) {
                    final method = methods[group.x].key;
                    final cnt = stats.countByMethod[method] ?? 0;
                    return BarTooltipItem(
                      '$method\n${fmt.format(rod.toY)}\n$cnt tx',
                      TextStyle(
                          color: cs.onInverseSurface,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    );
                  },
                ),
              ),
              alignment: BarChartAlignment.spaceAround,
              maxY: maxVal * 1.3,
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= methods.length) {
                        return const SizedBox.shrink();
                      }
                      final key = methods[i].key;
                      final color =
                          _methodColors[key] ?? const Color(0xFF607D8B);
                      final icon =
                          _methodIcons[key] ?? Icons.payment_outlined;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(icon, size: 16, color: color),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 56,
                    getTitlesWidget: (v, _) => Text(
                      fmt.format(v),
                      style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: methods.asMap().entries.map((e) {
                final color =
                    _methodColors[e.value.key] ?? const Color(0xFF607D8B);
                return BarChartGroupData(x: e.key, barRods: [
                  BarChartRodData(
                    toY: e.value.value,
                    color: color,
                    width: 30,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(6)),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxVal * 1.3,
                      color: color.withValues(alpha: 0.08),
                    ),
                  ),
                ]);
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: methods.map((e) {
            final color =
                _methodColors[e.key] ?? const Color(0xFF607D8B);
            final cnt = stats.countByMethod[e.key] ?? 0;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${e.key}  ${fmt.format(e.value)}  ($cnt tx)',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color),
              ),
            );
          }).toList(),
        ),
      ],
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Orders by Status bar chart
// ═══════════════════════════════════════════════════════════════════════════

class _StatusBarChart extends StatelessWidget {
  final DashboardStats stats;
  final ColorScheme cs;
  const _StatusBarChart({required this.stats, required this.cs});

  @override
  Widget build(BuildContext context) {
    final entries = stats.ordersByStatus.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxY =
        entries.isEmpty ? 1.0 : entries.first.value.toDouble() * 1.35;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Orders by Status'),
      const SizedBox(height: 14),
      if (entries.isEmpty)
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No orders',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        )
      else
        SizedBox(
          height: max(140.0, entries.length * 52.0),
          child: BarChart(
            BarChartData(
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => cs.inverseSurface,
                  getTooltipItem: (group, _, rod, __) {
                    return BarTooltipItem(
                      '${entries[group.x].key}\n${rod.toY.toInt()} orders',
                      TextStyle(
                          color: cs.onInverseSurface,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    );
                  },
                ),
              ),
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= entries.length) {
                        return const SizedBox.shrink();
                      }
                      final s = entries[i].key;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          s.length > 7 ? s.substring(0, 7) : s,
                          style: TextStyle(
                              fontSize: 8, color: cs.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: 1,
                    getTitlesWidget: (v, _) {
                      if (v % 1 != 0) return const SizedBox.shrink();
                      return Text(v.toInt().toString(),
                          style: TextStyle(
                              fontSize: 9, color: cs.onSurfaceVariant));
                    },
                  ),
                ),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                checkToShowHorizontalLine: (v) => v % 1 == 0,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: entries.asMap().entries.map((e) {
                final color = _statusColors[e.value.key] ??
                    _chartPalette[e.key % _chartPalette.length];
                return BarChartGroupData(x: e.key, barRods: [
                  BarChartRodData(
                    toY: e.value.value.toDouble(),
                    color: color,
                    width: 26,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(6)),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxY,
                      color: color.withValues(alpha: 0.07),
                    ),
                  ),
                ]);
              }).toList(),
            ),
          ),
        ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Order type donut
// ═══════════════════════════════════════════════════════════════════════════

class _TypeDonutChart extends StatelessWidget {
  final DashboardStats stats;
  final ColorScheme cs;
  final int hoveredIndex;
  final ValueChanged<int> onHover;

  const _TypeDonutChart({
    required this.stats,
    required this.cs,
    required this.hoveredIndex,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final entries = stats.ordersByType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (s, e) => s + e.value);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('By Type'),
      const SizedBox(height: 12),
      if (entries.isEmpty)
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No orders',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        )
      else ...[
        SizedBox(
          height: 150,
          child: PieChart(
            PieChartData(
              sections: entries.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                final color = _typeColors[e.key] ??
                    _chartPalette[i % _chartPalette.length];
                final pct =
                    total == 0 ? 0.0 : e.value / total * 100;
                return PieChartSectionData(
                  value: e.value.toDouble(),
                  color: color,
                  title: '${pct.toStringAsFixed(0)}%',
                  radius: hoveredIndex == i ? 54 : 44,
                  titleStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                );
              }).toList(),
              centerSpaceRadius: 30,
              sectionsSpace: 2,
              pieTouchData: PieTouchData(
                touchCallback: (ev, res) {
                  onHover((!ev.isInterestedForInteractions ||
                          res == null ||
                          res.touchedSection == null)
                      ? -1
                      : res.touchedSection!.touchedSectionIndex);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        ...entries.asMap().entries.map((entry) {
          final i = entry.key;
          final e = entry.value;
          final color =
              _typeColors[e.key] ?? _chartPalette[i % _chartPalette.length];
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(e.key.replaceAll('_', ' '),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w500))),
              Text('${e.value}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ]),
          );
        }),
      ],
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Top products bar chart
// ═══════════════════════════════════════════════════════════════════════════

class _TopProductsChart extends StatelessWidget {
  final DashboardStats stats;
  final CurrencyFormatter fmt;
  final ColorScheme cs;
  const _TopProductsChart(
      {required this.stats, required this.fmt, required this.cs});

  @override
  Widget build(BuildContext context) {
    final prods = stats.topProducts;
    final maxQty = prods.isEmpty ? 1.0 : prods.first.qty.toDouble();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Top Products'),
      const SizedBox(height: 14),
      SizedBox(
        height: max(160.0, prods.length * 54.0),
        child: BarChart(
          BarChartData(
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => cs.inverseSurface,
                getTooltipItem: (group, _, rod, __) {
                  final p = prods[group.x];
                  return BarTooltipItem(
                    '${p.name}\n${rod.toY.toInt()} sold\n${fmt.format(p.revenue)}',
                    TextStyle(
                        color: cs.onInverseSurface,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  );
                },
              ),
            ),
            alignment: BarChartAlignment.spaceAround,
            maxY: maxQty * 1.35,
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= prods.length) {
                      return const SizedBox.shrink();
                    }
                    final name = prods[i].name;
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        name.length > 10
                            ? '${name.substring(0, 9)}…'
                            : name,
                        style: TextStyle(
                            fontSize: 8, color: cs.onSurfaceVariant),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  interval: max(1.0, (maxQty / 4).floorToDouble()),
                  getTitlesWidget: (v, _) {
                    if (v % 1 != 0) return const SizedBox.shrink();
                    return Text(v.toInt().toString(),
                        style: TextStyle(
                            fontSize: 9, color: cs.onSurfaceVariant));
                  },
                ),
              ),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              checkToShowHorizontalLine: (v) => v % 1 == 0,
              getDrawingHorizontalLine: (v) => FlLine(
                color: cs.outlineVariant.withValues(alpha: 0.4),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: prods.asMap().entries.map((entry) {
              final color =
                  _chartPalette[entry.key % _chartPalette.length];
              return BarChartGroupData(x: entry.key, barRods: [
                BarChartRodData(
                  toY: entry.value.qty.toDouble(),
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.55)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  width: 30,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6)),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxQty * 1.35,
                    color: color.withValues(alpha: 0.07),
                  ),
                ),
              ]);
            }).toList(),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: prods.asMap().entries.map((entry) {
          final color = _chartPalette[entry.key % _chartPalette.length];
          final p = entry.value;
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              '${p.name}  ×${p.qty}  ${fmt.format(p.revenue)}',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color),
            ),
          );
        }).toList(),
      ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Discount Breakdown Card
// ═══════════════════════════════════════════════════════════════════════════

class _DiscountBreakdownCard extends StatelessWidget {
  final DashboardStats stats;
  final CurrencyFormatter fmt;
  final ColorScheme cs;
  const _DiscountBreakdownCard(
      {required this.stats, required this.fmt, required this.cs});

  @override
  Widget build(BuildContext context) {
    final total = stats.totalDiscount;
    final rows = [
      _DiscountRow('Auto (price rules)', stats.totalItemAutoDiscount,
          const Color(0xFF5C6BC0)),
      _DiscountRow('Manual (cashier)', stats.totalItemManualDiscount,
          const Color(0xFFEF5350)),
      _DiscountRow('Order % discount', stats.totalOrderDiscount,
          const Color(0xFFFF9800)),
    ].where((r) => r.amount > 0).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _cardTitle('Discounts Given'),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.deepOrange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Total: ${fmt.format(total)}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.deepOrange),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      ...rows.map((row) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: row.color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(row.label,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurface))),
                    Text(fmt.format(row.amount),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: row.color)),
                    const SizedBox(width: 8),
                    Text(
                      total == 0
                          ? ''
                          : '${(row.amount / total * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ]),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : row.amount / total,
                      minHeight: 6,
                      backgroundColor:
                          row.color.withValues(alpha: 0.12),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(row.color),
                    ),
                  ),
                ]),
          )),
    ]);
  }
}

class _DiscountRow {
  final String label;
  final double amount;
  final Color color;
  const _DiscountRow(this.label, this.amount, this.color);
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared helpers
// ═══════════════════════════════════════════════════════════════════════════

Widget _card({required Widget child}) => Builder(
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: child,
        );
      },
    );

Widget _cardTitle(String text) => Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    );







