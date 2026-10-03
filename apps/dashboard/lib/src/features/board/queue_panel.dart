import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/async_body.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

enum QueueFilter { all, pending, sos, reports }

class QueueFilterController extends Notifier<QueueFilter> {
  @override
  QueueFilter build() => QueueFilter.all;

  void set(QueueFilter filter) => state = filter;
}

final queueFilterProvider =
    NotifierProvider<QueueFilterController, QueueFilter>(
      QueueFilterController.new,
    );

bool _matches(Incident i, QueueFilter f) => switch (f) {
  QueueFilter.all => true,
  QueueFilter.pending => i.status == IncidentStatus.pendingVerification,
  QueueFilter.sos => i.origin == IncidentOrigin.sos,
  QueueFilter.reports => i.origin == IncidentOrigin.crowdCluster,
};

/// The queue after the dispatcher's filter, in priority order.
final visibleQueueProvider = Provider<List<Incident>>((ref) {
  final filter = ref.watch(queueFilterProvider);
  final queue = ref.watch(triageQueueProvider).value ?? const [];
  return [
    for (final i in queue)
      if (_matches(i, filter)) i,
  ];
});

/// Left panel of the Command Board: the ranked Triage Queue (FR2).
class QueuePanel extends ConsumerWidget {
  const QueuePanel({
    super.key,
    required this.selectedId,
    required this.onSelect,
  });

  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final queue = ref.watch(triageQueueProvider);
    final all = queue.value ?? const <Incident>[];
    final filter = ref.watch(queueFilterProvider);
    final visible = ref.watch(visibleQueueProvider);

    int count(QueueFilter f) => all.where((i) => _matches(i, f)).length;

    return ColoredBox(
      color: p.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(SagipSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(l10n.queueTitle, style: text.titleMedium),
                    const SizedBox(width: SagipSpace.md),
                    Expanded(
                      child: Text(
                        l10n.queueCount(all.length),
                        style: text.bodySmall,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SagipSpace.md),
                Wrap(
                  spacing: SagipSpace.sm,
                  runSpacing: SagipSpace.sm,
                  children: [
                    for (final f in QueueFilter.values)
                      _FilterChip(
                        label: switch (f) {
                          QueueFilter.all => l10n.filterAll(count(f)),
                          QueueFilter.pending => l10n.filterPending(count(f)),
                          QueueFilter.sos => l10n.filterSos(count(f)),
                          QueueFilter.reports => l10n.filterReports(count(f)),
                        },
                        selected: filter == f,
                        onTap: () =>
                            ref.read(queueFilterProvider.notifier).set(f),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.hairline),
          Expanded(
            child: AsyncBody(
              value: queue,
              isEmpty: (list) => list.isEmpty,
              empty: EmptyState(
                icon: Symbols.inbox_rounded,
                title: l10n.queueEmpty,
                message: l10n.queueEmptyMessage,
              ),
              builder: (_) => visible.isEmpty
                  ? EmptyState(
                      icon: Symbols.filter_alt_off_rounded,
                      title: l10n.queueFilterEmpty,
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final incident = visible[index];
                        return QueueRow(
                          key: ValueKey(incident.id),
                          incident: incident,
                          selected: incident.id == selectedId,
                          onTap: () => onSelect(incident.id),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.panelRaised : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SagipRadius.chip),
          side: BorderSide(color: selected ? p.info.fill : p.hairlineStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(SagipRadius.chip),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: text.labelMedium!.copyWith(
                fontWeight: FontWeight.w600,
                color: selected ? p.textPrimary : p.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One Triage Queue row: severity edge, type, status, place, wait timer,
/// channel, vulnerable household, and a mock-location warning.
class QueueRow extends ConsumerWidget {
  const QueueRow({
    super.key,
    required this.incident,
    required this.selected,
    required this.onTap,
  });

  final Incident incident;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final unit = ref.watch(unitsByIdProvider)[incident.assignedUnitId];
    final severity = ref
        .watch(priorityRulesProvider)
        .score(incident, now)
        .severity;
    final visual = incidentStatusVisual(incident.status, p);
    final statusLabel = switch (incident.status) {
      IncidentStatus.pendingVerification => l10n.statusPendingShort,
      final s when unit != null => l10n.statusWithUnit(
        l10n.incidentStatus(s),
        unit.callSign,
      ),
      final s => l10n.incidentStatus(s),
    };
    final meta = text.labelSmall!.copyWith(color: p.textSecondary);
    final strong = text.labelSmall!.copyWith(color: p.textPrimary);
    final isSos = incident.origin == IncidentOrigin.sos;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.panelRaised : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  width: 3,
                  color: selected ? p.info.fill : severityColor(severity, p),
                ),
                bottom: BorderSide(color: p.hairline),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(13, 14, SagipSpace.lg, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isSos ? Symbols.sos_rounded : incidentTypeIcon(incident.type),
                  size: 20,
                  color: isSos ? p.critical.text : p.textSecondary,
                ),
                const SizedBox(width: SagipSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.incidentTitle(incident),
                              style: text.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: SagipSpace.sm),
                          SagipChip(
                            label: statusLabel,
                            tone: visual.tone,
                            icon: visual.icon,
                            look: visual.look,
                          ),
                        ],
                      ),
                      const SizedBox(height: SagipSpace.xs),
                      Text(incident.place, style: text.bodySmall),
                      const SizedBox(height: SagipSpace.xs),
                      Wrap(
                        spacing: 14,
                        runSpacing: SagipSpace.xs,
                        children: [
                          _Meta(
                            icon: Symbols.timer_rounded,
                            label: formatWait(
                              now.difference(incident.capturedAt),
                            ),
                            style: strong.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          _Meta(
                            icon: channelIcon(incident.channel),
                            label: l10n.channel(incident.channel),
                            style: meta,
                          ),
                          if (incident.vulnerable.isNotEmpty)
                            _Meta(
                              icon: vulnerabilityIcon(
                                incident.vulnerable.first,
                              ),
                              label: incident.vulnerable
                                  .map(l10n.vulnerability)
                                  .join(', '),
                              style: strong,
                            ),
                          if (incident.isSimulated)
                            _Meta(
                              icon: Symbols.science_rounded,
                              label: l10n.simulatedTag,
                              style: text.labelSmall!.copyWith(
                                color: p.info.text,
                              ),
                            ),
                          if (incident.mockLocationSuspected)
                            _Meta(
                              icon: Symbols.gps_off_rounded,
                              label: l10n.mockLocationWarning,
                              style: text.labelSmall!.copyWith(
                                color: p.warning.text,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, required this.style});

  final IconData icon;
  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: style.color),
        const SizedBox(width: SagipSpace.xs),
        Flexible(
          child: Text(label, style: style, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
