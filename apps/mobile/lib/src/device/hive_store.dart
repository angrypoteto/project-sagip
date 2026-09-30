import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The phone's storage (Hive): the outbox of records waiting to be sent,
/// the last server copies for offline reading, and small settings.
///
/// Both boxes are encrypted (AES-256) with a key kept in Android's secure
/// storage, since they hold SOS locations and household details (RA 10173).
class HiveLocalStore implements LocalStore {
  HiveLocalStore._(this._outbox, this._values);

  final Box<String> _outbox;
  final Box<String> _values;

  static const _keyName = 'sagip-store-key';

  static Future<HiveLocalStore> open() async {
    await Hive.initFlutter('sagip');
    final cipher = HiveAesCipher(await _key());
    Future<Box<String>> box(String name) async {
      try {
        return await Hive.openBox<String>(name, encryptionCipher: cipher);
      } catch (_) {
        // The key was lost (for example after restoring a backup): the old
        // box cannot be read, so start it again.
        await Hive.deleteBoxFromDisk(name);
        return Hive.openBox<String>(name, encryptionCipher: cipher);
      }
    }

    return HiveLocalStore._(await box('outbox'), await box('values'));
  }

  static Future<List<int>> _key() async {
    const storage = FlutterSecureStorage();
    final saved = await storage.read(key: _keyName);
    if (saved != null) return base64Url.decode(saved);
    final key = Hive.generateSecureKey();
    await storage.write(key: _keyName, value: base64UrlEncode(key));
    return key;
  }

  @override
  List<OutboxEntry> get outbox => [
    for (final text in _outbox.values)
      if (jsonDecodeSafe(text) case final Map<String, dynamic> json)
        OutboxEntry.fromJson(json),
  ];

  @override
  Future<void> putEntry(OutboxEntry entry) =>
      _outbox.put(entry.id, jsonEncode(entry.toJson()));

  @override
  Future<void> deleteEntry(String id) => _outbox.delete(id);

  @override
  Object? read(String key) => _values.get(key);

  @override
  Future<void> write(String key, Object? value) => value == null
      ? _values.delete(key)
      : _values.put(key, value is String ? value : jsonEncode(value));
}
