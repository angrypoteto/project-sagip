import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';
import 'labels.dart';

/// A short confirmation or error. It floats at the bottom centre, 360 px
/// wide, so it never covers the queue on the left or the incident drawer's
/// action button on the right (a full-width one hid "Assign" for four
/// seconds right after "Mark verified").
SnackBar statusSnack(String text) => SnackBar(content: Text(text), width: 360);

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
      messenger.showSnackBar(statusSnack(success));
    }
    return true;
  } on ActionRejected catch (e) {
    messenger.showSnackBar(statusSnack(l10n.actionRejection(e.reason)));
  } catch (_) {
    messenger.showSnackBar(statusSnack(l10n.errorGeneric));
  }
  return false;
}
