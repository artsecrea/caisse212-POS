import 'dart:math';

/// Characters a POS line id is made of: no spaces, nothing the backend trims.
const _alphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

/// The longest id the backend accepts from a client (`CLIENT_UID_MAX`).
/// Its own ids are 8 long, so a POS id can never collide with one it minted.
const lineUidLength = 7;

final _random = Random.secure();

/// A new identity for an order line, minted once when the line is written
/// and kept for its whole life. The v2 order push matches lines by it alone
/// (`PUT /pos/v2/orders/{code}`), so it must never change on an edit.
/// 62^7 ≈ 3.5e12 values: a clash inside one order is not a practical concern.
String mintLineUid() => List.generate(
    lineUidLength, (_) => _alphabet[_random.nextInt(_alphabet.length)]).join();
