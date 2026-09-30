import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';

/// R2 "Add details": optional extras after the SOS is already sent. Returns
/// the new details, or null if the sheet was closed.
Future<SosDetails?> showAddDetailsSheet(
  BuildContext context,
  SosDetails current,
) => showModalBottomSheet<SosDetails>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => _AddDetailsSheet(initial: current),
);

class _AddDetailsSheet extends StatefulWidget {
  const _AddDetailsSheet({required this.initial});

  final SosDetails initial;

  @override
  State<_AddDetailsSheet> createState() => _AddDetailsSheetState();
}

class _AddDetailsSheetState extends State<_AddDetailsSheet> {
  late IncidentType? _type = widget.initial.type;
  late int? _people = widget.initial.peopleCount;
  late bool _extraHelp = widget.initial.needsExtraHelp;
  late final _note = TextEditingController(text: widget.initial.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SagipSpace.xl,
        0,
        SagipSpace.xl,
        SagipSpace.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.addDetails, style: text.titleLarge),
            const SizedBox(height: SagipSpace.xs),
            Text(
              l10n.detailsHint,
              style: text.bodyMedium!.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: SagipSpace.xl),
            Text(l10n.detailsType, style: text.titleSmall),
            const SizedBox(height: SagipSpace.sm),
            Wrap(
              spacing: SagipSpace.sm,
              runSpacing: SagipSpace.sm,
              children: [
                for (final t in IncidentType.values)
                  ChoiceChip(
                    label: Text(l10n.incidentType(t)),
                    selected: _type == t,
                    onSelected: (on) => setState(() => _type = on ? t : null),
                  ),
              ],
            ),
            const SizedBox(height: SagipSpace.xl),
            Text(l10n.detailsPeople, style: text.titleSmall),
            const SizedBox(height: SagipSpace.sm),
            Row(
              children: [
                IconButton.outlined(
                  tooltip: l10n.fewerPeople,
                  onPressed: (_people ?? 0) > 1
                      ? () => setState(() => _people = _people! - 1)
                      : null,
                  icon: const Icon(Symbols.remove_rounded),
                ),
                Expanded(
                  child: Text(
                    _people == null ? '–' : l10n.detailsPeopleCount(_people!),
                    textAlign: TextAlign.center,
                    style: text.titleMedium!.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                IconButton.outlined(
                  tooltip: l10n.morePeople,
                  onPressed: () => setState(() => _people = (_people ?? 0) + 1),
                  icon: const Icon(Symbols.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: SagipSpace.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.detailsExtraHelp),
              subtitle: Text(l10n.detailsExtraHelpHint),
              value: _extraHelp,
              onChanged: (on) => setState(() => _extraHelp = on),
            ),
            const SizedBox(height: SagipSpace.md),
            TextField(
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              controller: _note,
              maxLines: 3,
              maxLength: 200,
              decoration: InputDecoration(labelText: l10n.detailsNote),
            ),
            const SizedBox(height: SagipSpace.lg),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                SosDetails(
                  type: _type,
                  peopleCount: _people,
                  needsExtraHelp: _extraHelp,
                  note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                ),
              ),
              child: Text(l10n.saveDetails),
            ),
          ],
        ),
      ),
    );
  }
}
