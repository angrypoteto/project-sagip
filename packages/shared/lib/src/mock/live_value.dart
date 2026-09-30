import 'dart:async';

/// A value that can be watched: emits the current value on listen, then
/// every change. Stands in for a Supabase realtime channel in the mocks.
class LiveValue<T> {
  LiveValue(this._value);

  T _value;
  final _changes = StreamController<T>.broadcast();

  T get value => _value;

  set value(T next) {
    _value = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  Stream<T> watch() => Stream<T>.multi((listener) {
    listener.add(_value);
    final sub = _changes.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.onCancel = sub.cancel;
  });

  Future<void> close() => _changes.close();
}
