import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// D4: the photos residents added to the SOS, or to the crowd reports in
/// its cluster (2026-10-19), to help verify it. Nothing is shown when there
/// are none.
class IncidentPhotos extends ConsumerWidget {
  const IncidentPhotos({super.key, required this.incidentId});

  final String incidentId;

  static const double thumb = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final photos =
        ref.watch(incidentPhotosProvider(incidentId)).value ?? const [];
    if (photos.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('incident-photos'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.photosTitle(photos.length), style: text.titleSmall),
        const SizedBox(height: SagipSpace.sm),
        Wrap(
          spacing: SagipSpace.sm,
          runSpacing: SagipSpace.sm,
          children: [
            for (final photo in photos)
              _Thumb(photo: photo, onOpen: () => _open(context, photo)),
          ],
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, IncidentPhoto photo) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    photo.url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        _Missing(label: l10n.photoMissing),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(SagipSpace.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.photoCaption(
                          photo.kind == PhotoKind.sos
                              ? l10n.photoFromSos
                              : l10n.photoFromReport,
                          formatDateTime(photo.uploadedAt, locale),
                        ),
                        style: text.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.close),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.onOpen});

  final IncidentPhoto photo;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    return Semantics(
      button: true,
      label: l10n.photoOpen,
      child: Material(
        color: p.panelRaised,
        borderRadius: BorderRadius.circular(SagipRadius.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('photo-${photo.id}'),
          onTap: onOpen,
          child: SizedBox.square(
            dimension: IncidentPhotos.thumb,
            child: Image.network(
              photo.url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _Missing(label: l10n.photoMissing),
            ),
          ),
        ),
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return Tooltip(
      message: label,
      child: Center(
        child: Icon(Symbols.broken_image_rounded, color: p.textSecondary),
      ),
    );
  }
}
