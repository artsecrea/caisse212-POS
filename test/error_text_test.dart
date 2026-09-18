import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/booking_models.dart';
import 'package:caisse212/services/booking_service.dart';
import 'package:caisse212/utils/app_localizations.dart';
import 'package:caisse212/utils/error_text.dart';

/// What the person at the till reads when something fails.
///
/// The app used to put `Exception: DioException [connection error]: ...` in a
/// red bar. That is untranslatable, unactionable, and hides the one fact that
/// matters. These pin the mapping so it cannot drift back.

Response<dynamic> _response(int status, [dynamic body]) => Response(
      requestOptions: RequestOptions(path: '/x'),
      statusCode: status,
      data: body,
    );

DioException _dio(DioExceptionType type, {Response<dynamic>? response}) =>
    DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      response: response,
    );

void main() {
  late AppLocalizations en;

  setUpAll(() {
    en = AppLocalizations(const Locale('en'));
  });

  group('transport failures name the thing the user can fix', () {
    test('a dead connection reads as offline', () {
      expect(errorText(_dio(DioExceptionType.connectionError), en),
          en.translate('error_offline'));
    });

    test('an unknown Dio failure also reads as offline', () {
      // In practice this is a dead socket; "check the connection" is never
      // misleading advice for it.
      expect(errorText(_dio(DioExceptionType.unknown), en),
          en.translate('error_offline'));
    });

    test('each timeout kind reads as a timeout', () {
      for (final type in const [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(errorText(_dio(type), en), en.translate('error_timeout'));
      }
    });

    test('a raw SocketException reads as offline', () {
      expect(errorText(const SocketException('failed'), en),
          en.translate('error_offline'));
    });

    test('a TimeoutException reads as a timeout', () {
      expect(errorText(TimeoutException('slow'), en),
          en.translate('error_timeout'));
    });
  });

  group('status codes map to something actionable', () {
    void expectStatus(int status, String key) {
      expect(
        errorText(
            _dio(DioExceptionType.badResponse, response: _response(status)), en),
        en.translate(key),
      );
    }

    test('401 tells them to sign in again', () => expectStatus(401, 'error_unauthorized'));
    test('403 is a permission problem', () => expectStatus(403, 'error_forbidden'));
    test('404 says it is gone', () => expectStatus(404, 'error_not_found'));
    test('409 says someone else got there first',
        () => expectStatus(409, 'error_conflict'));
    test('429 says slow down', () => expectStatus(429, 'error_rate_limited'));

    test('a 5xx names the code so support can act on it', () {
      final text = errorText(
          _dio(DioExceptionType.badResponse, response: _response(503)), en);
      expect(text, contains('503'));
    });
  });

  group("the server's own message wins", () {
    test('a message field beats the generic status text', () {
      final text = errorText(
        _dio(DioExceptionType.badResponse,
            response: _response(409, {'message': 'Chair 2 is full (2/2)'})),
        en,
      );
      expect(text, 'Chair 2 is full (2/2)');
    });

    test('other spellings of the field are read too', () {
      for (final key in const ['error', 'detail', 'error_description']) {
        final text = errorText(
          _dio(DioExceptionType.badResponse,
              response: _response(400, {key: 'Product is not bookable'})),
          en,
        );
        expect(text, 'Product is not bookable');
      }
    });

    test('a stack-trace echo is not treated as a message', () {
      // Some 500s echo the exception class. That is not something to show.
      final text = errorText(
        _dio(DioExceptionType.badResponse,
            response: _response(500, {
              'message': 'java.lang.NullPointerException',
            })),
        en,
      );
      expect(text, isNot(contains('NullPointerException')));
      expect(text, contains('500'));
    });

    test('a plain-string body is used when it looks human', () {
      final text = errorText(
        _dio(DioExceptionType.badResponse,
            response: _response(400, 'Missing X-POS-Name header')),
        en,
      );
      expect(text, 'Missing X-POS-Name header');
    });
  });

  group('booking exceptions keep their own wording', () {
    test('offline booking points at the connection', () {
      expect(errorText(const OfflineBookingException(), en),
          en.translate('reconnect_to_book'));
    });

    test('an unsynced line says to sync the order', () {
      expect(errorText(const UnsyncedLineException(), en),
          en.translate('booking_order_sync_failed'));
    });

    test('a resource conflict carries the occupancy', () {
      final text = errorText(
        const ScheduleConflict(
            message: 'Room full', isResource: true, current: 2, capacity: 2),
        en,
      );
      expect(text, 'Room full (2/2)');
    });

    test('a validation error is passed through verbatim', () {
      expect(errorText(const ScheduleValidationError('End before start'), en),
          'End before start');
    });
  });

  group('Dart framing is stripped', () {
    test('the Exception: prefix goes', () {
      expect(errorText(Exception('Order already has a code'), en),
          'Order already has a code');
    });

    test('a stringified Dio dump is not shown raw', () {
      final text = errorText(
          'DioException [connection error]: SocketException: refused', en);
      expect(text, en.translate('error_offline'));
    });

    test('a wall of internals falls back to the generic message', () {
      expect(errorText('x' * 500, en), en.translate('error_unknown'));
    });

    test('null is still sayable', () {
      expect(errorText(null, en), en.translate('error_unknown'));
    });
  });

  // Shapes confirmed against the BMS backend's GlobalExceptionHandler
  // (2026-09-10): ErrorResponse is
  // {status, error, message, path, timestamp, details:{field:msg}|null},
  // where `error` is a category label and `message` is the sentence.
  group('the BMS error envelope', () {
    test('a validation 400 shows the field reasons, not "Validation failed"',
        () {
      final text = errorText(
          _dio(DioExceptionType.badResponse,
              response: _response(400, {
                'status': 400,
                'error': 'Validation Error',
                'message': 'Validation failed',
                'details': {'price': 'must be greater than or equal to 0'},
              })),
          en);
      expect(text, 'must be greater than or equal to 0');
    });

    test('several invalid fields are all named', () {
      final text = errorText(
          _dio(DioExceptionType.badResponse,
              response: _response(400, {
                'message': 'Validation failed',
                'details': {'name': 'must not be blank', 'price': 'is required'},
              })),
          en);
      expect(text, contains('must not be blank'));
      expect(text, contains('is required'));
    });

    test('a plain 400 still shows the server sentence', () {
      final text = errorText(
          _dio(DioExceptionType.badResponse,
              response: _response(400, {
                'error': 'Bad Request',
                'message': 'Send categoryId or categoryName, not both',
              })),
          en);
      expect(text, 'Send categoryId or categoryName, not both');
    });

    test('an empty details map does not swallow the message', () {
      final text = errorText(
          _dio(DioExceptionType.badResponse,
              response: _response(
                  400, {'message': 'Category not found: 7', 'details': {}})),
          en);
      expect(text, 'Category not found: 7');
    });

    test('a plan-limit 402 with no body still says something actionable', () {
      expect(
          errorText(
              _dio(DioExceptionType.badResponse, response: _response(402)), en),
          en.translate('error_plan_limit'));
    });
  });
}
