import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/services/printing_service.dart';

/// Per-station ticket scope, against the arrangement it was built for:
/// four stations — bar, pizza, burger, chief (the pass).
///
///   * chief  — whole order, always
///   * pizza  — whole order when it is cooking
///   * burger — whole order when it is cooking
///   * bar    — its own items, and private: drinks stay off everyone else's
///              paper
///
/// These pin the rule storage and its defaults. The routing that consumes it
/// needs a printer, so what is testable here is that the configuration
/// survives a round trip and that an unconfigured shop is unchanged.

void main() {
  late PrintingService service;
  late SharedPreferences prefs;

  const bar = 1;
  const pizza = 2;
  const burger = 3;
  const chief = 4;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = PrintingService();
    await service.saveConfig(prefs, const PrinterConfig());
    await service.saveStationRules(prefs, {});
  });

  group('an unconfigured shop is untouched', () {
    test('every station keeps its own items', () {
      expect(service.ruleForStation(pizza).scope, StationTicketScope.ownItems);
      expect(service.ruleForStation(pizza).private, isFalse);
    });

    test('a station nobody has heard of gets the default, not an error', () {
      expect(service.ruleForStation(999).scope, StationTicketScope.ownItems);
    });

    test('the no-station bucket gets the default', () {
      expect(service.ruleForStation(null).scope, StationTicketScope.ownItems);
    });
  });

  group('the four-station arrangement round-trips', () {
    setUp(() async {
      await service.saveStationRules(prefs, {
        bar: const StationTicketRule(private: true),
        pizza: const StationTicketRule(
            scope: StationTicketScope.wholeOrderWhenUsed),
        burger: const StationTicketRule(
            scope: StationTicketScope.wholeOrderWhenUsed),
        chief: const StationTicketRule(
            scope: StationTicketScope.wholeOrderAlways),
      });
    });

    test('each station keeps what it was given', () {
      expect(service.ruleForStation(bar).private, isTrue);
      expect(service.ruleForStation(bar).scope, StationTicketScope.ownItems);
      expect(service.ruleForStation(pizza).scope,
          StationTicketScope.wholeOrderWhenUsed);
      expect(service.ruleForStation(chief).scope,
          StationTicketScope.wholeOrderAlways);
    });

    test('it survives a reload from prefs', () async {
      final reloaded = PrintingService();
      await reloaded.saveConfig(
          await SharedPreferences.getInstance(), const PrinterConfig());
      expect(reloaded.ruleForStation(chief).scope,
          StationTicketScope.wholeOrderAlways);
      expect(reloaded.ruleForStation(bar).private, isTrue);
    });
  });

  group('defaults are stored as absence', () {
    test('a default rule is not written', () async {
      await service.saveStationRules(prefs, {
        pizza: const StationTicketRule(),
        bar: const StationTicketRule(private: true),
      });
      expect(service.stationRules.containsKey(pizza), isFalse,
          reason: 'unconfigured must stay a plain absence');
      expect(service.stationRules.containsKey(bar), isTrue);
    });

    test('clearing a station back to default removes it', () async {
      await service.saveStationRules(
          prefs, {bar: const StationTicketRule(private: true)});
      expect(service.stationRules, isNotEmpty);
      await service
          .saveStationRules(prefs, {bar: const StationTicketRule()});
      expect(service.stationRules, isEmpty);
      expect(service.ruleForStation(bar).private, isFalse);
    });
  });

  group('a rule from a future build degrades safely', () {
    test('an unknown scope reads as own-items, not as whole-order', () {
      // The dangerous direction: silently upgrading a station to "print
      // everything" would spray the whole order at a printer nobody meant to
      // configure.
      final rule = StationTicketRule.fromJson(
          {'scope': 'wholeOrderSometimesMaybe', 'private': false});
      expect(rule.scope, StationTicketScope.ownItems);
    });

    test('a missing private flag is not private', () {
      expect(StationTicketRule.fromJson({'scope': 'ownItems'}).private,
          isFalse);
    });
  });
}
