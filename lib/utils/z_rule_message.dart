import '../domain/services/day_service.dart' show ZRuleViolation;
import '../services/z_rules.dart' show ZRuleBlock;
import 'app_localizations.dart';

extension ZRuleViolationMessage on ZRuleViolation {
  String message(AppLocalizations l10n) => zRuleMessage(l10n, block, limit);
}

String zRuleMessage(AppLocalizations l10n, ZRuleBlock block, String? limit) {
  switch (block) {
    case ZRuleBlock.manualOpenRequired:
      return l10n.translate('z_block_manual_open');
    case ZRuleBlock.tooLateToOpen:
      return l10n
          .translate('z_block_too_late_open')
          .replaceAll('{0}', limit ?? '');
    case ZRuleBlock.tooEarlyToClose:
      return l10n
          .translate('z_block_too_early_close')
          .replaceAll('{0}', limit ?? '');
    case ZRuleBlock.noClosePermission:
      return l10n.translate('z_block_no_close_permission');
  }
}
