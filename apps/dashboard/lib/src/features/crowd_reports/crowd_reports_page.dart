import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/async_body.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';
import '../board/map_parts.dart';

/// D6: crowd reports from the last 60 minutes, grouped the way DBSCAN sees
/// them: confirmed clusters (3 or more within 50 m) and unverified singles.
class CrowdReportsPage extends ConsumerStatefulWidget {
  const CrowdReportsPage({super.key});

  @override
  ConsumerState<CrowdReportsPage> createState() => _CrowdReportsPageState();
}

class _CrowdReportsPageState extends ConsumerState<CrowdReportsPage> {
  final _map = MapController();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final reportsAsync = ref.watch(crowdReportsProvider);
    final reports = reportsAsync.value ?? const <CrowdReport>[];
    final incidents = {
      for (final i
          in ref.watch(activeIncidentsProvider).value ?? const <Incident>[])
        i.id: i,
    };

    final clusters = <String, List<CrowdReport>>{};
    final singles = <CrowdReport>[];
    for (final r in reports) {
      if (r.incidentId != null && incidents.containsKey(r.incidentId)) {
        (clusters[r.incidentId!] ??= []).add(r);
      } else if (r.incidentId == null) {
        singles.add(r);
      }
    }
    singles.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    final clustered = clusters.values.fold<int>(0, (n, l) => n + l.length);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 420,
          decoration: BoxDecoration(
            color: p.panel,
            border: Border(right: BorderSide(color: p.hairline)),
          ),
          child: AsyncBody(
            value: reportsAsync,
            isEmpty: (list) => list.isEmpty,
            empty: EmptyState(
              icon: Symbols.groups_rounded,
              title: l10n.crowdEmpty,
            ),
            builder: (_) => ListView(
              padding: const EdgeInsets.only(bottom: SagipSpace.xxl),
              children: [
                Padding(
                  padding: const EdgeInsets.all(SagipSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.crowdReportsTitle,
                              style: text.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: SagipSpace.sm),
                          SagipChip(label: l10n.crowdWindow, tone: p.neutral),
                        ],
                      ),
                      const SizedBox(height: SagipSpace.sm),
                      Text(
                        l10n.crowdSummary(
                          reports.length,
                          clustered,
                          singles.length,
                        ),
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                for (final entry in clusters.entries)
                  _ClusterCard(
                    incident: incidents[entry.key]!,
                    reports: entry.value,
                    onFocus: (point) => _map.move(toLatLng(point), 17),
                  ),
                if (singles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SagipSpace.lg,
                      SagipSpace.xl,
                      SagipSpace.lg,
                      SagipSpace.sm,
                    ),
                    child: Text(
                      l10n.unverifiedSection,
                      style: text.labelMedium!.copyWith(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                for (final r in singles)
                  _ReportRow(
                    report: r,
                    onTap: () => _map.move(toLatLng(r.location), 17),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: manilaCenter,
                  initialZoom: 13.6,
                  minZoom: 11,
                  maxZoom: 18,
                  backgroundColor: p.canvas,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  const SagipBaseMap(),
                  // The 50 m clustering radius around each confirmed cluster.
                  CircleLayer(
                    circles: [
                      for (final id in clusters.keys)
                        CircleMarker(
                          point: toLatLng(incidents[id]!.location),
                          radius: 50,
                          useRadiusInMeter: true,
                          color: p.critical.tint,
                          borderColor: p.critical.fill,
                          borderStrokeWidth: 1.5,
                        ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      for (final r in reports)
                        Marker(
                          point: toLatLng(r.location),
                          width: ReportMarkerRing.size,
                          height: ReportMarkerRing.size,
                          child: Tooltip(
                            message: r.description,
                            child: ReportMarkerRing(clustered: r.isClustered),
                          ),
                        ),
                      // Each cluster's count, just above its reports so the
                      // dots stay visible.
                      for (final entry in clusters.entries)
                        Marker(
                          key: ValueKey('cluster-count-${entry.key}'),
                          point: toLatLng(incidents[entry.key]!.location),
                          width: ClusterCountMarker.size,
                          height: ClusterCountMarker.size,
                          alignment: const Alignment(0, -2.2),
                          child: Tooltip(
                            message: l10n.clusterReports(entry.value.length),
                            child: ClusterCountMarker(
                              count: entry.value.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const MapAttribution(),
                ],
              ),
              Positioned(
                left: SagipSpace.lg,
                right: 120,
                bottom: SagipSpace.x3,
                child: Container(
                  padding: const EdgeInsets.all(SagipSpace.lg),
                  decoration: floatingCard(p),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.info_rounded,
                        size: 20,
                        color: p.textSecondary,
                      ),
                      const SizedBox(width: SagipSpace.md),
                      Expanded(
                        child: Text(l10n.crowdRule, style: text.bodyMedium),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: SagipSpace.lg,
                bottom: SagipSpace.x3,
                child: ZoomControls(controller: _map),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClusterCard extends StatelessWidget {
  const _ClusterCard({
    required this.incident,
    required this.reports,
    required this.onFocus,
  });

  final Incident incident;
  final List<CrowdReport> reports;
  final ValueChanged<GeoPoint> onFocus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final type = incident.type == null
        ? l10n.typeNotSet
        : l10n.incidentType(incident.type!);
    final sorted = [...reports]
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));

    return InkWell(
      onTap: () => onFocus(incident.location),
      child: Container(
        margin: const EdgeInsets.only(bottom: SagipSpace.sm),
        padding: const EdgeInsets.fromLTRB(
          13,
          SagipSpace.lg,
          SagipSpace.lg,
          SagipSpace.lg,
        ),
        decoration: BoxDecoration(
          color: p.panelRaised,
          border: Border(left: BorderSide(color: p.critical.fill, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SagipChip.status(
                  label: l10n.incidentStatus(IncidentStatus.confirmed),
                  visual: incidentStatusVisual(IncidentStatus.confirmed, p),
                ),
                const Spacer(),
                Text(l10n.clusterInQueue, style: text.bodySmall),
              ],
            ),
            const SizedBox(height: SagipSpace.md),
            Text(
              l10n.clusterCardTitle(type, reports.length),
              style: text.titleSmall,
            ),
            Text(incident.place, style: text.bodySmall),
            const SizedBox(height: SagipSpace.md),
            for (final r in sorted) _ReportText(report: r),
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => context.go(Routes.incident(incident.id)),
              child: Text(l10n.openInQueue),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportText extends StatelessWidget {
  const _ReportText({required this.report});

  final CrowdReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: SagipSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('"${report.description}"', style: text.bodyMedium),
          Text(
            l10n.reportMeta(
              formatTime(report.submittedAt, locale),
              l10n.channel(report.channel).toLowerCase(),
              report.suggestedType == null
                  ? l10n.typeNotSet
                  : l10n.incidentType(report.suggestedType!).toLowerCase(),
              ((report.suggestionConfidence ?? 0) * 100).round(),
            ),
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report, required this.onTap});

  final CrowdReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SagipSpace.lg,
          vertical: SagipSpace.md,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReportText(report: report),
                  Text(report.place, style: text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: SagipSpace.sm),
            SagipChip.status(
              label: l10n.statusUnverified,
              visual: incidentStatusVisual(IncidentStatus.unverified, p),
            ),
          ],
        ),
      ),
    );
  }
}
