import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../domain/models/reservation_models.dart';
import '../../providers/order_provider.dart';
import '../../providers/reservation_providers.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_localizations.dart';
import '../../utils/error_text.dart';
import '../../utils/snackbar_helper.dart';

String reservationStatusLabel(String status, AppLocalizations l10n) =>
    l10n.translate('res_status_$status');

String timeStatusLabel(BookingTimeStatus status, AppLocalizations l10n) {
  switch (status) {
    case BookingTimeStatus.notYet:
      return l10n.translate('booking_not_yet');
    case BookingTimeStatus.inProgress:
      return l10n.translate('booking_in_progress');
    case BookingTimeStatus.done:
      return l10n.translate('booking_done');
  }
}

/// Background and foreground for a reservation status, from the theme.
({Color bg, Color fg}) reservationStatusColors(String status, ColorScheme cs) {
  switch (status) {
    case ReservationStatus.confirmed:
      return (bg: cs.primaryContainer, fg: cs.onPrimaryContainer);
    case ReservationStatus.arrived:
      return (bg: cs.secondaryContainer, fg: cs.onSecondaryContainer);
    case ReservationStatus.converted:
      return (bg: cs.tertiaryContainer, fg: cs.onTertiaryContainer);
    case ReservationStatus.noShow:
    case ReservationStatus.canceled:
      return (bg: cs.errorContainer, fg: cs.onErrorContainer);
    default:
      return (bg: cs.surfaceContainerHighest, fg: cs.onSurface);
  }
}

/// A resource's colour from the back office (`#RRGGBB`), else a soft hue
/// derived from its id so every column stays distinguishable.
Color resourceColor(String? hex, int id, ColorScheme cs) {
  final h = hex?.replaceFirst('#', '');
  if (h != null && (h.length == 6 || h.length == 8)) {
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    if (v != null) return Color(v);
  }
  // Golden-angle steps keep neighbouring ids far apart on the wheel.
  final hue = (id * 137.508) % 360;
  final dark = cs.brightness == Brightness.dark;
  return HSLColor.fromAHSL(1, hue, 0.55, dark ? 0.62 : 0.52).toColor();
}

/// The pale fill of a card in that resource's column.
Color resourceTint(AgendaResource r, ColorScheme cs) => Color.alphaBlend(
  resourceColor(
    r.color,
    r.id,
    cs,
  ).withValues(alpha: cs.brightness == Brightness.dark ? 0.28 : 0.16),
  cs.surface,
);

/// "1 appt" / "3 appts".
String appointmentCount(int n, AppLocalizations l10n) => n == 1
    ? l10n.translate('res_appointment_one')
    : '$n ${l10n.translate('res_appointments')}';

final _hm = DateFormat('HH:mm');
String hm(DateTime t) => _hm.format(t);
String hmRange(DateTime a, DateTime b) => '${hm(a)}–${hm(b)}';

void reservationToast(String message, {bool isError = false}) {
  SnackBarHelper.showToast(
    message,
    kind: isError ? ToastKind.error : ToastKind.success,
    duration: Duration(seconds: isError ? 5 : 2),
  );
}

/// Runs a reservation write and reports it. Returns the result, or null when
/// it failed (the error is already shown). A 409 means "someone else has
/// it": staff are offered what they may do about it, else the agenda is
/// re-pulled so they pick again from the truth.
///
///   * [allowOverlap]: the same request kept unconfirmed over the other
///     booking (anyone may; given only for a BOOKED reservation);
///   * [overbook]: the same request with `overbook: true`, offered only when
///     the 409 says this user may double-book (a manager);
///   * [overbookLabel]: the button's wording ("Book anyway", "Confirm anyway").
Future<T?> runReservationWrite<T>(
  WidgetRef ref,
  BuildContext context,
  Future<T> Function() write, {
  String? successKey,
  Future<T> Function()? overbook,
  Future<T> Function()? allowOverlap,
  String overbookLabel = 'res_overbook',
}) async {
  final l10n = AppLocalizations.of(context)!;
  try {
    final result = await write();
    ref.read(agendaRevisionProvider.notifier).state++;
    if (successKey != null) reservationToast(l10n.translate(successKey));
    // The server's overlap list lives on the agenda: refresh it now rather
    // than wait for the SSE echo.
    unawaited(_repull(ref));
    return result;
  } on ReservationConflict catch (c) {
    final canOverbook = c.overbookable && overbook != null;
    if ((canOverbook || allowOverlap != null) && context.mounted) {
      final choice = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          icon: const Icon(Icons.layers_rounded),
          title: Text(l10n.translate('res_overbook_title')),
          content: Text(c.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: Text(l10n.translate('cancel')),
            ),
            if (allowOverlap != null)
              OutlinedButton(
                onPressed: () => Navigator.pop(d, 'overlap'),
                child: Text(l10n.translate('res_keep_both')),
              ),
            if (canOverbook)
              FilledButton(
                onPressed: () => Navigator.pop(d, 'overbook'),
                child: Text(l10n.translate(overbookLabel)),
              ),
          ],
        ),
      );
      if (choice != null && context.mounted) {
        return runReservationWrite(
          ref,
          context,
          choice == 'overbook' ? overbook! : allowOverlap!,
          successKey: successKey,
        );
      }
      if (context.mounted) await _repull(ref);
      return null;
    }
    reservationToast(c.message, isError: true);
    await _repull(ref);
    return null;
  } catch (e) {
    reservationToast(errorText(e, l10n), isError: true);
    return null;
  }
}

Future<void> _repull(WidgetRef ref) async {
  final visible = ref.read(agendaVisibleDateProvider);
  if (visible != null) await pullAgendaWeekFromWidget(ref, visible);
}

/// Ring [r] up: load its services into the cart, carrying its code so the
/// order push links the two, and go to the till. Works offline from the
/// cached copy. Returns true when the cart was loaded.
Future<bool> ringUpReservation(
  BuildContext context,
  WidgetRef ref,
  Reservation r,
) async {
  final l10n = AppLocalizations.of(context)!;
  final service = ref.read(reservationServiceProvider);

  // Converted elsewhere since the agenda was pulled: say so rather than sell
  // it twice. Offline we cannot know; the push reports it if it happened.
  final fresh = await service.refresh(r) ?? r;
  if (!context.mounted) return false;
  if (fresh.isConverted) {
    reservationToast(
      l10n
          .translate('res_already_converted')
          .replaceAll('{order}', fresh.orderCode ?? '?'),
      isError: true,
    );
    return false;
  }

  final local = await service.localOrdersFor(fresh.code);
  if (!context.mounted) return false;
  if (local.isNotEmpty &&
      !await _confirm(
        context,
        l10n
            .translate('res_already_rung_up')
            .replaceAll('{code}', local.first.code),
      )) {
    return false;
  }

  final cart = ref.read(orderProvider);
  if (!context.mounted) return false;
  if (cart.hasUnsavedChanges &&
      !await _confirm(context, l10n.translate('res_cart_not_empty'))) {
    return false;
  }

  final settings = ref.read(settingsProvider);
  try {
    final order = await service.buildCart(
      fresh,
      orderType: settings.defaultOrderType,
      zeroPriceTvaRate: settings.zeroPriceTvaRate,
    );
    ref.read(orderProvider.notifier).loadOrder(order);
  } on StateError catch (e) {
    reservationToast(
      l10n.translate('res_missing_product').replaceAll('{name}', e.message),
      isError: true,
    );
    return false;
  }

  // Tell the server the customer is here; never holds up the sale.
  await service.markArrivedQuietly(fresh);
  ref.read(agendaRevisionProvider.notifier).state++;

  if (context.mounted) {
    Navigator.of(
      context,
    ).popUntil((route) => route.settings.name == '/main' || route.isFirst);
  }
  return true;
}

Future<bool> _confirm(BuildContext context, String message) async {
  final l10n = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(l10n.translate('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(l10n.translate('confirm')),
        ),
      ],
    ),
  );
  return ok == true;
}
