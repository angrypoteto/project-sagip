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
import '../board/board_dialogs.dart';
import '../common_page.dart';

/// D9: the Vulnerable Resident Priority List. Admins and dispatchers only
/// (NFR4); numbers stay masked until revealed, and revealing is audited.
class VulnerablePage extends ConsumerWidget {
  const VulnerablePage({super.key, this.barangay});

  /// Only this barangay's residents (the link from the forecast, D8).
  final String? barangay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final residentsAsync = ref.watch(vulnerableResidentsProvider);
    final residents = [
      for (final r in residentsAsync.value ?? const <Resident>[])
        if (barangay == null || r.barangay == barangay) r,
    ]..sort((a, b) => a.barangay.compareTo(b.barangay));

    return PageFrame(
      title: l10n.vulnerableTitle,
      subtitle: l10n.vulnerablePrivacy,
      child: AsyncBody(
        value: residentsAsync,
        isEmpty: (list) => list.isEmpty,
        empty: EmptyState(
          icon: Symbols.accessible_rounded,
          title: l10n.vulnerableEmpty,
        ),
        builder: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (barangay != null) ...[
              Row(
                children: [
                  SagipChip(
                    label: l10n.vulnerableOnly(barangay!),
                    tone: p.info,
                    icon: Symbols.filter_alt_rounded,
                  ),
                  const SizedBox(width: SagipSpace.sm),
                  TextButton(
                    onPressed: () => context.go(Routes.vulnerable),
                    child: Text(l10n.vulnerableShowAll),
                  ),
                ],
              ),
              const SizedBox(height: SagipSpace.md),
            ],
            if (residents.isEmpty)
              EmptyState(
                icon: Symbols.accessible_rounded,
                title: l10n.vulnerableNoneIn(barangay ?? ''),
              )
            else
              _table(context, ref, residents),
          ],
        ),
      ),
    );
  }

  Widget _table(BuildContext context, WidgetRef ref, List<Resident> residents) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    return TableCard(
      table: DataTable(
        dataRowMaxHeight: 88,
        columns: [
          DataColumn(label: Text(l10n.colResident)),
          DataColumn(label: Text(l10n.colPlace)),
          DataColumn(label: Text(l10n.colHousehold)),
          DataColumn(label: Text(l10n.colContact)),
          DataColumn(label: Text(l10n.colConsent)),
          DataColumn(label: Text(l10n.colUpdated)),
        ],
        rows: [
          for (final r in residents)
            DataRow(
              cells: [
                DataCell(Text(r.fullName, style: text.titleSmall)),
                DataCell(Text(r.place)),
                DataCell(
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SagipSpace.sm,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: SagipSpace.xs,
                          runSpacing: SagipSpace.xs,
                          children: [
                            for (final v in r.vulnerabilityTypes)
                              SagipChip(
                                label: l10n.vulnerability(v),
                                tone: p.neutral,
                                icon: vulnerabilityIcon(v),
                              ),
                          ],
                        ),
                        for (final m in r.household)
                          if (m.notes != null)
                            Text(
                              '${m.label}: ${m.notes}',
                              style: text.bodySmall,
                            ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    children: [
                      Text(
                        r.maskedContact,
                        style: text.bodyMedium!.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      TextButton(
                        onPressed: () => showCallDialog(context, ref, r),
                        child: Text(l10n.showNumber),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Text(
                    r.consentGivenAt == null
                        ? ''
                        : formatDateTime(r.consentGivenAt!, locale),
                  ),
                ),
                DataCell(
                  Text(
                    r.updatedAt == null
                        ? ''
                        : formatDateTime(r.updatedAt!, locale),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
