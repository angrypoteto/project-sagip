import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/async_body.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common_page.dart';

/// A7: every dispatch action, status change, and verification with the
/// acting account (FR11). Admins only; the router hides it from dispatchers.
class AuditLogPage extends ConsumerWidget {
  const AuditLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final logAsync = ref.watch(auditLogProvider);

    return PageFrame(
      title: l10n.auditTitle,
      subtitle: l10n.auditSubtitle,
      child: AsyncBody(
        value: logAsync,
        isEmpty: (list) => list.isEmpty,
        empty: EmptyState(
          icon: Symbols.history_rounded,
          title: l10n.auditEmpty,
        ),
        builder: (entries) => TableCard(
          table: DataTable(
            columns: [
              DataColumn(label: Text(l10n.colTime)),
              DataColumn(label: Text(l10n.colAccount)),
              DataColumn(label: Text(l10n.colAction)),
              DataColumn(label: Text(l10n.colTarget)),
              DataColumn(label: Text(l10n.colDetail)),
            ],
            rows: [
              for (final e in entries)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        formatClock(e.at, locale),
                        style: text.bodyMedium!.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        l10n.userWithRole(e.actorName, l10n.role(e.actorRole)),
                      ),
                    ),
                    DataCell(Text(l10n.auditAction(e.action))),
                    DataCell(Text('${e.targetTable} ${e.targetId}')),
                    DataCell(Text(e.detail ?? '')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
