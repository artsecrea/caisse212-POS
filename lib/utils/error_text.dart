import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../domain/models/booking_models.dart';
import '../services/booking_service.dart';
import '../services/api_service.dart';
import 'app_localizations.dart';

/// Turns whatever was thrown into something a cashier can act on.
///
/// The POS surfaced raw `Exception: DioException [connection error]: ...` at
/// the till more often than not. That string tells the person at the counter
/// nothing they can do, buries the one useful fact (the network is down) in
/// noise, and is untranslatable — so an Arabic or French shop got English
/// stack-trace furniture in a red bar.
///
/// Every message here answers "what happened, and what now" in the app's
/// language. Where the server sent a human message of its own, that wins: it
/// knows the specifics (which resource is full, which field is invalid) that a
/// generic mapping never could.
String errorText(Object? error, AppLocalizations l10n) {
  if (error == null) return l10n.translate('error_unknown');

  // Booking's own exceptions already say the actionable thing.
  if (error is OfflineBookingException) {
    return l10n.translate('reconnect_to_book');
  }
  if (error is UnsyncedLineException) {
    return l10n.translate('booking_order_sync_failed');
  }
  if (error is ScheduleConflict) {
    final detail =
        error.capacity != null ? ' (${error.current ?? '?'}/${error.capacity})' : '';
    return '${error.message}$detail';
  }
  if (error is ScheduleValidationError) return error.message;

  // The till-side catalogue endpoints already carry the server's own words
  // (a plan-limit message names the cap and the plan). Only the 403 is worth
  // rewriting — "Forbidden" tells a cashier nothing.
  if (error is PosCatalogException) {
    if (error.isForbidden) return l10n.translate('error_forbidden');
    return _cleanup(error.message, l10n);
  }

  if (error is DioException) return _fromDio(error, l10n);
  if (error is SocketException) return l10n.translate('error_offline');
  if (error is TimeoutException) return l10n.translate('error_timeout');
  if (error is FormatException) return l10n.translate('error_bad_response');

  return _cleanup(error.toString(), l10n);
}

String _fromDio(DioException e, AppLocalizations l10n) {
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      // `unknown` is overwhelmingly a dead socket in practice; a genuinely
      // unknown failure reads no worse as "check the connection".
      return l10n.translate('error_offline');
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return l10n.translate('error_timeout');
    case DioExceptionType.cancel:
      return l10n.translate('error_cancelled');
    case DioExceptionType.badCertificate:
      return l10n.translate('error_certificate');
    case DioExceptionType.badResponse:
      break;
  }

  final status = e.response?.statusCode;
  final server = _serverMessage(e.response?.data);

  // The server's own words first — it knows which product, which slot, which
  // field. Only fall back to the status mapping when it said nothing useful.
  if (server != null && server.isNotEmpty) return server;

  return switch (status) {
    400 => l10n.translate('error_bad_request'),
    401 => l10n.translate('error_unauthorized'),
    403 => l10n.translate('error_forbidden'),
    404 => l10n.translate('error_not_found'),
    402 => l10n.translate('error_plan_limit'),
    409 => l10n.translate('error_conflict'),
    422 => l10n.translate('error_bad_request'),
    429 => l10n.translate('error_rate_limited'),
    _ when status != null && status >= 500 =>
      l10n.translate('error_server').replaceAll('{0}', '$status'),
    _ => l10n.translate('error_unknown'),
  };
}

/// The human message out of a JSON error body, under any of the spellings the
/// backend uses. Ignores anything that looks like a class name or a stack
/// frame — some 500s echo the exception type, which is not a message.
String? _serverMessage(dynamic data) {
  if (data is String) {
    final t = data.trim();
    return (t.isEmpty || t.length > 300 || t.contains('Exception')) ? null : t;
  }
  if (data is! Map) return null;

  // Bean-validation 400s from the BMS backend carry message:"Validation failed"
  // and put the useful half in `details` as {field: reason}. Confirmed with the
  // backend 2026-09-10. Showing "Validation failed" names nothing the cashier
  // can fix, so the field reasons win when they are there.
  final details = data['details'];
  if (details is Map && details.isNotEmpty) {
    final reasons = details.entries
        .map((e) => e.value?.toString().trim() ?? '')
        .where((v) => v.isNotEmpty)
        .toList();
    if (reasons.isNotEmpty) return reasons.join(' · ');
  }

  for (final key in const ['message', 'error_description', 'error', 'detail']) {
    final v = data[key];
    if (v is String && v.trim().isNotEmpty) {
      final t = v.trim();
      if (t.contains('Exception') || t.contains('\tat ')) continue;
      return t;
    }
  }
  return null;
}

/// Strips the framing Dart adds so the useful half is not buried.
///
/// `Exception: Failed to confirm: Connection refused` should reach the cashier
/// as "Failed to confirm: Connection refused", not with the ceremony in front.
String _cleanup(String raw, AppLocalizations l10n) {
  var text = raw.trim();
  for (final prefix in const [
    'Exception: ',
    'DioException: ',
    'StateError: ',
    'ArgumentError: ',
    'Error: ',
  ]) {
    while (text.startsWith(prefix)) {
      text = text.substring(prefix.length).trim();
    }
  }

  // A raw Dio dump reaching here means some layer stringified it; do not put
  // brackets and URLs in front of a cashier.
  if (text.startsWith('DioException')) return l10n.translate('error_offline');

  if (text.isEmpty) return l10n.translate('error_unknown');

  // One long line of internals is worse than an honest generic message.
  if (text.length > 240) return l10n.translate('error_unknown');
  return text;
}
