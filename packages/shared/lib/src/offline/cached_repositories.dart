import 'dart:async';

import '../models/alerts.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/settings.dart';
import '../repositories/repositories.dart';
import 'outbox.dart';
import 'streams.dart';

// Read-only data the phone keeps a copy of, so screens work offline: the
// saved copy shows first, and the server's copy replaces it when it comes.

/// The hotline and the SMS gateway number an administrator set on A3,
/// kept on the phone: an SOS by SMS needs the gateway number exactly when
/// there is no internet to ask for it.
class CachedClientConfig implements ClientConfigRepository {
  CachedClientConfig(this._inner, this._store);

  final ClientConfigRepository _inner;
  final LocalStore _store;
  static const _key = 'client-config';

  /// The last copy from the server; empty before the first one.
  ClientConfig get saved {
    final text = _store.read(_key);
    if (text is! String) return const ClientConfig();
    final json = jsonDecodeSafe(text);
    return json is Map
        ? ClientConfig.fromJson(json.cast<String, Object?>())
        : const ClientConfig();
  }

  /// The server's copy, saved; the saved copy when it cannot be reached.
  @override
  Future<ClientConfig> fetch() async {
    try {
      final config = await _inner.fetch();
      await _store.write(_key, jsonEncodeSafe(config.toJson()));
      return config;
    } on Object {
      return saved;
    }
  }
}

/// Alerts and the forecast (R7, R8). Read marks made offline are kept on
/// the phone and shown at once; the server learns them when back online.
class CachedAlertRepository implements AlertRepository {
  CachedAlertRepository(this._inner, this._store, this._account);

  final AlertRepository _inner;
  final LocalStore _store;
  final String? Function() _account;
  final _readHere = <String>{};
  final _confirmationsReadHere = <String>{};
  final _changed = StreamController<Object?>.broadcast();

  String get _key => 'alerts:${_account() ?? '-'}';

  @override
  Stream<AlertFeed> watch() => combineLatest(
    [
      withSavedCopy<AlertFeed>(
        _store,
        _key,
        _inner.watch(),
        decode: (j) => AlertFeed.fromJson((j! as Map).cast<String, Object?>()),
        encode: (f) => f.toJson(),
      ),
      _changed.stream.transform(_startWithNull()),
    ],
    (v) {
      final feed = v[0]! as AlertFeed;
      if (_readHere.isEmpty && _confirmationsReadHere.isEmpty) return feed;
      return feed.copyWith(
        alerts: [
          for (final a in feed.alerts)
            _readHere.contains(a.id) ? a.copyWith(read: true) : a,
        ],
        confirmations: [
          for (final c in feed.confirmations)
            _confirmationsReadHere.contains(c.id) ? c.copyWith(read: true) : c,
        ],
      );
    },
  );

  @override
  Future<void> refresh() => _inner.refresh();

  @override
  Future<void> markRead(String alertId) async {
    _readHere.add(alertId);
    _changed.add(null);
    try {
      await _inner.markRead(alertId);
    } catch (_) {
      // Offline: shown as read here; the next read online tells the server.
    }
  }

  @override
  Future<void> markConfirmationRead(String confirmationId) async {
    _confirmationsReadHere.add(confirmationId);
    _changed.add(null);
    try {
      await _inner.markConfirmationRead(confirmationId);
    } catch (_) {
      // Offline: shown as read here, as for alerts.
    }
  }
}

StreamTransformer<Object?, Object?> _startWithNull() =>
    StreamTransformer.fromBind((s) async* {
      yield null;
      yield* s;
    });

class CachedWeatherRepository implements WeatherRepository {
  const CachedWeatherRepository(this._inner, this._store);

  final WeatherRepository _inner;
  final LocalStore _store;

  @override
  Stream<WeatherStatus> watchCurrent() => withSavedCopy(
    _store,
    'weather',
    _inner.watchCurrent(),
    decode: (j) => WeatherStatus.fromJson((j! as Map).cast<String, Object?>()),
    encode: (w) => w.toJson(),
  );
}

/// The resident's own profile (Home, Me, R9) with a saved copy.
class CachedResidentRepository implements ResidentRepository {
  const CachedResidentRepository(this._inner, this._store);

  final ResidentRepository _inner;
  final LocalStore _store;

  @override
  Stream<Resident?> watchResident(String residentId) => withSavedCopy(
    _store,
    'resident:$residentId',
    _inner.watchResident(residentId),
    decode: (j) => j == null
        ? null
        : Resident.fromJson((j as Map).cast<String, Object?>()),
    encode: (r) => r?.toJson(),
  );

  @override
  Stream<List<Resident>> watchVulnerable() => _inner.watchVulnerable();

  @override
  Future<String> revealContact(String residentId) =>
      _inner.revealContact(residentId);
}
