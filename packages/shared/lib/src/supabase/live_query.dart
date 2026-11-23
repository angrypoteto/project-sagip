import 'dart:async';

import 'package:supabase/supabase.dart';

int _channelCount = 0;

final _restarts = StreamController<void>.broadcast();

/// Drops every live query's realtime channel and joins a new one (each
/// query refetches once joined). For a link stuck reconnecting: Joshua,
/// 2026-11-23, the board stayed on "Live updates paused. Reconnecting."
/// until the page was refreshed. Called by [SupabaseConnectionMonitor].
void restartLiveQueries() => _restarts.add(null);

/// A stream that runs [fetch] on listen, then runs it again whenever one of
/// [tables] changes (Supabase Realtime), if set every [refreshEvery], and
/// whenever [refreshOn] emits (for changes realtime cannot deliver).
///
/// Changes are debounced so a burst (an assignment touches three tables)
/// causes one refetch. It also refetches each time the realtime channel
/// (re)joins, so changes missed while disconnected are picked up.
Stream<T> liveQuery<T>(
  SupabaseClient client, {
  required List<String> tables,
  required Future<T> Function() fetch,
  Duration? refreshEvery,
  Stream<Object?>? refreshOn,
  Duration debounce = const Duration(milliseconds: 200),
}) {
  late final StreamController<T> controller;
  RealtimeChannel? channel;
  Timer? pending;
  Timer? periodic;
  StreamSubscription<Object?>? manual;
  StreamSubscription<void>? restarts;
  var sequence = 0;

  Future<void> run() async {
    final mine = ++sequence;
    try {
      final value = await fetch();
      // Drop a slow response if a newer fetch has started since.
      if (mine == sequence && !controller.isClosed) controller.add(value);
    } catch (error, stack) {
      if (mine == sequence && !controller.isClosed) {
        controller.addError(error, stack);
      }
    }
  }

  void schedule() {
    pending?.cancel();
    pending = Timer(debounce, run);
  }

  void join() {
    var ch = client.channel('live-${tables.join('-')}-${_channelCount++}');
    for (final table in tables) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => schedule(),
      );
    }
    channel = ch.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) schedule();
    });
  }

  controller = StreamController<T>(
    onListen: () {
      run();
      join();
      restarts = _restarts.stream.listen((_) {
        final old = channel;
        if (old != null) {
          unawaited(client.removeChannel(old).catchError((_) => ''));
        }
        join();
      });
      if (refreshEvery != null) {
        periodic = Timer.periodic(refreshEvery, (_) => schedule());
      }
      manual = refreshOn?.listen((_) => schedule());
    },
    onCancel: () async {
      pending?.cancel();
      periodic?.cancel();
      await manual?.cancel();
      await restarts?.cancel();
      final ch = channel;
      channel = null;
      if (ch != null) await client.removeChannel(ch);
    },
  );
  return controller.stream;
}
