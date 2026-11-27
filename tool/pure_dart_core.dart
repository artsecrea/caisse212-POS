// The libraries a future hub has to share with the till. Each must load
// with plain `dart`, no Flutter: `test/pure_dart_core_test.dart` runs this
// file with `dart run`, which fails on anything that reaches `dart:ui`.
//
// Add a library here once it is Flutter-free; never take one out to make the
// test pass.

// ignore_for_file: unused_import

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/component_rules.dart';
import 'package:caisse212/domain/models/line_payment.dart';
import 'package:caisse212/domain/models/order_money.dart';
import 'package:caisse212/domain/models/order_money_rows.dart';
import 'package:caisse212/domain/models/order_read_models.dart';
import 'package:caisse212/domain/models/permission_rules.dart';
import 'package:caisse212/domain/models/session_rules.dart';
import 'package:caisse212/domain/models/split_bill.dart';
import 'package:caisse212/domain/models/table_occupancy.dart';
import 'package:caisse212/domain/models/ticket_read_models.dart';
import 'package:caisse212/domain/services/cash_session_service.dart';
import 'package:caisse212/domain/services/customer_service.dart';
import 'package:caisse212/domain/services/day_service.dart';
import 'package:caisse212/domain/services/floor_service.dart';
import 'package:caisse212/domain/services/kitchen_service.dart';
import 'package:caisse212/domain/services/order_queries.dart';
import 'package:caisse212/domain/services/order_service.dart';
import 'package:caisse212/domain/services/payment_service.dart';
import 'package:caisse212/domain/services/returns_service.dart';
import 'package:caisse212/domain/services/ticket_queries.dart';
import 'package:caisse212/services/cash_report_sections.dart';
import 'package:caisse212/services/kitchen_timing.dart';
import 'package:caisse212/services/ticket_settlement_service.dart';
import 'package:caisse212/services/waiter_order_money.dart';
import 'package:caisse212/services/z_rules.dart';
import 'package:caisse212/utils/order_code.dart';
import 'package:caisse212/utils/password_check.dart';
import 'package:caisse212/utils/pos_log.dart';
import 'package:loggecrea/loggecrea.dart';

void main() {
  // Loading is the test; there is nothing to run.
}
