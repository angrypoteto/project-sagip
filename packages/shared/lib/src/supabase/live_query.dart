import 'dart:async';

import 'package:supabase/supabase.dart';

int _channelCount = 0;

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

  controller = StreamController<T>(
    onListen: () {
      run();
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
      if (refreshEvery != null) {
        periodic = Timer.periodic(refreshEvery, (_) => schedule());
      }
      manual = refreshOn?.listen((_) => schedule());
    },
    onCancel: () async {
      pending?.cancel();
      periodic?.cancel();
      await manual?.cancel();
      final ch = channel;
      channel = null;
      if (ch != null) await client.removeChannel(ch);
    },
  );
  return controller.stream;
}
