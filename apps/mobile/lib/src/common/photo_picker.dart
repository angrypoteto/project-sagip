import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

/// Where a photo comes from.
enum PhotoFrom { camera, gallery }

/// Takes or chooses a photo and gets it ready to send ([preparePhoto]):
/// null when the person cancelled or it could not be used.
typedef PhotoTaker = Future<Uint8List?> Function(PhotoFrom from);

/// The phone's camera and gallery (2026-10-19). Tests override it.
final photoTakerProvider = Provider<PhotoTaker>((ref) => devicePhotoTaker);

Future<Uint8List?> devicePhotoTaker(PhotoFrom from) async {
  try {
    final file = await ImagePicker().pickImage(
      source: from == PhotoFrom.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      // Smaller first, so getting it ready is quick on a low-end phone.
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final raw = await file.readAsBytes();
    return await compute(preparePhoto, raw);
  } catch (_) {
    return null;
  }
}

/// Asks camera or gallery, then returns the photo ready to send. Null when
/// cancelled; says so when the photo could not be used.
Future<Uint8List?> pickPhoto(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final from = await showModalBottomSheet<PhotoFrom>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('photo-camera'),
            leading: const Icon(Symbols.photo_camera_rounded),
            title: Text(l10n.photoTake),
            onTap: () => Navigator.pop(context, PhotoFrom.camera),
          ),
          ListTile(
            key: const ValueKey('photo-gallery'),
            leading: const Icon(Symbols.photo_library_rounded),
            title: Text(l10n.photoChoose),
            onTap: () => Navigator.pop(context, PhotoFrom.gallery),
          ),
          const SizedBox(height: SagipSpace.sm),
        ],
      ),
    ),
  );
  if (from == null) return null;
  final photo = await ref.read(photoTakerProvider)(from);
  if (photo == null) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.photoFailed)));
  }
  return photo;
}
