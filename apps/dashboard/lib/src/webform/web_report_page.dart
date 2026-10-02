import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../common/labels.dart';
import '../l10n/app_localizations.dart';
import 'browser/browser.dart';
import 'report_draft.dart';
import 'web_barangay_dialog.dart';
import 'web_frame.dart';
import 'web_providers.dart';
import 'web_router.dart';

/// W2 Submit crowd report (FR15). The location comes from the browser, a
/// pin on the map, or a barangay; nothing is sent until the resident has
/// chosen one. The draft is kept in the browser, so a lost connection or a
/// reload does not lose it. A single report is never an incident on its
/// own: DBSCAN needs a cluster (FR7).
class WebReportPage extends ConsumerStatefulWidget {
  const WebReportPage({super.key});

  @override
  ConsumerState<WebReportPage> createState() => _WebReportPageState();
}

class _WebReportPageState extends ConsumerState<WebReportPage> {
  final _description = TextEditingController();
  final _map = MapController();
  var _mapReady = false;
  var _sending = false;
  var _locating = false;

  /// Why the last Send was refused.
  ReportRejection? _error;
  var _needLocation = false;
  var _lostConnection = false;
  var _failed = false;
  BrowserLocationFailure? _locationFailure;

  @override
  void initState() {
    super.initState();
    _description.text = ref.read(reportDraftProvider).description;
  }

  @override
  void dispose() {
    _description.dispose();
    _map.dispose();
    super.dispose();
  }

  ReportDraftController get _draft => ref.read(reportDraftProvider.notifier);

  void _placed() => setState(() {
    _needLocation = false;
    _locationFailure = null;
    if (_error == ReportRejection.outsideManila ||
        _error == ReportRejection.noLocation) {
      _error = null;
    }
  });

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _locationFailure = null;
    });
    try {
      final fix = await ref.read(browserLocationProvider).current();
      if (!mounted) return;
      _draft.setLocation(
        fix.point,
        DraftPlace.browser,
        accuracyMeters: fix.accuracyMeters,
      );
      if (_mapReady) _map.move(toLatLng(fix.point), 17);
      _placed();
    } on BrowserLocationException catch (e) {
      if (mounted) setState(() => _locationFailure = e.reason);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _chooseBarangay() async {
    final picked = await showWebBarangayDialog(context, needsCenter: true);
    final center = picked?.center;
    if (picked == null || center == null || !mounted) return;
    _draft.setLocation(center, DraftPlace.barangay, barangay: picked);
    if (_mapReady) _map.move(toLatLng(center), 16);
    _placed();
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final draft = ref.read(reportDraftProvider);
    final location = draft.location;
    setState(() {
      _error = null;
      _lostConnection = false;
      _failed = false;
      _needLocation = location == null;
    });
    if (draft.description.trim().isEmpty) {
      setState(() => _error = ReportRejection.emptyDescription);
      return;
    }
    if (location == null) return;
    if (!roughlyInsideManila(location)) {
      setState(() => _error = ReportRejection.outsideManila);
      return;
    }

    setState(() => _sending = true);
    try {
      final at = _draft.markSending(DateTime.now());
      final report = await ref
          .read(webReportsProvider)
          .submit(
            clientId: draft.clientId,
            capturedAt: at,
            description: draft.description,
            location: location,
            type: draft.type,
            accuracyMeters: draft.accuracyMeters,
            barangay: draft.barangay,
          );
      if (!mounted) return;
      _draft.clear();
      context.go(WebRoutes.received(report.serverId ?? report.clientId));
    } on ReportRejected catch (e) {
      _draft.forgetSending();
      if (mounted) setState(() => _error = e.reason);
    } on ActionRejected catch (e) {
      if (e.reason == ActionRejection.offline) {
        // The draft and its time are kept; the same report goes out again.
        if (mounted) setState(() => _lostConnection = true);
      } else {
        _draft.forgetSending();
        if (mounted) setState(() => _failed = true);
      }
    } on Object {
      _draft.forgetSending();
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final draft = ref.watch(reportDraftProvider);
    final user = ref.watch(webUserProvider).value;
    final online = ref.watch(webIsOnlineProvider);
    final quota = ref.watch(reportQuotaProvider).value;
    final blocked = quota != null && (quota.suspended || quota.remaining == 0);
    // The quota line already says so when the limit or a suspension is
    // known; these cover a refusal the page did not see coming.
    final problem = switch (_error) {
      ReportRejection.outsideManila => l10n.webOutsideManila,
      ReportRejection.rateLimited => blocked ? null : l10n.webRateLimited,
      ReportRejection.accountSuspended => blocked ? null : l10n.webSuspended,
      ReportRejection.noLocation => l10n.webNeedLocation,
      ReportRejection.emptyDescription || null => null,
    };

    return WebFrame(
      trailing: [
        TextButton(
          onPressed: () => context.go(WebRoutes.reports),
          child: Text(l10n.webMyReports),
        ),
        TextButton(onPressed: () => webSignOut(ref), child: Text(l10n.signOut)),
      ],
      children: [
        Text(l10n.webReportTitle, style: text.headlineSmall),
        const SizedBox(height: SagipSpace.sm),
        Text(
          l10n.webReportBody,
          style: text.bodyMedium!.copyWith(color: p.textSecondary),
        ),
        if (user != null) ...[
          const SizedBox(height: SagipSpace.xs),
          Text(
            l10n.webSignedInAs(user.displayName),
            style: text.bodySmall!.copyWith(color: p.textSecondary),
          ),
        ],
        const SizedBox(height: SagipSpace.xxl),
        TextField(
          key: const ValueKey('web-description'),
          controller: _description,
          minLines: 3,
          maxLines: 6,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.webDescription,
            hintText: l10n.webDescriptionHint,
            alignLabelWithHint: true,
            errorText: _error == ReportRejection.emptyDescription
                ? l10n.webDescriptionEmpty
                : null,
          ),
          onChanged: (v) {
            _draft.setDescription(v);
            if (_error == ReportRejection.emptyDescription) {
              setState(() => _error = null);
            }
          },
        ),
        const SizedBox(height: SagipSpace.lg),
        Text(l10n.webType, style: text.titleSmall),
        const SizedBox(height: SagipSpace.sm),
        Wrap(
          spacing: SagipSpace.sm,
          runSpacing: SagipSpace.sm,
          children: [
            for (final t in IncidentType.values)
              ChoiceChip(
                label: Text(l10n.incidentType(t)),
                selected: draft.type == t,
                onSelected: (on) => _draft.setType(on ? t : null),
              ),
          ],
        ),
        const SizedBox(height: SagipSpace.xxl),
        Text(l10n.webLocationTitle, style: text.titleSmall),
        const SizedBox(height: SagipSpace.sm),
        Wrap(
          spacing: SagipSpace.sm,
          runSpacing: SagipSpace.sm,
          children: [
            OutlinedButton.icon(
              onPressed: _locating ? null : _useMyLocation,
              icon: const Icon(Symbols.my_location_rounded),
              label: Text(_locating ? l10n.webLocating : l10n.webUseMyLocation),
            ),
            OutlinedButton.icon(
              onPressed: _chooseBarangay,
              icon: const Icon(Symbols.location_city_rounded),
              label: Text(l10n.webChooseBarangayButton),
            ),
          ],
        ),
        const SizedBox(height: SagipSpace.sm),
        Text(
          l10n.webMapHint,
          style: text.bodySmall!.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: SagipSpace.md),
        _PinMap(
          controller: _map,
          initial: draft.location,
          chosen: draft.location != null,
          onReady: () => _mapReady = true,
          onMoved: (point) {
            _draft.setLocation(point, DraftPlace.pin);
            _placed();
          },
        ),
        const SizedBox(height: SagipSpace.md),
        _PlaceLines(draft: draft),
        if (_locationFailure != null) ...[
          const SizedBox(height: SagipSpace.md),
          WebMessage(
            text: _locationFailure == BrowserLocationFailure.denied
                ? l10n.webLocationDenied
                : l10n.webLocationUnavailable,
            tone: p.warning,
          ),
        ],
        if (_needLocation) ...[
          const SizedBox(height: SagipSpace.md),
          WebMessage(text: l10n.webNeedLocation, tone: p.critical),
        ],
        const SizedBox(height: SagipSpace.xxl),
        _QuotaLine(noneLeft: quota == null ? null : _noneLeft(l10n, quota)),
        if (problem != null) ...[
          const SizedBox(height: SagipSpace.md),
          WebMessage(text: problem, tone: p.critical),
        ],
        if (_failed) ...[
          const SizedBox(height: SagipSpace.md),
          WebMessage(text: l10n.errorGeneric, tone: p.critical),
        ],
        if (!online || _lostConnection) ...[
          const SizedBox(height: SagipSpace.md),
          WebMessage(
            text: l10n.webConnectionLost,
            tone: p.warning,
            icon: Symbols.cloud_off_rounded,
          ),
        ],
        const SizedBox(height: SagipSpace.lg),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _sending || !online || blocked ? null : _send,
            icon: const Icon(Symbols.send_rounded),
            label: Text(_sending ? l10n.webSending : l10n.webSend),
          ),
        ),
        const SizedBox(height: SagipSpace.x3),
        const SosNotice(),
      ],
    );
  }

  String _noneLeft(AppLocalizations l10n, ReportQuota quota) {
    final at = quota.resetsAt;
    return at == null
        ? l10n.webQuotaNoneLater(quota.limit)
        : l10n.webQuotaNone(quota.limit, formatTime(at, l10n.localeName));
  }
}

/// "4 of 5 reports left this hour", the rate-limit message, or the
/// suspension notice (plan 7.2 W2).
class _QuotaLine extends ConsumerWidget {
  const _QuotaLine({required this.noneLeft});

  final String? noneLeft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final quota = ref.watch(reportQuotaProvider);
    final q = quota.value;
    if (q == null) {
      // Loading. On an error the line is left out: the server still checks.
      return quota.hasError
          ? const SizedBox.shrink()
          : const Align(
              alignment: Alignment.centerLeft,
              child: SkeletonBox(width: 200, height: 16),
            );
    }
    if (q.suspended) {
      return WebMessage(text: l10n.webSuspended, tone: p.warning);
    }
    if (q.remaining == 0) {
      return WebMessage(
        text: noneLeft ?? l10n.webQuotaNoneLater(q.limit),
        tone: p.warning,
        icon: Symbols.hourglass_top_rounded,
      );
    }
    return Text(
      l10n.webQuotaLeft(q.remaining, q.limit),
      style: text.bodyMedium!.copyWith(
        color: p.textSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Where the report is, in words: the barangay, the coordinates, and how
/// the location was chosen.
class _PlaceLines extends StatelessWidget {
  const _PlaceLines({required this.draft});

  final ReportDraft draft;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final point = draft.location;
    final muted = text.bodySmall!.copyWith(color: p.textSecondary);
    if (point == null) {
      return Text(
        l10n.webLocationNone,
        style: text.bodyMedium!.copyWith(color: p.textSecondary),
      );
    }
    final b = draft.barangay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (b != null)
          Text(
            draft.place == DraftPlace.barangay
                ? l10n.webPlace(b.name, b.district)
                : l10n.webNear(l10n.webPlace(b.name, b.district)),
            style: text.titleSmall,
          ),
        Text(
          formatCoordinates(point),
          style: muted.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(switch (draft.place) {
          DraftPlace.browser => l10n.webLocationBrowser(
            (draft.accuracyMeters ?? 0).round(),
          ),
          DraftPlace.barangay => l10n.webLocationBarangay,
          DraftPlace.pin || null => l10n.webLocationPin,
        }, style: muted),
      ],
    );
  }
}

/// A map that moves under a fixed pin. The pin is grey until the resident
/// has chosen a location, so the starting view is never sent by mistake.
class _PinMap extends ConsumerWidget {
  const _PinMap({
    required this.controller,
    required this.initial,
    required this.chosen,
    required this.onReady,
    required this.onMoved,
  });

  final MapController controller;
  final GeoPoint? initial;
  final bool chosen;
  final VoidCallback onReady;
  final ValueChanged<GeoPoint> onMoved;

  void _zoom(double by) {
    final camera = controller.camera;
    controller.move(camera.center, (camera.zoom + by).clamp(11, 19));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final tiles = ref.watch(webMapTilesProvider);
    final start = initial;
    return SizedBox(
      height: 280,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SagipRadius.card),
        child: DecoratedBox(
          decoration: BoxDecoration(color: p.panelRaised),
          child: Stack(
            children: [
              FlutterMap(
                key: const ValueKey('web-map'),
                mapController: controller,
                options: MapOptions(
                  initialCenter: start == null ? manilaCenter : toLatLng(start),
                  initialZoom: start == null ? 13 : 16,
                  minZoom: 11,
                  maxZoom: 19,
                  onMapReady: onReady,
                  // Moves by code set the location themselves.
                  onPositionChanged: (camera, hasGesture) {
                    if (!hasGesture) return;
                    final c = camera.center;
                    onMoved(GeoPoint(c.latitude, c.longitude));
                  },
                  // The page scrolls, so the wheel does not zoom the map;
                  // the buttons do.
                  interactionOptions: const InteractionOptions(
                    flags:
                        InteractiveFlag.drag |
                        InteractiveFlag.pinchZoom |
                        InteractiveFlag.doubleTapZoom |
                        InteractiveFlag.flingAnimation,
                  ),
                ),
                children: [
                  SagipTiles(
                    userAgentPackageName: 'ph.sagip.webform',
                    enabled: tiles,
                  ),
                  MapCredit(label: l10n.mapAttribution),
                ],
              ),
              // The pin stays in the middle; its tip marks the spot.
              IgnorePointer(
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(0, -18),
                    child: Semantics(
                      label: l10n.webPinLabel,
                      child: Icon(
                        Symbols.location_on_rounded,
                        size: 48,
                        fill: 1,
                        color: chosen ? p.info.fill : p.textSecondary,
                        shadows: const [
                          Shadow(color: Color(0x33000000), blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: SagipSpace.md,
                top: SagipSpace.md,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.panel,
                    borderRadius: BorderRadius.circular(SagipRadius.card),
                    border: Border.all(color: p.hairline),
                    boxShadow: const [
                      BoxShadow(color: Color(0x1F000000), blurRadius: 24),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l10n.zoomIn,
                        onPressed: () => _zoom(1),
                        icon: const Icon(Symbols.add_rounded),
                      ),
                      IconButton(
                        tooltip: l10n.zoomOut,
                        onPressed: () => _zoom(-1),
                        icon: const Icon(Symbols.remove_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
