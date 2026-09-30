import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/hotline.dart';
import '../../common/labels.dart';
import '../../common/offline_banner.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'add_details_sheet.dart';

/// R2 SOS status: where the SOS is, from "Saved on phone" to "Resolved".
/// The local record shows immediately; server progress fills in as it
/// arrives (plan 7.4).
class SosStatusPage extends ConsumerWidget {
  const SosStatusPage({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final loading = ref.watch(mySosProvider).isLoading;
    final sos = ref.watch(sosByIdProvider(clientId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sosStatusTitle)),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: sos == null
                ? (loading
                      ? const SkeletonList()
                      : EmptyState(
                          icon: Symbols.search_off_rounded,
                          title: l10n.sosNotFound,
                        ))
                : _Body(sos: sos),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SagipSpace.xl,
            SagipSpace.sm,
            SagipSpace.xl,
            SagipSpace.lg,
          ),
          child: FilledButton.icon(
            onPressed: () => showHotlineDialog(context),
            icon: const Icon(Symbols.call_rounded),
            label: Text(l10n.callMdrrmd),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.sos});

  final SosRequest sos;

  Future<void> _addDetails(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final details = await showAddDetailsSheet(context, sos.details);
    if (details == null) return;
    await ref.read(sosRepositoryProvider).addDetails(sos.clientId, details);
    messenger.showSnackBar(SnackBar(content: Text(l10n.detailsSaved)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final signal = ref.watch(signalProvider).value ?? SignalState.internet;
    final elapsed = now.difference(sos.capturedAt);
    final resolved = sos.status == IncidentStatus.resolved;
    final showEta =
        (sos.status == IncidentStatus.assigned ||
            sos.status == IncidentStatus.enRoute) &&
        sos.etaMinutes != null;

    return ListView(
      padding: const EdgeInsets.all(SagipSpace.xl),
      children: [
        // Before delivery the heading already names the tier ("Sent by
        // SMS"); after it, the badge keeps "Delivered" visible under the
        // response status.
        if (sos.isDelivered) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: DeliveryBadge(
              state: DeliveryState.delivered,
              label: l10n.deliveryDelivered,
              dense: false,
            ),
          ),
          const SizedBox(height: SagipSpace.md),
        ],
        Text(l10n.sosState(sos), style: text.headlineMedium),
        const SizedBox(height: SagipSpace.xs),
        Text(
          l10n.elapsed(
            formatWait(elapsed.isNegative ? Duration.zero : elapsed),
          ),
          style: text.bodyLarge!.copyWith(
            color: p.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (!sos.isDelivered && signal != SignalState.internet) ...[
          const SizedBox(height: SagipSpace.md),
          Text(l10n.keepTrying, style: text.bodyMedium),
        ],
        if (resolved) ...[
          const SizedBox(height: SagipSpace.md),
          Text(l10n.resolvedBody, style: text.bodyLarge),
        ],
        if (showEta) ...[
          const SizedBox(height: SagipSpace.xl),
          _EtaCard(sos: sos),
        ],
        const SizedBox(height: SagipSpace.xl),
        _Timeline(sos: sos),
        const SizedBox(height: SagipSpace.xl),
        if (!resolved)
          OutlinedButton.icon(
            onPressed: () => _addDetails(context, ref),
            icon: const Icon(Symbols.edit_note_rounded),
            label: Text(
              sos.details.isEmpty ? l10n.addDetails : l10n.editDetails,
            ),
          ),
        const SizedBox(height: SagipSpace.xl),
        _LocationCard(sos: sos),
        if (!resolved) ...[
          const SizedBox(height: SagipSpace.xl),
          Text(l10n.guidanceTitle, style: text.titleMedium),
          const SizedBox(height: SagipSpace.sm),
          Text(l10n.guidanceBody, style: text.bodyMedium),
        ],
      ],
    );
  }
}

class _EtaCard extends StatelessWidget {
  const _EtaCard({required this.sos});

  final SosRequest sos;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.info.tint,
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.etaTitle,
              style: text.bodyMedium!.copyWith(color: p.info.text),
            ),
            Text(
              l10n.etaMinutes(sos.etaMinutes!),
              style: text.displaySmall!.copyWith(
                color: p.info.text,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (sos.unitCallSign != null && sos.unitType != null)
              Text(
                l10n.unitLine(sos.unitCallSign!, l10n.unitType(sos.unitType!)),
                style: text.titleSmall!.copyWith(color: p.info.text),
              ),
          ],
        ),
      ),
    );
  }
}

/// The delivery and response timeline (plan R2).
class _Timeline extends StatelessWidget {
  const _Timeline({required this.sos});

  final SosRequest sos;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final t = sos.statusTimes;
    final steps = <(String, DateTime?)>[
      (l10n.stepSaved, sos.capturedAt),
      (
        switch (sos.sentVia) {
          ReportChannel.app || ReportChannel.webForm => l10n.stepSentInternet,
          ReportChannel.sms => l10n.stepSentSms,
          ReportChannel.bleRelay => l10n.stepSentRelay,
          null => l10n.stepSent,
        },
        sos.sentAt,
      ),
      (l10n.stepReceived, sos.deliveredAt),
      (l10n.stepPending, t[IncidentStatus.pendingVerification]),
      (l10n.stepVerified, t[IncidentStatus.confirmed]),
      (
        sos.unitCallSign == null
            ? l10n.stepAssigned
            : l10n.stepAssignedUnit(sos.unitCallSign!),
        t[IncidentStatus.assigned],
      ),
      (l10n.stepEnRoute, t[IncidentStatus.enRoute]),
      (l10n.stepOnScene, t[IncidentStatus.onScene]),
      (l10n.stepResolved, t[IncidentStatus.resolved]),
    ];
    final current = steps.indexWhere((s) => s.$2 == null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.timelineTitle, style: text.titleMedium),
        const SizedBox(height: SagipSpace.md),
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            label: steps[i].$1,
            time: steps[i].$2 == null ? null : formatTime(steps[i].$2!, locale),
            state: steps[i].$2 != null
                ? _StepState.done
                : (i == current ? _StepState.current : _StepState.later),
            last: i == steps.length - 1,
          ),
      ],
    );
  }
}

enum _StepState { done, current, later }

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.time,
    required this.state,
    required this.last,
  });

  final String label;
  final String? time;
  final _StepState state;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final (icon, color) = switch (state) {
      _StepState.done => (Symbols.check_circle_rounded, p.success.text),
      _StepState.current => (Symbols.radio_button_checked_rounded, p.info.text),
      _StepState.later => (Symbols.radio_button_unchecked_rounded, p.hairline),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(icon, size: 22, color: color, fill: 1),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    color: state == _StepState.done
                        ? p.success.text
                        : p.hairline,
                  ),
                ),
            ],
          ),
          const SizedBox(width: SagipSpace.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: SagipSpace.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: text.bodyLarge!.copyWith(
                        color: state == _StepState.later
                            ? p.textSecondary
                            : p.textPrimary,
                        fontWeight: state == _StepState.current
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (time != null)
                    Text(
                      time!,
                      style: text.bodySmall!.copyWith(
                        color: p.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.sos});

  final SosRequest sos;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: p.hairline),
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Symbols.location_on_rounded, color: p.textSecondary),
            const SizedBox(width: SagipSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.locationTitle, style: text.titleSmall),
                  const SizedBox(height: SagipSpace.xs),
                  if (sos.barangay != null && sos.district != null)
                    Text(
                      l10n.place(sos.barangay!, sos.district!),
                      style: text.bodyMedium,
                    ),
                  Text(
                    sos.location == null
                        ? l10n.locationUnknown
                        : l10n.locationAccuracy(
                            formatCoordinates(sos.location!),
                            (sos.accuracyMeters ?? 0).round(),
                          ),
                    style: text.bodySmall!.copyWith(
                      color: p.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
