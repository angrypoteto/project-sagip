import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

/// A searchable barangay list (W1 register, W2 location). The list is the
/// bundled sample until the Data role supplies all 897 barangays.
Future<Barangay?> showWebBarangayDialog(
  BuildContext context, {
  bool needsCenter = false,
}) => showDialog<Barangay>(
  context: context,
  builder: (context) => _BarangayDialog(needsCenter: needsCenter),
);

class _BarangayDialog extends StatefulWidget {
  const _BarangayDialog({required this.needsCenter});

  /// W2 moves the pin to the barangay's centre, so it needs one.
  final bool needsCenter;

  @override
  State<_BarangayDialog> createState() => _BarangayDialogState();
}

class _BarangayDialogState extends State<_BarangayDialog> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final q = _query.trim().toLowerCase();
    final matches = [
      for (final b in sampleManilaBarangays)
        if ((!widget.needsCenter || b.center != null) &&
            (q.isEmpty || '${b.name} ${b.district}'.toLowerCase().contains(q)))
          b,
    ];
    return AlertDialog(
      title: Text(l10n.webChooseBarangayButton),
      contentPadding: const EdgeInsets.only(top: SagipSpace.lg),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SagipSpace.xxl),
              child: TextField(
                key: const ValueKey('barangay-search'),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.webSearchBarangay,
                  prefixIcon: const Icon(Symbols.search_rounded),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: SagipSpace.sm),
            Expanded(
              child: matches.isEmpty
                  ? EmptyState(
                      icon: Symbols.search_off_rounded,
                      title: l10n.webNoBarangayMatch,
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, i) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: SagipSpace.xxl,
                        ),
                        title: Text(matches[i].name),
                        subtitle: Text(matches[i].district),
                        onTap: () => Navigator.pop(context, matches[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
