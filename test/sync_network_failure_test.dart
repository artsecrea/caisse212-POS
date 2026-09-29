import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/services/data_sync_service.dart';

/// Telling "the endpoint is unreachable" from "the server refused this one
/// order" is what decides whether a batch keeps going.
///
/// It matters because of what the field logs showed: thousands of
/// "the request connection took longer than 0:00:10 and it was aborted", and a
/// per-order fallback that walked a batch of up to 50 regardless — every one
/// burning a full connect timeout against a host that was plainly not
/// answering. Roughly 17 minutes of work inside a 5-minute cycle, achieving
/// nothing.
///
/// Getting this wrong is expensive in both directions: classify a refused
/// order as a network failure and three bad orders stop the whole queue;
/// classify a dead host as a refusal and the till goes back to burning its
/// life in timeouts.

void main() {
  DioException dio(DioExceptionType type) => DioException(
        requestOptions: RequestOptions(path: '/pos/orders'),
        type: type,
      );

  group('the network gave up', () {
    test('a connect timeout is a network failure', () {
      expect(
          DataSyncService.isNetworkFailure(
              dio(DioExceptionType.connectionTimeout)),
          isTrue);
    });

    test('send and receive timeouts are too', () {
      expect(DataSyncService.isNetworkFailure(dio(DioExceptionType.sendTimeout)),
          isTrue);
      expect(
          DataSyncService.isNetworkFailure(
              dio(DioExceptionType.receiveTimeout)),
          isTrue);
    });

    test('a connection error is too', () {
      expect(
          DataSyncService.isNetworkFailure(
              dio(DioExceptionType.connectionError)),
          isTrue);
    });

    test('the rewrapped message still classifies — which is the real path', () {
      // syncSingleOrder catches Dio's error and rethrows a plain Exception, so
      // by the time the batch loop sees it the type is gone.
      expect(
        DataSyncService.isNetworkFailure(Exception(
            'Failed to sync order: The request connection took longer than '
            '0:00:10.000000 and it was aborted.')),
        isTrue,
        reason: 'this exact string is what fills the field logs',
      );
    });

    test('socket-level failures count', () {
      for (final m in const [
        'SocketException: Connection refused',
        'Failed host lookup: api.example.com',
        'Network is unreachable',
        'Connection closed before full header was received',
      ]) {
        expect(DataSyncService.isNetworkFailure(Exception(m)), isTrue,
            reason: m);
      }
    });
  });

  group('the server answered and said no', () {
    test('a bad response is NOT a network failure', () {
      expect(
          DataSyncService.isNetworkFailure(dio(DioExceptionType.badResponse)),
          isFalse);
    });

    test('a cancelled request is not either', () {
      expect(DataSyncService.isNetworkFailure(dio(DioExceptionType.cancel)),
          isFalse);
    });

    test('a serial rejection must never stop the queue', () {
      // One order the backend refuses says nothing about the next one.
      final e = Exception('Failed to sync order: serial not available');
      expect(DataSyncService.isNetworkFailure(e), isFalse);
      expect(DataSyncService.isSerialRejection(e), isTrue,
          reason: 'it is a business refusal, and it is handled as one');
    });

    test('a validation error is not a network failure', () {
      expect(
        DataSyncService.isNetworkFailure(
            Exception('Failed to sync order: 400 missing tableId')),
        isFalse,
      );
    });
  });
}
