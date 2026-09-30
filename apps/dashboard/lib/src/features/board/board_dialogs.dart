import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// D5: asks why the dispatcher is not taking the top suggestion (FR3 manual
/// override). Returns the reason to record, or null if cancelled.
Future<String?> showOverrideDialog(
  BuildContext context, {
  required UnitSuggestion chosen,
  required UnitSuggestion top,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _OverrideDialog(chosen: chosen, top: top),
  );
}

class _OverrideDialog extends StatefulWidget {
  const _OverrideDialog({required this.chosen, required this.top});

  final UnitSuggestion chosen;
  final UnitSuggestion top;

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  String? _reason;
  bool _showMissing = false;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final reasons = [
      l10n.reasonEquipment,
      l10n.reasonBusy,
      l10n.reasonBlocked,
      l10n.reasonOther,
    ];
    final minutes = (widget.chosen.etaMinutes - widget.top.etaMinutes)
        .round()
        .clamp(1, 999);

    return AlertDialog(
      title: Text(l10n.overrideTitle(widget.chosen.unit.callSign)),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.overrideBody(widget.top.unit.callSign, minutes)),
            const SizedBox(height: SagipSpace.xl),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.overrideReasonLabel,
                errorText: _showMissing && _reason == null
                    ? l10n.overrideReasonMissing
                    : null,
              ),
              dropdownColor: p.panelRaised,
              items: [
                for (final r in reasons)
                  DropdownMenuItem(
                    value: r,
                    child: Text(r, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _reason = value),
            ),
            const SizedBox(height: SagipSpace.lg),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: InputDecoration(labelText: l10n.overrideNoteLabel),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (_reason == null) {
              setState(() => _showMissing = true);
              return;
            }
            final note = _note.text.trim();
            Navigator.pop(context, note.isEmpty ? _reason : '$_reason: $note');
          },
          child: Text(l10n.assignUnit(widget.chosen.unit.callSign)),
        ),
      ],
    );
  }
}

/// "Choose another unit": every unit that can take the job, nearest first.
Future<UnitSuggestion?> showChooseUnitDialog(
  BuildContext context,
  List<UnitSuggestion> ranked,
) {
  return showDialog<UnitSuggestion>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final text = Theme.of(context).textTheme;
      return AlertDialog(
        title: Text(l10n.chooseUnitTitle),
        content: SizedBox(
          width: 460,
          child: ranked.isEmpty
              ? Text(l10n.noAvailableUnitsMessage)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.chooseUnitBody, style: text.bodySmall),
                    const SizedBox(height: SagipSpace.md),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final s in ranked)
                            ListTile(
                              leading: Icon(unitTypeIcon(s.unit.type)),
                              title: Text(s.unit.callSign),
                              subtitle: Text(
                                '${l10n.unitType(s.unit.type)}, ${s.unit.station}',
                              ),
                              trailing: Text(
                                l10n.etaMinutes(s.etaMinutes.round()),
                                style: text.titleSmall!.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              onTap: () => Navigator.pop(context, s),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ],
      );
    },
  );
}

/// Confirms marking an SOS as false. Returns true if confirmed.
Future<bool> confirmFalseReport(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.falseReportTitle),
      content: SizedBox(width: 420, child: Text(l10n.falseReportBody)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.markFalse),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Shows the resident's number for a callback. Revealing it is logged.
Future<void> showCallDialog(
  BuildContext context,
  WidgetRef ref,
  Resident resident,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // Viewing personal data is an audited action (NFR4, FR11).
  ref.read(residentRepositoryProvider).logContactViewed(resident.id).ignore();
  await showDialog<void>(
    context: context,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      return AlertDialog(
        title: Text(l10n.callTitle(resident.fullName)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                resident.contactNumber,
                style: text.displaySmall!.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: SagipSpace.md),
              Text(l10n.callBody),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: resident.contactNumber),
              );
              messenger.showSnackBar(SnackBar(content: Text(l10n.copiedSnack)));
            },
            child: Text(l10n.copyNumber),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      );
    },
  );
}
