import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/hotline.dart';
import '../../common/labels.dart';
import '../../common/offline_banner.dart';
import '../../common/photo_picker.dart';
import '../../common/timeline.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';
import 'add_details_sheet.dart';
import 'cancel_sos_sheet.dart';
import 'whats_happening_sheet.dart';

/// R2 SOS status: where the SOS is, from "Saved on phone" to "Resolved".
/// The local record shows immediately; server progress fills in as it
/// arrives (plan 7.4).
class SosStatusPage extends ConsumerStatefulWidget {
  const SosStatusPage({
    super.key,
    required this.clientId,
    this.askType = false,
  });

  final String clientId;

  /// Just sent: ask "What is happening?" once, over this screen (Joshua,
  /// 2026-10-16). The SOS has already gone; the answer is an optional
  /// detail.
  final bool askType;

  @override
  ConsumerState<SosStatusPage> createState() => _SosStatusPageState();
}

class _SosStatusPageState extends ConsumerState<SosStatusPage> {
  String get clientId => widget.clientId;

  @override
  void initState() {
    super.initState();
    if (widget.askType) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askType());
    }
  }

  Future<void> _askType() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final type = await showWhatsHappeningSheet(context);
    if (type == null || !mounted) return;
    final now = ref.read(sosByIdProvider(clientId))?.details;
    try {
      await ref
          .read(sosRepositoryProvider)
          .addDetails(
            clientId,
            SosDetails(
              type: type,
              peopleCount: now?.peopleCount,
              needsExtraHelp: now?.needsExtraHelp ?? false,
              note: now?.note,
            ),
          );
      messenger.showSnackBar(SnackBar(content: Text(l10n.detailsSaved)));
    } catch (_) {
      // Not sent now: it can be set later under Add details.
    }
  }

  @override
  Widget build(BuildContext context) {
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

  /// Asks MDRRMD to cancel ([reason] set) or takes that back (null). Needs
  /// internet: it is never queued.
  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref, {
    required bool ask,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(sosRepositoryProvider);
    SosCancelReason? reason;
    if (ask) {
      reason = await showCancelSosSheet(context);
      if (reason == null) return;
    }
    try {
      if (reason != null) {
        await repo.requestCancel(sos.clientId, reason);
      } else {
        await repo.withdrawCancel(sos.clientId);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            reason != null ? l10n.cancelAskedSnack : l10n.cancelWithdrawnSnack,
          ),
        ),
      );
    } on ActionRejected catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.reason == ActionRejection.offline
                ? l10n.cancelOffline
                : l10n.cancelFailed,
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.cancelFailed)));
    }
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
          Text(
            sos.cancelled ? l10n.cancelledBody : l10n.resolvedBody,
            style: text.bodyLarge,
          ),
        ],
        if (sos.cancelRequested && !resolved) ...[
          const SizedBox(height: SagipSpace.lg),
          _CancelAsked(
            sos: sos,
            onWithdraw: () => _cancel(context, ref, ask: false),
          ),
        ],
        if (showEta) ...[
          const SizedBox(height: SagipSpace.xl),
          _EtaCard(sos: sos),
        ],
        if (sos.unitCallSign != null && !resolved) ...[
          const SizedBox(height: SagipSpace.md),
          // Secondary: Call MDRRMD stays the one filled button here.
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.track(sos.clientId)),
            icon: const Icon(Symbols.map_rounded),
            label: Text(l10n.trackResponder),
          ),
        ],
        // Right under Track responder, so it is seen (Joshua, 2026-10-19).
        if (!resolved) ...[
          const SizedBox(height: SagipSpace.xl),
          _SafePlacesCard(sos: sos),
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
        if (!resolved) ...[
          const SizedBox(height: SagipSpace.md),
          _PhotoSection(sos: sos),
        ],
        const SizedBox(height: SagipSpace.xl),
        _LocationCard(sos: sos),
        if (!resolved) ...[
          const SizedBox(height: SagipSpace.xl),
          Text(l10n.guidanceTitle, style: text.titleMedium),
          const SizedBox(height: SagipSpace.sm),
          Text(l10n.guidanceBody, style: text.bodyMedium),
        ],
        // Last and quiet: cancelling is rare and must not be hit by mistake.
        if (sos.canAskToCancel) ...[
          const SizedBox(height: SagipSpace.xl),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _cancel(context, ref, ask: true),
              icon: const Icon(Symbols.cancel_rounded),
              label: Text(l10n.cancelSos),
            ),
          ),
        ],
      ],
    );
  }
}

/// The resident asked to cancel: say plainly that the SOS is still open,
/// and offer the way back.
class _CancelAsked extends StatelessWidget {
  const _CancelAsked({required this.sos, required this.onWithdraw});

  final SosRequest sos;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return DecoratedBox(
      key: const ValueKey('cancel-asked'),
      decoration: BoxDecoration(
        color: p.warning.tint,
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.cancel_rounded, color: p.warning.text),
                const SizedBox(width: SagipSpace.md),
                Expanded(
                  child: Text(l10n.cancelAskedTitle, style: text.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: SagipSpace.sm),
            Text(
              l10n.cancelAskedBody(
                l10n.cancelReason(sos.cancelReason ?? SosCancelReason.other),
              ),
              style: text.bodyMedium,
            ),
            const SizedBox(height: SagipSpace.sm),
            OutlinedButton(
              onPressed: onWithdraw,
              child: Text(l10n.cancelWithdraw),
            ),
          ],
        ),
      ),
    );
  }
}

class _EtaCard extends StatelessWidget {
  const _EtaCard({required this.sos});

  final SosRequest sos;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EtaHero(
      label: l10n.etaTitle,
      value: l10n.etaMinutes(sos.etaMinutes!),
      caption: sos.unitCallSign != null && sos.unitType != null
          ? l10n.unitLine(sos.unitCallSign!, l10n.unitType(sos.unitType!))
          : null,
      tone: SagipPalette.of(context).info,
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
          TimelineStep(
            label: steps[i].$1,
            time: steps[i].$2 == null ? null : formatTime(steps[i].$2!, locale),
            state: steps[i].$2 != null
                ? TimelineState.done
                : (i == current ? TimelineState.current : TimelineState.later),
            last: i == steps.length - 1,
          ),
      ],
    );
  }
}

/// An optional photo (2026-10-19): only after the SOS is sent, and sent
/// after it, so the SOS never waits for a picture.
class _PhotoSection extends ConsumerWidget {
  const _PhotoSection({required this.sos});

  final SosRequest sos;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final photo = await pickPhoto(context, ref);
    if (photo == null) return;
    try {
      await ref.read(sosRepositoryProvider).addPhoto(sos.clientId, photo);
      messenger.showSnackBar(SnackBar(content: Text(l10n.photoSaved)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.photoFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final count = ref.watch(sosPhotoCountProvider(sos.clientId)).value ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (count < photosPerRecord)
          OutlinedButton.icon(
            key: const ValueKey('sos-add-photo'),
            onPressed: () => _add(context, ref),
            icon: const Icon(Symbols.add_a_photo_rounded),
            label: Text(l10n.photoAdd),
          ),
        const SizedBox(height: SagipSpace.xs),
        Text(
          count == 0
              ? l10n.photoSosHint
              : l10n.photoSosCount(count, photosPerRecord),
          style: text.bodySmall!.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }
}

/// Safe places near the resident (2026-10-19). Help comes to where they
/// are, so this is for when staying is unsafe; the type they tapped picks
/// the kind of place.
class _SafePlacesCard extends ConsumerWidget {
  const _SafePlacesCard({required this.sos});

  final SosRequest sos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final type = sos.details.type;
    final at = sos.location;
    final nearest = type == null || at == null
        ? null
        : ref
              .watch(safePlacesNearProvider(safePlaceQuery(at, type)))
              .value
              ?.firstOrNull;
    return DecoratedBox(
      key: const ValueKey('sos-safe-places'),
      decoration: BoxDecoration(
        border: Border.all(color: p.hairline),
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.night_shelter_rounded, color: p.success.text),
                const SizedBox(width: SagipSpace.md),
                Expanded(
                  child: Text(l10n.sosSafePlacesTitle, style: text.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: SagipSpace.sm),
            Text(l10n.safePlacesFromSos, style: text.bodyMedium),
            if (nearest != null) ...[
              const SizedBox(height: SagipSpace.sm),
              Text(
                l10n.sosSafePlacesNearest(
                  l10n.safePlaceName(nearest.place),
                  formatDistance(nearest.meters),
                ),
                style: text.bodyMedium!.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            const SizedBox(height: SagipSpace.md),
            OutlinedButton.icon(
              onPressed: () => context.push(
                Routes.safePlaces(need: type, from: at, fromSos: true),
              ),
              icon: const Icon(Symbols.directions_walk_rounded),
              label: Text(l10n.sosSafePlacesButton),
            ),
          ],
        ),
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
                  if (sos.isDelivered && sos.isActive) ...[
                    const SizedBox(height: SagipSpace.xs),
                    Text(
                      l10n.locationShared,
                      style: text.bodySmall!.copyWith(color: p.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
