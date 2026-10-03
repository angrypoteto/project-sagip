import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

/// A searchable barangay list (S4, R5). Works offline: the list is bundled.
Future<Barangay?> showBarangayPicker(BuildContext context) =>
    showModalBottomSheet<Barangay>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => const _BarangayPicker(),
    );

class _BarangayPicker extends StatefulWidget {
  const _BarangayPicker();

  @override
  State<_BarangayPicker> createState() => _BarangayPickerState();
}

class _BarangayPickerState extends State<_BarangayPicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final q = _query.trim().toLowerCase();
    final matches = [
      for (final b in manilaBarangays)
        if (q.isEmpty ||
            b.name.toLowerCase().contains(q) ||
            b.district.toLowerCase().contains(q))
          b,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SagipSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.chooseBarangay, style: text.titleLarge),
                  const SizedBox(height: SagipSpace.md),
                  TextField(
                    autofocus: false,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      labelText: l10n.searchBarangay,
                      prefixIcon: const Icon(Symbols.search_rounded),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: SagipSpace.sm),
                  Text(
                    l10n.sampleBarangays,
                    style: text.bodySmall!.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? EmptyState(
                      icon: Symbols.search_off_rounded,
                      title: l10n.noBarangayMatch,
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(matches[i].name),
                        subtitle: Text(matches[i].district),
                        onTap: () => Navigator.pop(context, matches[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
