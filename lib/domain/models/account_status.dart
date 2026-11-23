/// Whether the server lets this till work: tenant, business and terminal all
/// active. Separate from the subscription. An expired subscription only warns,
/// but a deactivated account locks the till until it is reactivated (user
/// ruling 2026-11-16).
library;

/// Which level of the account the back office switched off. When several are
/// off the server reports the widest one (tenant > business > terminal).
enum AccountBlockScope { tenant, business, terminal, unknown }

class AccountBlock {
  final AccountBlockScope scope;

  /// Free text from the server, shown under the lock card when present.
  final String? message;

  /// Why, as a code the back office sets (SUBSCRIPTION_ENDED, ADMIN_KICK…).
  /// Shown on the card so support can tell the cases apart at a glance.
  final String? reasonCode;

  /// When this till first heard it was blocked.
  final DateTime since;

  const AccountBlock(
      {required this.scope, this.message, this.reasonCode, required this.since});

  Map<String, dynamic> toJson() => {
        'scope': scope.name,
        if (message != null) 'message': message,
        if (reasonCode != null) 'reasonCode': reasonCode,
        'since': since.toUtc().toIso8601String(),
      };

  factory AccountBlock.fromJson(Map<dynamic, dynamic> json) => AccountBlock(
        scope: parseAccountScope(json['scope']),
        message: _str(json['message']),
        reasonCode: _str(json['reasonCode']),
        since: DateTime.tryParse('${json['since']}')?.toLocal() ?? DateTime.now(),
      );
}

const kAccountDisabledCode = 'ACCOUNT_DISABLED';
const kAccountStatusHeader = 'x-account-status';

AccountBlockScope parseAccountScope(dynamic raw) {
  final s = raw?.toString().trim().toUpperCase() ?? '';
  if (s.contains('TENANT')) return AccountBlockScope.tenant;
  if (s.contains('BUSINESS')) return AccountBlockScope.business;
  if (s.contains('TERMINAL') || s.contains('POS')) return AccountBlockScope.terminal;
  return AccountBlockScope.unknown;
}

/// What an HTTP answer says about the account:
/// - an [AccountBlock] when it is the server's "account disabled" refusal;
/// - null otherwise (any other error, or success).
///
/// Recognised by the body `code: ACCOUNT_DISABLED` or the `X-Account-Status:
/// DISABLED_*` header. The header is the fallback for a proxy that rewrites
/// error bodies. A bare 423 without either still counts: nothing else on the
/// POS routes uses 423.
AccountBlock? accountBlockFromError({
  required int? statusCode,
  dynamic body,
  String? statusHeader,
}) {
  final header = statusHeader?.trim().toUpperCase() ?? '';
  final headerSaysDisabled = header.startsWith('DISABLED');
  final code = body is Map ? _str(body['code'] ?? body['error'])?.toUpperCase() : null;
  final bodySaysDisabled = code == kAccountDisabledCode;
  // Servers deployed before the 423 answered an inactive terminal with
  // 403 "POS terminal is not active".
  final legacy = statusCode == 403 &&
      body is Map &&
      (_str(body['message'])?.toLowerCase().contains('terminal is not active') ?? false);
  if (legacy) {
    return AccountBlock(
        scope: AccountBlockScope.terminal, message: null, since: DateTime.now());
  }
  if (!headerSaysDisabled && !bodySaysDisabled && statusCode != 423) {
    return null;
  }
  final scopeRaw = (body is Map ? body['scope'] : null) ?? header;
  return AccountBlock(
    scope: parseAccountScope(scopeRaw),
    message: body is Map ? _str(body['message']) : null,
    reasonCode: body is Map ? _str(body['reasonCode']) : null,
    since: DateTime.now(),
  );
}

/// Reads an `accountStatus` object (`{"active": bool, "scope", "message"}`):
/// - `true`: the account is active, so any stored block is cleared;
/// - an [AccountBlock]: the account is disabled;
/// - null: unreadable, or no `active` key, so nothing changes.
Object? parseAccountStatus(dynamic raw) {
  if (raw is! Map || !raw.containsKey('active')) return null;
  final active = raw['active'];
  if (active == true || '$active'.toLowerCase() == 'true') return true;
  if (active == false || '$active'.toLowerCase() == 'false') {
    return AccountBlock(
      scope: parseAccountScope(raw['scope']),
      message: _str(raw['message']),
      reasonCode: _str(raw['reasonCode']),
      since: DateTime.now(),
    );
  }
  return null;
}

String? _str(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}
