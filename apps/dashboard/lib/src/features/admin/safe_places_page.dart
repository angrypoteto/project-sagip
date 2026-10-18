import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/actions.dart';
import '../../common/async_body.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common_page.dart';

/// Safe places (admin, Joshua 2026-10-19): the places residents are
/// pointed to in an emergency. 763 come from OpenStreetMap; an admin hides
/// a wrong one and adds MDRRMD's own evacuation centers. No capacity or
/// occupancy: evacuation center management is out of scope.
class SafePlacesPage extends ConsumerStatefulWidget {
  const SafePlacesPage({super.key});

  /// Rows drawn at once; search or a kind narrows the rest.
  static const maxRows = 100;

  @override
  ConsumerState<SafePlacesPage> createState() => _SafePlacesPageState();
}

class _SafePlacesPageState extends ConsumerState<SafePlacesPage> {
  final _search = TextEditingController();
  SafePlaceKind? _kind;
  bool _showHidden = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SafePlace> _filter(List<SafePlace> all, AppLocalizations l10n) {
    final q = _search.text.trim().toLowerCase();
    final out = [
      for (final p in all)
        if ((_showHidden || !p.hidden) &&
            (_kind == null || p.kind == _kind) &&
            (q.isEmpty ||
                l10n.safePlaceName(p).toLowerCase().contains(q) ||
                (p.barangay ?? '').toLowerCase().contains(q) ||
                (p.district ?? '').toLowerCase().contains(q)))
          p,
    ];
    // MDRRMD's own first, then by district, barangay, and name.
    out.sort((a, b) {
      final byOfficial = (b.official ? 1 : 0).compareTo(a.official ? 1 : 0);
      if (byOfficial != 0) return byOfficial;
      final byDistrict = (a.district ?? '').compareTo(b.district ?? '');
      if (byDistrict != 0) return byDistrict;
      final byBarangay = compareBarangays(a.barangay, b.barangay);
      if (byBarangay != 0) return byBarangay;
      return l10n.safePlaceName(a).compareTo(l10n.safePlaceName(b));
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final online = ref.watch(isOnlineProvider);
    return PageFrame(
      title: l10n.navSafePlaces,
      subtitle: l10n.safePlacesSubtitle,
      headerTrailing: FilledButton.icon(
        key: const ValueKey('add-safe-place'),
        onPressed: online ? () => showSafePlaceDialog(context, ref) : null,
        icon: const Icon(Symbols.add_rounded),
        label: Text(l10n.safePlaceAdd),
      ),
      child: AsyncBody(
        value: ref.watch(safePlacesProvider),
        isEmpty: (all) => all.isEmpty,
        empty: EmptyState(
          icon: Symbols.night_shelter_rounded,
          title: l10n.safePlacesEmpty,
        ),
        builder: (all) {
          final shown = _filter(all, l10n);
          final rows = shown.take(SafePlacesPage.maxRows).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!online) ...[
                Text(l10n.offlineActionsDisabled, style: text.bodySmall),
                const SizedBox(height: SagipSpace.md),
              ],
              Wrap(
                spacing: SagipSpace.lg,
                runSpacing: SagipSpace.md,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      key: const ValueKey('safe-place-search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Symbols.search_rounded),
                        hintText: l10n.safePlacesSearch,
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<SafePlaceKind?>(
                      key: const ValueKey('safe-place-kind-filter'),
                      initialValue: _kind,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(l10n.safePlacesAllKinds),
                        ),
                        for (final k in SafePlaceKind.values)
                          DropdownMenuItem(
                            value: k,
                            child: Text(l10n.safePlaceKind(k)),
                          ),
                      ],
                      onChanged: (k) => setState(() => _kind = k),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        key: const ValueKey('safe-place-show-hidden'),
                        value: _showHidden,
                        onChanged: (v) => setState(() => _showHidden = v),
                      ),
                      const SizedBox(width: SagipSpace.sm),
                      Text(l10n.safePlacesShowHidden, style: text.labelMedium),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: SagipSpace.md),
              Text(
                shown.length > rows.length
                    ? l10n.safePlacesFirst(rows.length)
                    : l10n.safePlacesCount(shown.length, all.length),
                style: text.bodySmall,
              ),
              const SizedBox(height: SagipSpace.sm),
              if (rows.isEmpty)
                EmptyState(
                  icon: Symbols.search_off_rounded,
                  title: l10n.safePlacesNone,
                )
              else
                _PlacesTable(places: rows, online: online),
            ],
          );
        },
      ),
    );
  }
}

/// Orders "Barangay 9" before "Barangay 10".
int compareBarangays(String? a, String? b) {
  int? number(String? s) =>
      int.tryParse(RegExp(r'\d+').firstMatch(s ?? '')?.group(0) ?? '');
  final na = number(a), nb = number(b);
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  return (a ?? '').compareTo(b ?? '');
}

class _PlacesTable extends ConsumerWidget {
  const _PlacesTable({required this.places, required this.online});

  final List<SafePlace> places;
  final bool online;

  Future<void> _setHidden(
    BuildContext context,
    WidgetRef ref,
    SafePlace place,
  ) {
    final l10n = AppLocalizations.of(context);
    return runAction(
      context,
      () => ref
          .read(safePlaceRepositoryProvider)
          .setHidden(place.id, !place.hidden),
      success: place.hidden
          ? l10n.safePlaceShownSnack
          : l10n.safePlaceHiddenSnack,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return TableCard(
      table: DataTable(
        columnSpacing: SagipSpace.xl,
        columns: [
          DataColumn(label: Text(l10n.colPlace)),
          DataColumn(label: Text(l10n.colKind)),
          DataColumn(label: Text(l10n.colBarangay)),
          DataColumn(label: Text(l10n.colSource)),
          const DataColumn(label: SizedBox.shrink()),
        ],
        rows: [
          for (final place in places)
            DataRow(
              key: ValueKey('safe-place-${place.id}'),
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          l10n.safePlaceName(place),
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium!.copyWith(
                            color: place.hidden ? p.textSecondary : null,
                          ),
                        ),
                      ),
                      if (place.official) ...[
                        const SizedBox(width: SagipSpace.sm),
                        SagipChip(
                          label: l10n.safePlaceOfficialChip,
                          tone: p.success,
                          icon: Symbols.verified_rounded,
                        ),
                      ],
                      if (place.hidden) ...[
                        const SizedBox(width: SagipSpace.sm),
                        SagipChip(
                          label: l10n.safePlaceHiddenChip,
                          tone: p.neutral,
                          icon: Symbols.visibility_off_rounded,
                        ),
                      ],
                    ],
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        safePlaceIcon(place.kind),
                        size: 18,
                        color: p.textSecondary,
                      ),
                      const SizedBox(width: SagipSpace.sm),
                      Text(l10n.safePlaceKind(place.kind)),
                    ],
                  ),
                ),
                DataCell(
                  Text(
                    place.barangay == null
                        ? '–'
                        : place.district == null
                        ? place.barangay!
                        : l10n.safePlaceWhere(place.barangay!, place.district!),
                  ),
                ),
                DataCell(
                  Text(
                    place.fromMap
                        ? l10n.safePlaceFromMap
                        : l10n.safePlaceAddedHere,
                    style: text.bodySmall,
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('edit-${place.id}'),
                        tooltip: l10n.edit,
                        onPressed: online
                            ? () => showSafePlaceDialog(
                                context,
                                ref,
                                place: place,
                              )
                            : null,
                        icon: const Icon(Symbols.edit_rounded),
                      ),
                      IconButton(
                        key: ValueKey('hide-${place.id}'),
                        tooltip: place.hidden
                            ? l10n.safePlaceShow
                            : l10n.safePlaceHide,
                        onPressed: online
                            ? () => _setHidden(context, ref, place)
                            : null,
                        icon: Icon(
                          place.hidden
                              ? Symbols.visibility_rounded
                              : Symbols.visibility_off_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Adds a safe place, or edits [place].
Future<void> showSafePlaceDialog(
  BuildContext context,
  WidgetRef ref, {
  SafePlace? place,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SafePlaceDialog(ref: ref, place: place),
);

class _SafePlaceDialog extends StatefulWidget {
  const _SafePlaceDialog({required this.ref, this.place});

  final WidgetRef ref;
  final SafePlace? place;

  @override
  State<_SafePlaceDialog> createState() => _SafePlaceDialogState();
}

class _SafePlaceDialogState extends State<_SafePlaceDialog> {
  late final _name = TextEditingController(text: widget.place?.name ?? '');
  late final _position = TextEditingController(
    text: widget.place == null
        ? ''
        : '${widget.place!.location.lat.toStringAsFixed(5)}, '
              '${widget.place!.location.lng.toStringAsFixed(5)}',
  );
  late SafePlaceKind _kind =
      widget.place?.kind ?? SafePlaceKind.evacuationCenter;
  late bool _official = widget.place?.official ?? true;
  bool _tried = false;
  bool _busy = false;
  bool _outside = false;

  @override
  void dispose() {
    _name.dispose();
    _position.dispose();
    super.dispose();
  }

  /// "14.6002, 120.9902": a position in or near Manila.
  GeoPoint? get _point {
    final parts = _position.text.trim().split(RegExp(r'[,\s]+'));
    final lat = parts.length == 2 ? double.tryParse(parts[0]) : null;
    final lng = parts.length == 2 ? double.tryParse(parts[1]) : null;
    final ok =
        lat != null &&
        lng != null &&
        lat >= 14.50 &&
        lat <= 14.70 &&
        lng >= 120.90 &&
        lng <= 121.07;
    return ok ? GeoPoint(lat, lng) : null;
  }

  String? _nameError(AppLocalizations l10n) {
    final n = _name.text.trim();
    if (n.length > 120) return l10n.fieldPlaceNameError;
    if (_kind == SafePlaceKind.evacuationCenter && n.isEmpty) {
      return l10n.fieldPlaceNameError;
    }
    return null;
  }

  String? _positionError(AppLocalizations l10n) {
    if (_outside) return l10n.safePlaceOutside;
    return _point == null ? l10n.fieldPlacePositionError : null;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _tried = true;
      _outside = false;
    });
    final point = _point;
    if (_nameError(l10n) != null || point == null) return;
    setState(() => _busy = true);
    final name = _name.text.trim();
    final repo = widget.ref.read(safePlaceRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      await repo.savePlace(
        id: widget.place?.id,
        name: name.isEmpty ? null : name,
        kind: _kind,
        location: point,
        official: _official,
      );
      ok = true;
      messenger.showSnackBar(
        statusSnack(
          l10n.safePlaceSaved(name.isEmpty ? l10n.safePlaceKind(_kind) : name),
        ),
      );
    } on ReportRejected {
      // The database's "inside Manila" check is the precise one.
      _outside = true;
    } on ActionRejected catch (e) {
      messenger.showSnackBar(statusSnack(l10n.actionRejection(e.reason)));
    } catch (_) {
      messenger.showSnackBar(statusSnack(l10n.errorGeneric));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.place == null ? l10n.safePlaceAddTitle : l10n.safePlaceEditTitle,
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('safe-place-name'),
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.fieldPlaceName,
                hintText: l10n.fieldPlaceNameHint,
                errorText: _tried ? _nameError(l10n) : null,
              ),
            ),
            const SizedBox(height: SagipSpace.md),
            DropdownButtonFormField<SafePlaceKind>(
              key: const ValueKey('safe-place-kind'),
              initialValue: _kind,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.fieldPlaceKind),
              items: [
                for (final k in SafePlaceKind.values)
                  DropdownMenuItem(
                    value: k,
                    child: Text(l10n.safePlaceKind(k)),
                  ),
              ],
              onChanged: (k) => setState(() => _kind = k ?? _kind),
            ),
            const SizedBox(height: SagipSpace.md),
            TextField(
              key: const ValueKey('safe-place-position'),
              controller: _position,
              onChanged: (_) => setState(() => _outside = false),
              decoration: InputDecoration(
                labelText: l10n.fieldPlacePosition,
                hintText: l10n.fieldStationPositionHint,
                errorText: _tried ? _positionError(l10n) : null,
              ),
            ),
            const SizedBox(height: SagipSpace.sm),
            CheckboxListTile(
              key: const ValueKey('safe-place-official'),
              value: _official,
              onChanged: (v) => setState(() => _official = v ?? false),
              title: Text(l10n.fieldPlaceOfficial),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(l10n.save)),
      ],
    );
  }
}
