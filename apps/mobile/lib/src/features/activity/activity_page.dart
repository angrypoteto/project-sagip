import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../common/offline_banner.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';
import 'report_detail_sheet.dart';

enum _Tab { sos, reports }

/// R6 My activity: the resident's SOS requests and hazard reports, newest
/// first, each with its delivery or status. Read from the phone's copy, so
/// it works offline.
class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  var _tab = _Tab.sos;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myActivity)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OfflineBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SagipSpace.xl,
              SagipSpace.md,
              SagipSpace.xl,
              SagipSpace.sm,
            ),
            child: SegmentedButton<_Tab>(
              segments: [
                ButtonSegment(
                  value: _Tab.sos,
                  label: Text(l10n.activityTabSos),
                ),
                ButtonSegment(
                  value: _Tab.reports,
                  label: Text(l10n.activityTabReports),
                ),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _tab = s.single),
            ),
          ),
          Expanded(
            child: switch (_tab) {
              _Tab.sos => const _SosList(),
              _Tab.reports => const _ReportList(),
            },
          ),
        ],
      ),
    );
  }
}

/// Loading, error, and empty handling shared by both lists. A failed
/// refresh keeps the saved list and says so.
class _ListStates<T> extends StatelessWidget {
  const _ListStates({
    required this.value,
    required this.emptyIcon,
    required this.emptyText,
    required this.onRetry,
    required this.row,
  });

  final AsyncValue<List<T>> value;
  final IconData emptyIcon;
  final String emptyText;
  final VoidCallback onRetry;
  final Widget Function(T item) row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final items = value.value;
    if (items == null) {
      return value.hasError
          ? ErrorState(
              message: l10n.activityError,
              onRetry: onRetry,
              retryLabel: l10n.retry,
            )
          : const SkeletonList(rows: 4, rowHeight: 72);
    }
    if (items.isEmpty) {
      return EmptyState(icon: emptyIcon, title: emptyText);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: SagipSpace.x3),
      children: [
        if (value.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SagipSpace.xl,
              vertical: SagipSpace.sm,
            ),
            child: Text(
              l10n.activityError,
              style: text.bodySmall!.copyWith(color: p.warning.text),
            ),
          ),
        for (final (i, item) in items.indexed) ...[
          if (i > 0)
            Divider(
              height: 1,
              indent: SagipSpace.xl + 40 + SagipSpace.lg,
              endIndent: SagipSpace.xl,
            ),
          row(item),
        ],
      ],
    );
  }
}

class _SosList extends ConsumerWidget {
  const _SosList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    return _ListStates<SosRequest>(
      value: ref.watch(mySosProvider),
      emptyIcon: Symbols.sos_rounded,
      emptyText: l10n.activitySosEmpty,
      onRetry: () => ref.invalidate(mySosProvider),
      row: (s) => ActivityRow(
        icon: Symbols.sos_rounded,
        title: l10n.typeOrEmergency(s.details.type),
        subtitle: formatDateTime(s.capturedAt, locale),
        trailing: s.isDelivered && s.status != null
            ? SagipChip.status(
                label: l10n.incidentStatus(s.status!),
                visual: incidentStatusVisual(s.status!, p),
              )
            : DeliveryBadge(
                state: s.delivery,
                label: l10n.delivery(s.delivery),
              ),
        onTap: () => context.push(Routes.sos(s.clientId)),
      ),
    );
  }
}

class _ReportList extends ConsumerWidget {
  const _ReportList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    return _ListStates<HazardReport>(
      value: ref.watch(myReportsProvider),
      emptyIcon: Symbols.report_rounded,
      emptyText: l10n.activityReportsEmpty,
      onRetry: () => ref.invalidate(myReportsProvider),
      row: (r) => ActivityRow(
        icon: incidentTypeIcon(r.type),
        title: r.description,
        titleLines: 2,
        subtitle: formatDateTime(r.capturedAt, locale),
        trailing: r.stage != null
            ? SagipChip.status(
                label: l10n.reportStage(r.stage!),
                visual: reportStageVisual(r.stage!, p),
              )
            : DeliveryBadge(
                state: r.delivery,
                label: l10n.delivery(r.delivery),
              ),
        onTap: () => showReportDetail(context, r.clientId),
      ),
    );
  }
}

/// Color and icon for a report's stage, following the incident status
/// mapping (confirmed is signal, resolved is verdant).
StatusVisual reportStageVisual(
  ReportStage stage,
  SagipPalette p,
) => switch (stage) {
  ReportStage.received => StatusVisual(
    p.info,
    Symbols.inbox_rounded,
    ChipLook.outline,
  ),
  ReportStage.checking => StatusVisual(
    p.warning,
    Symbols.hourglass_top_rounded,
  ),
  ReportStage.confirmed => StatusVisual(p.critical, Symbols.warning_rounded),
  ReportStage.notConfirmed => StatusVisual(p.neutral, null, ChipLook.dashed),
  ReportStage.resolved => StatusVisual(p.success, Symbols.check_circle_rounded),
};

/// One row in a history list (R6, F7): an icon, a title and a time line,
/// and a chip on the right.
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.detail,
    this.titleLines = 1,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// An optional second line under the title, such as the barangay.
  final String? detail;

  /// Report descriptions may take two lines.
  final int titleLines;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final secondary = text.bodySmall!.copyWith(color: p.textSecondary);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SagipSpace.xl,
            vertical: SagipSpace.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.panel,
                  borderRadius: BorderRadius.circular(SagipRadius.control),
                  border: Border.all(color: p.hairline),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: p.textSecondary),
              ),
              const SizedBox(width: SagipSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: titleLines,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall,
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: secondary,
                      ),
                    Text(
                      subtitle,
                      style: secondary.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SagipSpace.md),
              // The chip takes what it needs, up to a limit, so the title
              // keeps most of the row.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: trailing,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
