import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../common/photo_picker.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';
import '../queue/queue_sheet.dart';

/// R4 Report a hazard. One report is never an emergency on its own: MDRRMD
/// acts when several nearby reports form a cluster (FR7, FR15). The report
/// is saved on the phone first and sent over the internet.
class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key});

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  final _description = TextEditingController();
  IncidentType? _type;
  ReportRejection? _error;
  var _saving = false;

  /// A spot the resident chose on R5 instead of the GPS fix.
  LocationFix? _picked;

  /// The report just sent; shows the confirmation instead of the form.
  String? _sentId;

  /// An optional photo (2026-10-19), sent after the report.
  Uint8List? _photo;

  Future<void> _addPhoto() async {
    final picked = await pickPhoto(context, ref);
    if (picked != null && mounted) setState(() => _photo = picked);
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fix = _picked ?? ref.read(locationProvider).value?.lastFix;
      final report = await ref
          .read(hazardReportRepositoryProvider)
          .submit(description: _description.text, type: _type, fix: fix);
      final photo = _photo;
      if (photo != null) {
        await ref
            .read(hazardReportRepositoryProvider)
            .addPhoto(report.clientId, photo);
      }
      if (!mounted) return;
      setState(() => _sentId = report.clientId);
    } on ReportRejected catch (e) {
      if (mounted) setState(() => _error = e.reason);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _change() async {
    final gps = ref.read(locationProvider).value?.lastFix;
    final picked = await context.push<LocationFix>(
      Routes.pickLocation,
      extra: (_picked ?? gps)?.point,
    );
    if (picked == null || !mounted) return;
    // Choosing the GPS fix goes back to following GPS.
    setState(() => _picked = picked.manual ? picked : null);
  }

  void _reset() => setState(() {
    _sentId = null;
    _picked = null;
    _type = null;
    _error = null;
    _photo = null;
    _description.clear();
  });

  @override
  Widget build(BuildContext context) {
    final sentId = _sentId;
    return ListView(
      padding: const EdgeInsets.all(SagipSpace.xl),
      children: [
        if (sentId != null)
          _Sent(clientId: sentId, onAnother: _reset)
        else
          _form(context),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final location = ref.watch(locationProvider).value;
    final fix = _picked ?? location?.lastFix;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.reportTitle, style: text.headlineSmall),
        const SizedBox(height: SagipSpace.sm),
        Text(
          l10n.reportExpectation,
          style: text.bodyMedium!.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: SagipSpace.xl),
        TextField(
          // Tapping outside closes the keyboard.
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          controller: _description,
          minLines: 3,
          maxLines: 6,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.reportDescription,
            hintText: l10n.reportDescriptionHint,
            alignLabelWithHint: true,
            errorText: _error == ReportRejection.emptyDescription
                ? l10n.reportEmpty
                : null,
          ),
          onChanged: (_) {
            if (_error == ReportRejection.emptyDescription) {
              setState(() => _error = null);
            }
          },
        ),
        const SizedBox(height: SagipSpace.lg),
        Text(l10n.reportType, style: text.titleSmall),
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
        const SizedBox(height: SagipSpace.lg),
        _PhotoRow(
          photo: _photo,
          onAdd: _addPhoto,
          onRemove: () => setState(() => _photo = null),
        ),
        const SizedBox(height: SagipSpace.xl),
        _LocationRow(
          status: location,
          picked: _picked,
          onChange: _change,
          onUseGps: () => setState(() => _picked = null),
        ),
        if (_error != null && _error != ReportRejection.emptyDescription) ...[
          const SizedBox(height: SagipSpace.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Symbols.error_rounded, color: p.critical.text),
              const SizedBox(width: SagipSpace.sm),
              Expanded(
                child: Text(
                  l10n.reportRejection(_error!),
                  style: text.bodyMedium!.copyWith(color: p.critical.text),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: SagipSpace.xl),
        FilledButton.icon(
          onPressed: _saving || fix == null ? null : _send,
          icon: const Icon(Symbols.send_rounded),
          label: Text(_saving ? l10n.reportSaving : l10n.reportSend),
        ),
        const SizedBox(height: SagipSpace.lg),
        Text(
          l10n.reportSosHint,
          textAlign: TextAlign.center,
          style: text.bodySmall!.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }
}

/// The report's optional photo: a button, or the photo with a way to
/// remove it.
class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.photo,
    required this.onAdd,
    required this.onRemove,
  });

  final Uint8List? photo;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final shot = photo;
    if (shot == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('report-add-photo'),
          onPressed: onAdd,
          icon: const Icon(Symbols.add_a_photo_rounded),
          label: Text(l10n.photoAddOptional),
        ),
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(SagipRadius.control),
          child: Semantics(
            image: true,
            label: l10n.photoThumb,
            child: Image.memory(shot, width: 64, height: 64, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: SagipSpace.md),
        Expanded(
          child: Text(
            l10n.photoReportAdded,
            style: text.bodyMedium!.copyWith(color: p.textSecondary),
          ),
        ),
        IconButton(
          key: const ValueKey('report-remove-photo'),
          tooltip: l10n.photoRemove,
          onPressed: onRemove,
          icon: const Icon(Symbols.close_rounded),
        ),
      ],
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.status,
    required this.picked,
    required this.onChange,
    required this.onUseGps,
  });

  final LocationStatus? status;

  /// Set when the resident chose the spot on R5.
  final LocationFix? picked;
  final VoidCallback onChange;
  final VoidCallback onUseGps;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final gps = status?.lastFix;
    final fix = picked ?? gps;
    final numbers = text.bodySmall!.copyWith(
      color: p.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Symbols.location_on_rounded, color: p.textSecondary),
        const SizedBox(width: SagipSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.reportLocation, style: text.titleSmall),
              const SizedBox(height: SagipSpace.xs),
              if (fix == null)
                Text(l10n.reportLocationFinding, style: text.bodyMedium)
              else ...[
                if (fix.barangay != null && fix.district != null)
                  Text(
                    l10n.place(fix.barangay!, fix.district!),
                    style: text.bodyMedium,
                  ),
                if (fix.manual) ...[
                  Text(formatCoordinates(fix.point), style: numbers),
                  Text(
                    l10n.reportLocationChosen,
                    style: text.bodySmall!.copyWith(color: p.info.text),
                  ),
                ] else ...[
                  Text(
                    l10n.locationAccuracy(
                      formatCoordinates(fix.point),
                      fix.accuracyMeters.round(),
                    ),
                    style: numbers,
                  ),
                  if (status?.gpsOn == false)
                    Text(
                      l10n.reportLocationLast,
                      style: text.bodySmall!.copyWith(color: p.warning.text),
                    ),
                ],
              ],
              if (picked != null && gps != null)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: onUseGps,
                  child: Text(l10n.reportUseGpsAgain),
                ),
            ],
          ),
        ),
        TextButton(onPressed: onChange, child: Text(l10n.reportChangeLocation)),
      ],
    );
  }
}

/// Confirmation after sending: delivered, or saved on the phone until the
/// phone is back online.
class _Sent extends ConsumerWidget {
  const _Sent({required this.clientId, required this.onAnother});

  final String clientId;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    HazardReport? report;
    for (final r in ref.watch(myReportsProvider).value ?? const []) {
      if (r.clientId == clientId) report = r;
    }
    final state = report?.delivery ?? DeliveryState.savedOnPhone;
    final waiting = state == DeliveryState.savedOnPhone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: SagipSpace.x4),
        Icon(
          waiting ? Symbols.smartphone_rounded : Symbols.check_circle_rounded,
          size: 48,
          color: waiting ? p.warning.text : p.success.text,
          fill: 1,
        ),
        const SizedBox(height: SagipSpace.lg),
        Text(
          waiting ? l10n.reportSavedTitle : l10n.reportSentTitle,
          textAlign: TextAlign.center,
          style: text.headlineSmall,
        ),
        const SizedBox(height: SagipSpace.sm),
        Center(
          child: DeliveryBadge(state: state, label: l10n.delivery(state)),
        ),
        const SizedBox(height: SagipSpace.lg),
        Text(
          waiting ? l10n.reportSavedBody : l10n.reportSentBody,
          textAlign: TextAlign.center,
          style: text.bodyMedium!.copyWith(color: p.textSecondary),
        ),
        if (waiting) ...[
          const SizedBox(height: SagipSpace.sm),
          Center(
            child: TextButton(
              onPressed: () => showQueueSheet(context),
              child: Text(l10n.reportSeeQueue),
            ),
          ),
        ],
        const SizedBox(height: SagipSpace.x3),
        OutlinedButton(onPressed: onAnother, child: Text(l10n.reportAnother)),
      ],
    );
  }
}
