import 'dart:async';
import 'dart:convert';

import 'outbox.dart';

/// Emits [combine] of the latest value of each stream once all of them have
/// emitted, then again whenever any of them emits. Errors pass through.
Stream<R> combineLatest<R>(
  List<Stream<Object?>> streams,
  R Function(List<Object?> values) combine,
) {
  late final StreamController<R> controller;
  final subs = <StreamSubscription<Object?>>[];
  final values = List<Object?>.filled(streams.length, null);
  final seen = List<bool>.filled(streams.length, false);

  controller = StreamController<R>(
    onListen: () {
      for (var i = 0; i < streams.length; i++) {
        subs.add(
          streams[i].listen((v) {
            values[i] = v;
            seen[i] = true;
            if (seen.every((s) => s)) controller.add(combine(values));
          }, onError: controller.addError),
        );
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
  return controller.stream;
}

/// [source] with the phone's last saved copy in front: the saved copy
/// (if any) is emitted first so screens work offline, and every new value
/// is saved under [key]. Values are stored as JSON text.
Stream<T> withSavedCopy<T>(
  LocalStore store,
  String key,
  Stream<T> source, {
  required T Function(Object? json) decode,
  required Object? Function(T value) encode,
}) {
  late final StreamController<T> controller;
  StreamSubscription<T>? sub;
  controller = StreamController<T>(
    onListen: () {
      final saved = store.read(key);
      if (saved is String) {
        try {
          controller.add(decode(jsonDecode(saved)));
        } catch (_) {
          // An old or damaged copy is ignored; the server copy replaces it.
        }
      }
      sub = source.listen((value) {
        controller.add(value);
        store.write(key, jsonEncode(encode(value)));
      }, onError: controller.addError);
    },
    onCancel: () => sub?.cancel(),
  );
  return controller.stream;
}

/// Decodes a JSON list of objects with [fromJson].
List<T> decodeList<T>(
  Object? json,
  T Function(Map<String, Object?> json) fromJson,
) => [
  for (final e in (json as List<Object?>? ?? const []))
    fromJson((e! as Map).cast<String, Object?>()),
];

/// [source] with errors turned into `null` values, so a screen that merges
/// server data with records on the phone still shows the phone's records
/// while the server cannot be reached.
Stream<T?> nullOnError<T>(Stream<T> source) => source.transform(
  StreamTransformer<T, T?>.fromHandlers(
    handleError: (_, _, sink) => sink.add(null),
  ),
);

/// Decodes [text], or returns null if it is not valid JSON.
Object? jsonDecodeSafe(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

String jsonEncodeSafe(Object? value) => jsonEncode(value);
