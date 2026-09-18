import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/services/api_service.dart';

/// The scrap of identity that goes into a refund code.
///
/// Refund codes have to differ between tills. The old code dropped the
/// terminal segment entirely when the POS name was blank, producing codes with
/// nothing terminal-specific in them — so two unnamed tills refunding in the
/// same second minted the same code. That is the case this exists to close,
/// and it is exactly the terminal least likely to have been set up carefully.

Future<ApiService> serviceWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return ApiService(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the POS name wins when there is one', () async {
    final api = await serviceWith({'pos_name': 'Caisse1', 'pos_terminal_id': 7});
    expect(api.terminalTag(), 'Caisse1');
  });

  test('whitespace is not a name', () async {
    final api = await serviceWith({'pos_name': '   ', 'pos_terminal_id': 7});
    expect(api.terminalTag(), 'T7');
  });

  test('the terminal id stands in when the name is missing', () async {
    final api = await serviceWith({'pos_terminal_id': 42});
    expect(api.terminalTag(), 'T42');
  });

  test('a till with no identity at all still gets one', () async {
    // The hole: this used to yield nothing, and the code lost its terminal
    // segment altogether.
    final api = await serviceWith({});
    final tag = api.terminalTag();
    expect(tag, isNotEmpty);
    expect(tag.startsWith('X'), isTrue);
  });

  test('the minted tag is kept, not re-rolled', () async {
    // It has to be stable: a tag that changed per call would put a different
    // terminal segment on every refund from the same till.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = ApiService(prefs).terminalTag();
    expect(ApiService(prefs).terminalTag(), first,
        reason: 'survives a new service over the same prefs');
    expect(prefs.getString('terminal_tag'), first);
  });

  test('a real name later on takes over from the minted tag', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ApiService(prefs).terminalTag();
    await prefs.setString('pos_name', 'Caisse2');
    expect(ApiService(prefs).terminalTag(), 'Caisse2');
  });
}
