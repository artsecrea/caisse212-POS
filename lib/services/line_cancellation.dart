import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database/app_database.dart';

/// Keeps a copy of [row] in `cancelled_order_lines` before it is deleted, so
/// the v2 order push still carries it as a cancelled line (state CANCELED,
/// canceledQuantity = everything ever taken off it). The caller deletes the
/// row and its components afterwards, exactly as before.
///
/// [by] is a POS user id. A waiter's removal passes null: waiter ids are not
/// user ids, and the server resolves `canceledBy` against its users.
Future<void> keepCancelledLine(
  AppDatabase db,
  OrderProduct row, {
  int? by,
  DateTime? at,
}) async {
  final components = await (db.select(db.orderProductComponents)
        ..where((c) => c.orderProductId.equals(row.id)))
      .get();
  await db.into(db.cancelledOrderLines).insert(
        CancelledOrderLinesCompanion.insert(
          orderId: row.orderId,
          lineUid: Value(row.lineUid),
          serverId: Value(row.serverId),
          productId: row.productId,
          variantId: Value(row.variantId),
          quantity: row.quantity,
          canceledQuantity: row.canceledQuantity + row.quantity,
          unitaryPrice: row.unitaryPrice,
          unitaryDiscount: Value(row.unitaryDiscount),
          unitaryTva: Value(row.unitaryTva),
          manualDiscount: Value(row.manualDiscount),
          cost: Value(row.cost),
          note: Value(row.note),
          saleUomId: Value(row.saleUomId),
          courseNo: Value(row.courseNo),
          zDay: Value(row.zDay),
          componentsJson: Value(jsonEncode([
            for (final c in components)
              {
                'componentId': c.componentId,
                'quantity': c.quantity,
                'price': c.price,
                'isSpecial': c.isSpecial,
                if (c.name != null) 'name': c.name,
                if (c.removalCharge) 'removalCharge': true,
              },
          ])),
          canceledAt: Value(at ?? DateTime.now()),
          canceledBy: Value(by),
        ),
      );
}
