import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/async_body.dart';
import '../../common/download.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../board/incident_drawer.dart';
import '../common_page.dart';

/// Incident history (Joshua, 2026-10-16): closed incidents, newest first,
/// for dispatchers and admins. Filters by period, type, how it ended, and a
/// search; a row opens its details read-only; the filtered list downloads
/// as CSV without personal data.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  IncidentType? _type;
  IncidentEnding? _ending;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = ref.read(historyNowProvider)();
    final range = ref.read(historyRangeProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2026),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: range.from.isAfter(now) ? now : range.from,
        end: range.to.isAfter(now) ? now : range.to,
      ),
    );
    if (picked != null) {
      ref.read(historyRangeProvider.notifier).custom(picked.start, picked.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final range = ref.watch(historyRangeProvider);
    final history = ref.watch(historyProvider);
    final units = ref.watch(unitsByIdProvider);
    final rows = filterHistory(
      history.value ?? const [],
      type: _type,
      ending: _ending,
      query: _search.text,
    );

    return PageFrame(
      title: l10n.historyTitle,
      subtitle: l10n.historySubtitle,
      headerTrailing: OutlinedButton.icon(
        key: const ValueKey('history-csv'),
        onPressed: rows.isEmpty
            ? null
            : () => downloadText(
                historyCsvName(range.from, range.to),
                historyCsv(rows, unitCallSign: (id) => units[id]?.callSign),
              ),
        icon: const Icon(Symbols.download_rounded),
        label: Text(l10n.exportCsv),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: SagipSpace.md,
            runSpacing: SagipSpace.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<HistoryPreset>(
                segments: [
                  ButtonSegment(
                    value: HistoryPreset.today,
                    label: Text(l10n.historyToday),
                  ),
                  ButtonSegment(
                    value: HistoryPreset.week,
                    label: Text(l10n.historyWeek),
                  ),
                  ButtonSegment(
                    value: HistoryPreset.month,
                    label: Text(l10n.historyMonth),
                  ),
                  ButtonSegment(
                    value: HistoryPreset.custom,
                    label: Text(
                      range.preset == HistoryPreset.custom
                          ? l10n.historyRange(
                              formatDate(range.from, locale),
                              formatDate(range.to, locale),
                            )
                          : l10n.historyCustom,
                    ),
                  ),
                ],
                selected: {range.preset},
                showSelectedIcon: false,
                onSelectionChanged: (s) => s.single == HistoryPreset.custom
                    ? _pickRange()
                    : ref.read(historyRangeProvider.notifier).preset(s.single),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<IncidentType?>(
                  key: const ValueKey('history-type'),
                  initialValue: _type,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.colType),
                  items: [
                    DropdownMenuItem(value: null, child: Text(l10n.historyAll)),
                    for (final t in IncidentType.values)
                      DropdownMenuItem(
                        value: t,
                        child: Text(l10n.incidentType(t)),
                      ),
                  ],
                  onChanged: (t) => setState(() => _type = t),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<IncidentEnding?>(
                  key: const ValueKey('history-ending'),
                  initialValue: _ending,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.historyEnding),
                  items: [
                    DropdownMenuItem(value: null, child: Text(l10n.historyAll)),
                    for (final e in IncidentEnding.values)
                      DropdownMenuItem(
                        value: e,
                        child: Text(l10n.historyEndingName(e.name)),
                      ),
                  ],
                  onChanged: (e) => setState(() => _ending = e),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  key: const ValueKey('history-search'),
                  controller: _search,
                  decoration: InputDecoration(
                    labelText: l10n.historySearch,
                    prefixIcon: const Icon(Symbols.search_rounded),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: SagipSpace.lg),
          AsyncBody(
            value: history,
            isEmpty: (_) => rows.isEmpty,
            empty: EmptyState(
              icon: Symbols.event_note_rounded,
              title: (history.value ?? const []).isEmpty
                  ? l10n.historyEmpty
                  : l10n.historyNoMatch,
            ),
            builder: (_) => _HistoryTable(rows: rows, units: units),
          ),
        ],
      ),
    );
  }
}

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({required this.rows, required this.units});

  final List<ClosedIncident> rows;
  final Map<String, ResponseUnit> units;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final tabular = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return TableCard(
      table: DataTable(
        showCheckboxColumn: false,
        columns: [
          DataColumn(label: Text(l10n.historyColId)),
          DataColumn(label: Text(l10n.colType)),
          DataColumn(label: Text(l10n.historyColPlace)),
          DataColumn(label: Text(l10n.historyColReceived)),
          DataColumn(label: Text(l10n.historyColClosed)),
          DataColumn(label: Text(l10n.historyEnding)),
          DataColumn(label: Text(l10n.historyColUnit)),
          DataColumn(label: Text(l10n.historyColResponse)),
        ],
        rows: [
          for (final c in rows)
            DataRow(
              key: ValueKey('history-${c.incident.id}'),
              onSelectChanged: (_) => showHistoryDetails(context, c),
              cells: [
                DataCell(Text(c.incident.id, style: tabular)),
                DataCell(
                  Text(
                    c.incident.type == null
                        ? l10n.typeNotSet
                        : l10n.incidentType(c.incident.type!),
                  ),
                ),
                DataCell(Text(c.incident.place)),
                DataCell(
                  Text(
                    formatDateTime(c.incident.receivedAt, locale),
                    style: tabular,
                  ),
                ),
                DataCell(
                  Text(
                    c.incident.resolvedAt == null
                        ? ''
                        : formatDateTime(c.incident.resolvedAt!, locale),
                    style: tabular,
                  ),
                ),
                DataCell(_EndingChip(ending: c.ending)),
                DataCell(
                  Text(
                    c.incident.assignedUnitId == null
                        ? l10n.historyNoUnit
                        : units[c.incident.assignedUnitId!]?.callSign ??
                              c.incident.assignedUnitId!,
                  ),
                ),
                DataCell(
                  Text(
                    c.responseTime == null ? '' : formatWait(c.responseTime!),
                    style: tabular,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EndingChip extends StatelessWidget {
  const _EndingChip({required this.ending});

  final IncidentEnding ending;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final (tone, icon) = switch (ending) {
      IncidentEnding.resolved => (p.success, Symbols.check_circle_rounded),
      IncidentEnding.falseReport => (p.critical, Symbols.block_rounded),
      IncidentEnding.cancelled => (p.neutral, Symbols.undo_rounded),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(SagipRadius.chip),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SagipSpace.sm,
          vertical: SagipSpace.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: tone.text),
            const SizedBox(width: SagipSpace.xs),
            Text(
              l10n.historyEndingName(ending.name),
              style: Theme.of(context).textTheme.labelMedium!
                  .copyWith(color: tone.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// A closed incident's details in a panel at the right, read-only.
Future<void> showHistoryDetails(BuildContext context, ClosedIncident c) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppLocalizations.of(context).close,
      barrierColor: Colors.black26,
      transitionDuration: SagipMotion.base,
      pageBuilder: (context, _, _) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: IncidentDrawer.width,
          height: double.infinity,
          child: _HistoryDetails(closed: c),
        ),
      ),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: SagipMotion.enter)),
        child: child,
      ),
    );

class _HistoryDetails extends ConsumerWidget {
  const _HistoryDetails({required this.closed});

  final ClosedIncident closed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final i = closed.incident;
    final unit = i.assignedUnitId == null
        ? null
        : ref.watch(unitsByIdProvider)[i.assignedUnitId!];

    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: SagipSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: text.bodyMedium!.copyWith(color: p.textSecondary),
            ),
          ),
          Expanded(child: Text(value, style: text.bodyMedium)),
        ],
      ),
    );

    return Material(
      key: const ValueKey('history-details'),
      color: p.panel,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SagipSpace.xxl),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.historyDetailsTitle(i.id),
                    style: text.labelLarge!.copyWith(color: p.textSecondary),
                  ),
                ),
                IconButton(
                  tooltip: l10n.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Symbols.close_rounded),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _EndingChip(ending: closed.ending),
            ),
            const SizedBox(height: SagipSpace.md),
            Text(l10n.incidentTitle(i), style: text.headlineSmall),
            Text(i.place, style: text.bodyLarge),
            const SizedBox(height: SagipSpace.lg),
            line(l10n.historyColReceived, formatDateTime(i.receivedAt, locale)),
            line(
              l10n.historyVerified,
              i.verificationMethod == null
                  ? l10n.historyNotVerified
                  : l10n.verificationMethod(i.verificationMethod!),
            ),
            line(
              l10n.historyColUnit,
              unit == null
                  ? (i.assignedUnitId ?? l10n.historyNoUnit)
                  : '${unit.callSign}, ${unit.station}',
            ),
            if (closed.onSceneAt != null)
              line(
                l10n.historyOnScene,
                formatDateTime(closed.onSceneAt!, locale),
              ),
            if (i.resolvedAt != null)
              line(
                l10n.historyColClosed,
                formatDateTime(i.resolvedAt!, locale),
              ),
            if (closed.responseTime != null)
              line(l10n.historyColResponse, formatWait(closed.responseTime!)),
            const SizedBox(height: SagipSpace.md),
            FacebookPostLine(incident: i),
            const SizedBox(height: SagipSpace.xl),
            Text(l10n.historyReportTitle, style: text.titleSmall),
            const SizedBox(height: SagipSpace.xs),
            if (!closed.hasReport)
              Text(
                l10n.historyNoReport,
                style: text.bodyMedium!.copyWith(color: p.textSecondary),
              )
            else ...[
              line(
                l10n.historyOutcome,
                l10n.historyOutcomeName(closed.outcome!.name),
              ),
              line(l10n.historyAssisted, '${closed.personsAssisted ?? 0}'),
              line(l10n.historyHouses, '${closed.housesDamaged ?? 0}'),
              line(l10n.historyInjured, '${closed.injured ?? 0}'),
              line(l10n.historyMissing, '${closed.missing ?? 0}'),
              line(l10n.historyFamilies, '${closed.affectedFamilies ?? 0}'),
            ],
            if (i.origin == IncidentOrigin.sos && i.residentId != null) ...[
              const SizedBox(height: SagipSpace.xl),
              ResidentNoticesSection(incident: i),
            ],
            const SizedBox(height: SagipSpace.xl),
            IncidentTimeline(incident: i),
          ],
        ),
      ),
    );
  }
}
