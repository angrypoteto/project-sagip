import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/async_body.dart';
import '../../common/download.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common_page.dart';

/// A4 Performance analytics (admin): dispatch, verification, and response
/// times from the incident timeline, SOS by channel, breakdowns, and the
/// Dijkstra run times, with a CSV export (plan 7.4, Objective 1).
class AnalyticsPage extends ConsumerWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final period = ref.watch(analyticsPeriodProvider);
    final report = ref.watch(analyticsProvider);

    return PageFrame(
      title: l10n.navAnalytics,
      subtitle: l10n.analyticsSubtitle,
      headerTrailing: Wrap(
        spacing: SagipSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<AnalyticsPeriod>(
            segments: [
              ButtonSegment(
                value: AnalyticsPeriod.day,
                label: Text(l10n.periodDay),
              ),
              ButtonSegment(
                value: AnalyticsPeriod.week,
                label: Text(l10n.periodWeek),
              ),
              ButtonSegment(
                value: AnalyticsPeriod.month,
                label: Text(l10n.periodMonth),
              ),
            ],
            selected: {period},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                ref.read(analyticsPeriodProvider.notifier).select(s.single),
          ),
          IconButton(
            tooltip: l10n.refresh,
            onPressed: () => ref.invalidate(analyticsProvider),
            icon: const Icon(Symbols.refresh_rounded),
          ),
          OutlinedButton.icon(
            onPressed: report.value == null
                ? null
                : () => downloadText(
                    'sagip-analytics-${dateOnly(report.value!.from)}'
                    '-to-${dateOnly(report.value!.to)}.csv',
                    analyticsCsv(report.value!),
                  ),
            icon: const Icon(Symbols.download_rounded),
            label: Text(l10n.exportCsv),
          ),
        ],
      ),
      child: AsyncBody(
        value: report,
        isEmpty: (r) => r.incidents == 0,
        empty: EmptyState(
          icon: Symbols.monitoring_rounded,
          title: l10n.analyticsEmpty,
        ),
        builder: (r) => _Report(report: r),
      ),
    );
  }
}

String _time(AppLocalizations l10n, double? seconds) => seconds == null
    ? l10n.noValue
    : formatWait(Duration(seconds: seconds.round()));

class _Report extends StatelessWidget {
  const _Report({required this.report});

  final AnalyticsReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final r = report;
    final routing = r.routing.where(
      (s) => s.kind == RoutingRunKind.suggestions,
    );
    final dijkstra = routing.isEmpty ? null : routing.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: SagipSpace.lg,
          runSpacing: SagipSpace.lg,
          children: [
            _Kpi(
              icon: Symbols.emergency_rounded,
              label: l10n.kpiIncidents,
              value: '${r.incidents}',
              footer: l10n.kpiIncidentsFooter(r.resolved, r.falseReports),
            ),
            _Kpi(
              icon: Symbols.assignment_ind_rounded,
              label: l10n.kpiDispatch,
              value: _time(l10n, r.medianDispatchS),
              footer: l10n.kpiDispatchFooter(_time(l10n, r.avgDispatchS)),
            ),
            _Kpi(
              icon: Symbols.location_on_rounded,
              label: l10n.kpiResponse,
              value: _time(l10n, r.medianResponseS),
              footer: l10n.kpiResponseFooter(_time(l10n, r.avgResponseS)),
            ),
            _Kpi(
              icon: Symbols.verified_rounded,
              label: l10n.kpiVerify,
              value: _time(l10n, r.avgVerifyS),
              footer: l10n.kpiVerifyFooter,
            ),
            _Kpi(
              icon: Symbols.cell_tower_rounded,
              label: l10n.kpiSosChannels,
              value: '${r.sos}',
              footer: r.sosByChannel.isEmpty
                  ? l10n.noValue
                  : [
                      for (final e in r.sosByChannel.entries)
                        l10n.channelCount(l10n.channel(e.key), e.value),
                    ].join(' · '),
            ),
            _Kpi(
              icon: Symbols.route_rounded,
              label: l10n.kpiDijkstra,
              value: dijkstra == null
                  ? l10n.noValue
                  : l10n.kpiDijkstraValue(dijkstra.avgMs.toStringAsFixed(1)),
              footer: dijkstra == null
                  ? l10n.kpiDijkstraNone
                  : l10n.kpiDijkstraFooter(
                      dijkstra.runs,
                      dijkstra.p95Ms.toStringAsFixed(1),
                    ),
            ),
          ],
        ),
        const SizedBox(height: SagipSpace.lg),
        Row(
          children: [
            Icon(Symbols.info_rounded, size: 18, color: p.info.text),
            const SizedBox(width: SagipSpace.sm),
            Expanded(child: Text(l10n.baselineNote, style: text.bodySmall)),
          ],
        ),
        const SizedBox(height: SagipSpace.xl),
        _Daily(days: r.daily),
        const SizedBox(height: SagipSpace.xl),
        _GroupTable(
          title: l10n.byTypeTitle,
          nameColumn: l10n.colType,
          countColumn: l10n.colIncidents,
          groups: r.byType,
          name: (g) => switch (IncidentType.values.asNameMap()[g.key]) {
            final t? => l10n.incidentType(t),
            null => l10n.typeNotSet,
          },
        ),
        const SizedBox(height: SagipSpace.xl),
        _GroupTable(
          title: l10n.byBarangayTitle,
          nameColumn: l10n.colBarangay,
          countColumn: l10n.colIncidents,
          groups: r.byBarangay,
          name: (g) => g.label,
        ),
        const SizedBox(height: SagipSpace.xl),
        _GroupTable(
          title: l10n.byUnitTitle,
          nameColumn: l10n.colUnit,
          countColumn: l10n.colJobs,
          groups: r.byUnit,
          name: (g) => g.label,
          travel: true,
        ),
        const SizedBox(height: SagipSpace.xl),
        _Delivery(delivery: r.delivery),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.footer,
  });

  final IconData icon;
  final String label;
  final String value;
  final String footer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(SagipSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: p.textSecondary),
                  const SizedBox(width: SagipSpace.sm),
                  Expanded(child: Text(label, style: text.labelMedium)),
                ],
              ),
              const SizedBox(height: SagipSpace.md),
              Text(
                value,
                style: text.displaySmall!.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: SagipSpace.xs),
              Text(footer, style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Incidents per Manila day as bars, with the day's average response time.
class _Daily extends StatelessWidget {
  const _Daily({required this.days});

  final List<AnalyticsDay> days;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final most = days.fold<int>(1, (m, d) => d.count > m ? d.count : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.dailyTitle, style: text.titleMedium),
            const SizedBox(height: SagipSpace.lg),
            for (final d in days)
              Padding(
                padding: const EdgeInsets.only(bottom: SagipSpace.sm),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        formatDate(d.day, locale),
                        style: text.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 16,
                            width: box.maxWidth * d.count / most,
                            decoration: BoxDecoration(
                              color: p.info.fill,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: SagipSpace.md),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${d.count}',
                        textAlign: TextAlign.end,
                        style: text.bodyMedium!.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: SagipSpace.md),
                    SizedBox(
                      width: 220,
                      child: Text(
                        l10n.dailyAvgResponse(_time(l10n, d.avgResponseS)),
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupTable extends StatelessWidget {
  const _GroupTable({
    required this.title,
    required this.nameColumn,
    required this.countColumn,
    required this.groups,
    required this.name,
    this.travel = false,
  });

  final String title;
  final String nameColumn;
  final String countColumn;
  final List<AnalyticsGroup> groups;
  final String Function(AnalyticsGroup g) name;

  /// Units show travel time (assigned to on scene) instead of dispatch.
  final bool travel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final tabular = text.bodyMedium!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: text.titleMedium),
        const SizedBox(height: SagipSpace.sm),
        TableCard(
          table: DataTable(
            columns: [
              DataColumn(label: Text(nameColumn)),
              DataColumn(label: Text(countColumn), numeric: true),
              DataColumn(
                label: Text(travel ? l10n.colAvgTravel : l10n.colAvgDispatch),
                numeric: true,
              ),
              DataColumn(label: Text(l10n.colAvgResponse), numeric: true),
            ],
            rows: [
              for (final g in groups)
                DataRow(
                  cells: [
                    DataCell(Text(name(g))),
                    DataCell(Text('${g.count}', style: tabular)),
                    DataCell(
                      Text(
                        _time(l10n, travel ? g.avgTravelS : g.avgDispatchS),
                        style: tabular,
                      ),
                    ),
                    DataCell(Text(_time(l10n, g.avgResponseS), style: tabular)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The Objective 3 harness: SOS by the tier that delivered them first, the
/// delay from capture to receipt, and the success rate once the trial team
/// enters how many attempts they made on the phones.
class _Delivery extends StatefulWidget {
  const _Delivery({required this.delivery});

  final SosDeliveryReport delivery;

  @override
  State<_Delivery> createState() => _DeliveryState();
}

class _DeliveryState extends State<_Delivery> {
  final _attempts = TextEditingController();

  @override
  void dispose() {
    _attempts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final tabular = text.bodyMedium!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final d = widget.delivery;
    final attempts = int.tryParse(_attempts.text.trim());
    final tooFew = attempts != null && attempts < d.delivered;

    DataRow row(String name, List<Object?> cells, {bool bold = false}) =>
        DataRow(
          cells: [
            DataCell(
              Text(
                name,
                style: bold
                    ? text.bodyMedium!.copyWith(fontWeight: FontWeight.w600)
                    : null,
              ),
            ),
            for (final c in cells)
              DataCell(
                Text(switch (c) {
                  final double s => _time(l10n, s),
                  null => l10n.noValue,
                  _ => '$c',
                }, style: tabular),
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.deliveryTitle, style: text.titleMedium),
        const SizedBox(height: SagipSpace.xs),
        Text(l10n.deliveryNote, style: text.bodySmall),
        const SizedBox(height: SagipSpace.sm),
        TableCard(
          table: DataTable(
            columns: [
              DataColumn(label: Text(l10n.colFirstTier)),
              DataColumn(label: Text(l10n.colDelivered), numeric: true),
              DataColumn(label: Text(l10n.colMedianDelay), numeric: true),
              DataColumn(label: Text(l10n.colP95Delay), numeric: true),
              DataColumn(label: Text(l10n.colMaxDelay), numeric: true),
              for (final w in SosDeliveryReport.windows)
                DataColumn(label: Text(l10n.colWithin(w ~/ 60)), numeric: true),
            ],
            rows: [
              for (final c in d.channels)
                row(l10n.channel(c.channel), [
                  c.count,
                  c.medianS,
                  c.p95S,
                  c.maxS,
                  c.within60,
                  c.within300,
                  c.within900,
                ]),
              row(l10n.deliveryAllTiers, [
                d.delivered,
                null,
                null,
                null,
                for (final w in SosDeliveryReport.windows) d.deliveredWithin(w),
              ], bold: true),
            ],
          ),
        ),
        const SizedBox(height: SagipSpace.md),
        Text(
          d.relayUploads == 0
              ? l10n.relayNone
              : l10n.relayLine(
                  d.relayUploads,
                  d.relayedSos,
                  '${d.relayMaxHops ?? 0}',
                ),
          style: text.bodySmall,
        ),
        const SizedBox(height: SagipSpace.lg),
        Wrap(
          spacing: SagipSpace.xl,
          runSpacing: SagipSpace.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                key: const ValueKey('sos-attempts'),
                controller: _attempts,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.attemptsLabel,
                  helperText: l10n.attemptsHelp,
                  errorText: tooFew ? l10n.attemptsTooFew : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (attempts != null && attempts > 0 && !tooFew)
              for (final w in SosDeliveryReport.windows)
                Text(
                  l10n.successRate(
                    w ~/ 60,
                    d.deliveredWithin(w),
                    attempts,
                    (100 * d.deliveredWithin(w) / attempts).toStringAsFixed(1),
                  ),
                  style: tabular.copyWith(
                    color: d.deliveredWithin(w) / attempts >= 0.95
                        ? p.success.text
                        : p.textPrimary,
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
