import 'dart:async';
import 'dart:math';

import '../mock/live_value.dart';
import '../models/assignment.dart';
import '../models/enums.dart';
import '../models/hazard_report.dart';
import '../models/offline.dart';
import '../models/sos.dart';
import '../repositories/repositories.dart';
import 'mobile_server.dart';
import 'outbox.dart';

/// Sends one outbox record. Returns the server's id for it, if any.
abstract interface class OutboxSender {
  Future<String?> send(OutboxEntry entry);
}

/// Sends outbox records with a [MobileServer].
class ServerSender implements OutboxSender {
  const ServerSender(this._server);

  final MobileServer _server;

  @override
  Future<String?> send(OutboxEntry entry) async {
    final p = entry.payload;
    String incident() => p['incident_id']! as String;
    switch (entry.action) {
      case OutboxAction.sos:
        return _server.submitSos(SosRequest.fromJson(p));
      case OutboxAction.sosDetails:
        await _server.addSosDetails(
          p['client_id']! as String,
          SosDetails.fromJson((p['details']! as Map).cast<String, Object?>()),
        );
        return null;
      case OutboxAction.crowdReport:
        return _server.submitReport(HazardReport.fromJson(p));
      case OutboxAction.accept:
        await _server.accept(incident(), entry.capturedAt);
        return null;
      case OutboxAction.arrive:
        await _server.arrive(incident(), entry.capturedAt);
        return null;
      case OutboxAction.confirmOnScene:
        await _server.confirmOnScene(
          incident(),
          realEmergency: p['real_emergency']! as bool,
          reason: p['reason'] as String?,
          peopleFound: p['people_found'] as int?,
          capturedAt: entry.capturedAt,
        );
        return null;
      case OutboxAction.setStatus:
        await _server.setStatus(
          UnitStatus.values.byName(p['status']! as String),
          entry.capturedAt,
        );
        return null;
      case OutboxAction.completion:
        await _server.submitCompletion(
          CompletionReport.fromJson(
            (p['report']! as Map).cast<String, Object?>(),
          ),
        );
        return null;
    }
  }
}

/// Works through the outbox (NFR1, FR13): records are saved first, sent in
/// the order they were made, and marked delivered only when the server
/// confirms them. A refused record is kept (marked rejected) and the rest
/// go on; a network failure stops the run so the order holds, and it is
/// tried again after a pause or as soon as the phone is back online.
class SyncEngine {
  SyncEngine({
    required LocalStore store,
    required this._sender,
    required Stream<bool> online,
    required this._account,
    DateTime Function()? clock,
    Duration Function(int attempts)? retryDelay,
  }) : _store = store,
       _clock = clock ?? DateTime.now,
       _retryDelay = retryDelay ?? defaultRetryDelay {
    final now = _clock();
    final kept = <OutboxEntry>[];
    for (final e in store.outbox) {
      final delivered = e.delivery == DeliveryState.delivered;
      if (delivered && now.difference(e.deliveredAt ?? now) > keepDelivered) {
        unawaited(store.deleteEntry(e.id));
        continue;
      }
      // A send cut off when the app closed counts as not sent.
      kept.add(
        e.delivery == DeliveryState.sending
            ? e.copyWith(delivery: DeliveryState.savedOnPhone, waited: true)
            : e,
      );
    }
    _entries = LiveValue(_sorted(kept));
    _onlineSub = online.listen((on) {
      _online = on;
      if (on) unawaited(pump());
    });
  }

  /// Delivered records stay this long so screens can show them until the
  /// server's copy catches up.
  static const keepDelivered = Duration(days: 1);

  /// 5 s, 10 s, 20 s, ... up to 5 minutes.
  static Duration defaultRetryDelay(int attempts) =>
      Duration(seconds: min(300, 5 * pow(2, max(0, attempts - 1)).toInt()));

  final LocalStore _store;
  final OutboxSender _sender;
  final String? Function() _account;
  final DateTime Function() _clock;
  final Duration Function(int attempts) _retryDelay;
  late final LiveValue<List<OutboxEntry>> _entries;
  late final StreamSubscription<bool> _onlineSub;
  final _deliveries = StreamController<QueuedRecord>.broadcast();
  Timer? _retry;
  var _online = false;
  var _pumping = false;
  var _again = false;
  var _disposed = false;

  /// Every record on the phone, oldest capture first.
  Stream<List<OutboxEntry>> watch() => _entries.watch();
  List<OutboxEntry> get entries => _entries.value;

  /// One event per record the server confirms.
  Stream<QueuedRecord> deliveries() => _deliveries.stream;

  static List<OutboxEntry> _sorted(List<OutboxEntry> list) =>
      list..sort((a, b) {
        final t = a.capturedAt.compareTo(b.capturedAt);
        return t != 0 ? t : a.sequence.compareTo(b.sequence);
      });

  Future<void> _put(OutboxEntry e) async {
    await _store.putEntry(e);
    _entries.value = _sorted([
      for (final x in _entries.value)
        if (x.id != e.id) x,
      e,
    ]);
  }

  /// Saves [entry] on the phone, then starts sending. Returns once saved;
  /// it never waits for the network.
  Future<void> add(OutboxEntry entry) async {
    final next = _entries.value.fold(0, (m, e) => max(m, e.sequence)) + 1;
    final numbered = entry.copyWith(sequence: next);
    await _put(_online ? numbered : numbered.copyWith(waited: true));
    unawaited(pump());
  }

  /// Removes a record the server refused (S6).
  Future<void> remove(String id) async {
    final e = entries.where((x) => x.id == id).firstOrNull;
    if (e == null || e.delivery != DeliveryState.rejected) return;
    await _store.deleteEntry(id);
    _entries.value = [
      for (final x in _entries.value)
        if (x.id != id) x,
    ];
  }

  Future<void> retryNow() {
    _retry?.cancel();
    return pump();
  }

  /// The signed-in account changed; its records can go now.
  void accountChanged() => unawaited(pump());

  Future<void> pump() async {
    if (_pumping) {
      _again = true;
      return;
    }
    _pumping = true;
    try {
      do {
        _again = false;
        final me = _account();
        if (me == null) return;
        final pending = [
          for (final e in _entries.value)
            if (e.accountId == me && e.delivery.isPending) e,
        ];
        for (final e in pending) {
          if (_disposed) return;
          if (!_online) {
            if (!e.waited) await _put(e.copyWith(waited: true));
            continue;
          }
          if (!await _send(e)) break;
        }
      } while (_again && !_disposed);
    } finally {
      _pumping = false;
    }
  }

  /// Returns false when the network failed (stop, keep the order).
  Future<bool> _send(OutboxEntry e) async {
    await _put(e.copyWith(delivery: DeliveryState.sending));
    try {
      final serverId = await _sender.send(e);
      final done = e.copyWith(
        delivery: DeliveryState.delivered,
        serverId: serverId,
        deliveredAt: _clock(),
      );
      await _put(done);
      if (!_deliveries.isClosed) _deliveries.add(done.toQueued());
      return true;
    } on ActionRejected catch (err) {
      if (err.reason == ActionRejection.offline) return _failed(e);
      await _reject(e, err.reason.name);
      return true;
    } on ReportRejected catch (err) {
      await _reject(e, err.reason.name);
      return true;
    } on StatusRejected catch (err) {
      await _reject(e, err.reason.name);
      return true;
    } catch (_) {
      // Anything unexpected is retried: an SOS is never dropped.
      return _failed(e);
    }
  }

  Future<void> _reject(OutboxEntry e, String reason) =>
      _put(e.copyWith(delivery: DeliveryState.rejected, rejectReason: reason));

  Future<bool> _failed(OutboxEntry e) async {
    final back = e.copyWith(
      delivery: DeliveryState.savedOnPhone,
      attempts: e.attempts + 1,
      waited: true,
    );
    await _put(back);
    _retry?.cancel();
    if (!_disposed) {
      _retry = Timer(_retryDelay(back.attempts), () => unawaited(pump()));
    }
    return false;
  }

  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    await _onlineSub.cancel();
    await _deliveries.close();
  }
}
