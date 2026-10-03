import 'dart:async';
import 'dart:math';

import '../algorithms/sos_relay.dart';
import '../algorithms/sos_sms.dart';
import '../mock/live_value.dart';
import '../models/assignment.dart';
import '../models/enums.dart';
import '../models/hazard_report.dart';
import '../models/offline.dart';
import '../models/sos.dart';
import '../repositories/repositories.dart';
import 'mobile_server.dart';
import 'outbox.dart';
import 'relay.dart';

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

/// Sends a text message from this phone (Tier 2).
abstract interface class SmsSender {
  /// True when the phone's SMS service accepted and sent it.
  Future<bool> send(String number, String text);
}

/// Tier 2 (plan section 11): an SOS goes to the MDRRMD gateway SIM as an
/// SMS in the SAGIP1 format while the phone has signal but no data.
class SmsTier {
  const SmsTier({
    required this.sender,
    required this.gatewayNumber,
    required this.available,
    this.retryAfter = const Duration(seconds: 30),
  });

  final SmsSender sender;

  /// The gateway SIM's number right now: from the build, or the one an
  /// administrator set on A3 (kept on the phone). Empty while unknown;
  /// nothing is texted then.
  final String Function() gatewayNumber;

  /// True while texting is the way out (signal, no internet).
  final Stream<bool> available;

  /// A failed text is tried again after this, while texting is possible.
  final Duration retryAfter;
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
    SmsTier? sms,
    RelayTier? relay,
  }) : _store = store,
       _sms = sms,
       _relay = relay,
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
      // A send cut off when the app closed counts as not sent; an advert
      // stopped with the app, so a relaying SOS is advertised again.
      kept.add(
        e.delivery == DeliveryState.sending ||
                e.delivery == DeliveryState.relaying
            ? e.copyWith(delivery: _notSent(e), waited: true)
            : e,
      );
    }
    _entries = LiveValue(_sorted(kept));
    _onlineSub = online.listen((on) {
      _online = on;
      if (on) unawaited(pump());
    });
    _smsSub = sms?.available.listen((ok) {
      _smsOk = ok;
      if (ok) unawaited(pump());
    });
    _relaySub = relay?.available.listen((ok) {
      _relayOk = ok;
      if (ok) unawaited(pump());
    });
  }

  /// Where a record goes back to when a send did not finish: still "sent
  /// by SMS" if the SMS went out.
  static DeliveryState _notSent(OutboxEntry e) => e.smsSentAt != null
      ? DeliveryState.sentBySms
      : DeliveryState.savedOnPhone;

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
  final SmsTier? _sms;
  StreamSubscription<bool>? _smsSub;
  var _smsOk = false;
  final RelayTier? _relay;
  StreamSubscription<bool>? _relaySub;
  var _relayOk = false;
  Timer? _smsRetry;
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
            if (_smsOk &&
                _sms!.gatewayNumber().isNotEmpty &&
                e.action == OutboxAction.sos &&
                e.delivery == DeliveryState.savedOnPhone) {
              await _sendSms(e);
            } else if (_relayOk &&
                e.action == OutboxAction.sos &&
                e.delivery == DeliveryState.savedOnPhone) {
              await _sendRelay(e);
            } else if (!e.waited) {
              await _put(e.copyWith(waited: true));
            }
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
      if (e.delivery == DeliveryState.relaying ||
          (e.action == OutboxAction.sos && _relay != null)) {
        await _stopRelay(e);
      }
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

  /// Tier 2: texts the SOS to the gateway. It stays pending (sent by SMS)
  /// so it still goes over the internet later; a failed text is tried again
  /// after [SmsTier.retryAfter] while texting is possible.
  Future<void> _sendSms(OutboxEntry e) async {
    final sms = _sms!;
    var sent = false;
    try {
      final text = SosSms.encode(SosRequest.fromJson(e.payload));
      sent = await sms.sender
          .send(sms.gatewayNumber(), text)
          .timeout(const Duration(seconds: 45), onTimeout: () => false);
    } catch (_) {
      sent = false;
    }
    if (sent) {
      await _put(
        e.copyWith(
          delivery: DeliveryState.sentBySms,
          smsSentAt: _clock(),
          waited: true,
        ),
      );
      return;
    }
    if (!e.waited) await _put(e.copyWith(waited: true));
    _smsRetry?.cancel();
    if (!_disposed) {
      _smsRetry = Timer(sms.retryAfter, () {
        if (_smsOk) unawaited(pump());
      });
    }
  }

  /// Tier 3: advertises the SOS to nearby phones (Bluetooth LE). It stays
  /// pending (relaying) so it still goes over the internet later; the
  /// server keeps one incident whichever copy arrives first.
  Future<void> _sendRelay(OutboxEntry e) async {
    final relay = _relay!;
    var started = false;
    try {
      final sos = SosRequest.fromJson(e.payload);
      started = await relay.radio.advertise(
        RelayTier.ownKey(sos.clientId),
        SosRelayPacket.of(sos).encode(),
      );
    } catch (_) {
      started = false;
    }
    await _put(
      started
          ? e.copyWith(delivery: DeliveryState.relaying, waited: true)
          : e.copyWith(waited: true),
    );
  }

  Future<void> _stopRelay(OutboxEntry e) async {
    try {
      final id = e.payload['client_id'] as String?;
      if (id != null) await _relay?.radio.stop(RelayTier.ownKey(id));
    } catch (_) {
      // The advert ends with the app anyway.
    }
  }

  Future<void> _reject(OutboxEntry e, String reason) =>
      _put(e.copyWith(delivery: DeliveryState.rejected, rejectReason: reason));

  Future<bool> _failed(OutboxEntry e) async {
    final back = e.copyWith(
      delivery: _notSent(e),
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
    _smsRetry?.cancel();
    await _smsSub?.cancel();
    await _relaySub?.cancel();
    await _onlineSub.cancel();
    await _deliveries.close();
  }
}
