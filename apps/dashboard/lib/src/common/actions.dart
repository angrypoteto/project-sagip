import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';
import 'labels.dart';

/// Runs a repository action and reports the result in a snackbar.
///
/// Errors say what happened and what to do (design skill). Returns true on
/// success so callers can close dialogs.
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  try {
    await action();
    if (success != null) {
      messenger.showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } on ActionRejected catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.actionRejection(e.reason))),
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
  }
  return false;
}
