import 'package:flutter/services.dart';
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
import 'supply_widgets.dart';

/// A responder's own unit on the web: what it carries, reported by its
/// crew (unit inventory). It sits in the same frame as the dispatcher's
/// and the admin's pages, is the one page in a responder's menu, and is
/// the only place a unit's supplies are changed.
class MyUnitPage extends ConsumerWidget {
  const MyUnitPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final unitAsync = ref.watch(myUnitProvider);
    return PageFrame(
      title: l10n.myUnitTitle,
      subtitle: l10n.myUnitIntro,
      child: AsyncBody(
        value: unitAsync,
        isEmpty: (unit) => unit == null,
        empty: EmptyState(
          icon: Symbols.group_off_rounded,
          title: l10n.myUnitNone,
          message: l10n.myUnitNoneBody,
        ),
        onRetry: () => ref.invalidate(myUnitProvider),
        builder: (unit) => _Body(unit: unit!),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.unit});

  final ResponseUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final supplies = ref.watch(mySuppliesProvider).value ?? const [];
    final lowPercent = ref.watch(inventoryLowPercentProvider);
    final online = ref.watch(isOnlineProvider);
    final now = ref.watch(slowClockProvider).value ?? DateTime.now();
    final byItem = {for (final s in supplies) s.item: s};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: SagipSpace.sm,
          runSpacing: SagipSpace.sm,
          children: [
            SagipChip.status(
              label: l10n.unitStatus(unit.status),
              visual: unitStatusVisual(unit.status, p),
              dense: false,
            ),
          ],
        ),
        const SizedBox(height: SagipSpace.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(SagipSpace.lg),
            child: Row(
              children: [
                Icon(unitTypeIcon(unit.type), size: 28),
                const SizedBox(width: SagipSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(unit.callSign, style: text.titleLarge),
                      Text(
                        '${l10n.unitType(unit.type)} · '
                        '${l10n.unitAgency(unit.agency)} · ${unit.station}',
                        style: text.bodyMedium!.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SagipSpace.md),
        _CrewCard(unitId: unit.id),
        const SizedBox(height: SagipSpace.lg),
        Text(
          l10n.suppliesLowRule(lowPercent.round()),
          style: text.bodySmall!.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: SagipSpace.lg),
        // Two cards across on a wide window, one on a narrow one.
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = SagipSpace.md;
            final across = constraints.maxWidth >= 900 ? 2 : 1;
            final width = (constraints.maxWidth - gap * (across - 1)) / across;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in SupplyItem.values)
                  SizedBox(
                    width: width,
                    child: _SupplyEditor(
                      key: ValueKey('supply-${item.name}'),
                      item: item,
                      current: byItem[item],
                      lowPercent: lowPercent,
                      now: now,
                      enabled: online,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Who is on this unit (Joshua, 2026-10-28): each member's full name and
/// MDRRMD personnel ID, the signed-in responder marked "You".
class _CrewCard extends ConsumerWidget {
  const _CrewCard({required this.unitId});

  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final me = ref.watch(currentUserProvider).value?.id;
    final crew = [
      for (final c in ref.watch(crewProvider).value ?? const <CrewMember>[])
        if (c.unitId == unitId) c,
    ];
    return Card(
      key: const ValueKey('my-unit-crew'),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Symbols.groups_rounded, color: p.textSecondary),
                const SizedBox(width: SagipSpace.sm),
                Text(l10n.myUnitCrewTitle, style: text.titleMedium),
                const SizedBox(width: SagipSpace.sm),
                Text(
                  '${crew.length}',
                  style: text.titleMedium!.copyWith(
                    color: p.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: SagipSpace.sm),
            for (final c in crew)
              Padding(
                key: ValueKey('my-crew-${c.staffId}'),
                padding: const EdgeInsets.symmetric(vertical: SagipSpace.sm),
                child: Row(
                  children: [
                    Icon(
                      Symbols.person_rounded,
                      size: 20,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: SagipSpace.md),
                    Expanded(
                      child: Wrap(
                        spacing: SagipSpace.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(c.displayName, style: text.bodyLarge),
                          if (c.staffId == me)
                            SagipChip(label: l10n.myUnitCrewYou, tone: p.info),
                        ],
                      ),
                    ),
                    Text(
                      c.personnelId ?? l10n.personnelIdMissing,
                      style: text.bodyMedium!.copyWith(
                        color: c.personnelId == null ? p.textSecondary : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            if (crew.length <= 1)
              Text(
                l10n.myUnitCrewEmpty,
                style: text.bodySmall!.copyWith(color: p.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

/// One supply: how it stands, and the fields to report it again.
class _SupplyEditor extends ConsumerStatefulWidget {
  const _SupplyEditor({
    super.key,
    required this.item,
    required this.current,
    required this.lowPercent,
    required this.now,
    required this.enabled,
  });

  final SupplyItem item;
  final UnitSupply? current;
  final double lowPercent;
  final DateTime now;
  final bool enabled;

  @override
  ConsumerState<_SupplyEditor> createState() => _SupplyEditorState();
}

class _SupplyEditorState extends ConsumerState<_SupplyEditor> {
  late double _percent = widget.current?.quantity ?? 100;
  late final _have = TextEditingController(
    text: widget.current == null ? '' : '${widget.current!.quantity.round()}',
  );
  late final _full = TextEditingController(
    text: widget.current == null ? '' : '${widget.current!.capacity.round()}',
  );
  var _busy = false;

  /// A newer report (this crew's own, or a crewmate's) replaces what is in
  /// the fields: they always start from what dispatch sees.
  @override
  void didUpdateWidget(_SupplyEditor old) {
    super.didUpdateWidget(old);
    final now = widget.current;
    if (now != null && now.updatedAt != old.current?.updatedAt) {
      _percent = now.quantity;
      _have.text = '${now.quantity.round()}';
      _full.text = '${now.capacity.round()}';
    }
  }

  @override
  void dispose() {
    _have.dispose();
    _full.dispose();
    super.dispose();
  }

  int? get _haveN => int.tryParse(_have.text.trim());
  int? get _fullN => int.tryParse(_full.text.trim());

  bool get _countOk {
    final have = _haveN, full = _fullN;
    return have != null &&
        full != null &&
        full >= 1 &&
        full <= 100000 &&
        have >= 0 &&
        have <= full;
  }

  bool get _changed {
    final c = widget.current;
    if (widget.item.isPercent) return c == null || c.quantity != _percent;
    return c == null ||
        c.quantity.round() != _haveN ||
        c.capacity.round() != _fullN;
  }

  Future<void> _report() async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(unitInventoryRepositoryProvider);
    final item = widget.item;
    setState(() => _busy = true);
    await runAction(
      context,
      () => item.isPercent
          ? repo.setSupply(item, _percent.round())
          : repo.setSupply(item, _haveN!, capacity: _fullN),
      success: l10n.myUnitSaved(l10n.supplyItem(item)),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final current = widget.current;
    final valid = item.isPercent || _countOk;
    final typed = _have.text.isNotEmpty || _full.text.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (current == null)
              Row(
                children: [
                  Icon(supplyIcon(item), size: 18, color: p.textSecondary),
                  const SizedBox(width: SagipSpace.sm),
                  Expanded(
                    child: Text(l10n.supplyItem(item), style: text.titleSmall),
                  ),
                  Text(
                    l10n.myUnitNotYet,
                    style: text.bodySmall!.copyWith(color: p.textSecondary),
                  ),
                ],
              )
            else
              SupplyLine(
                supply: current,
                lowPercent: widget.lowPercent,
                now: widget.now,
              ),
            const SizedBox(height: SagipSpace.sm),
            if (item.isPercent)
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _percent,
                      max: 100,
                      divisions: 20,
                      label: l10n.supplyPercent(_percent.round()),
                      semanticFormatterCallback: (v) => l10n.myUnitPercentLabel(
                        l10n.supplyItem(item),
                        v.round(),
                      ),
                      onChanged: widget.enabled
                          ? (v) => setState(() => _percent = v)
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      l10n.supplyPercent(_percent.round()),
                      textAlign: TextAlign.end,
                      style: text.titleSmall!.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (controller, label, key) in [
                    (_have, l10n.myUnitOnBoard, 'have'),
                    (_full, l10n.myUnitFullLoad, 'full'),
                  ]) ...[
                    SizedBox(
                      width: 150,
                      child: TextField(
                        key: ValueKey('supply-${item.name}-$key'),
                        controller: controller,
                        enabled: widget.enabled,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(labelText: label),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: SagipSpace.md),
                  ],
                ],
              ),
            if (!item.isPercent && typed && !valid) ...[
              const SizedBox(height: SagipSpace.xs),
              Text(
                l10n.myUnitCountError,
                style: text.bodySmall!.copyWith(color: p.critical.text),
              ),
            ],
            const SizedBox(height: SagipSpace.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: ValueKey('report-${item.name}'),
                onPressed: widget.enabled && !_busy && valid && _changed
                    ? _report
                    : null,
                child: Text(_busy ? l10n.working : l10n.myUnitReport),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
