import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

_ParserWorker? _worker;

_ParserWorker get _currentWorker => _worker ??= _ParserWorker();

Future<void> prewarmParserWorker() async {
  if (!kIsWeb) await _currentWorker.ready;
}

Future<R> dispatchParserInWorker<M, R>(
  ComputeCallback<M, R> callback,
  M message,
) => kIsWeb
    ? compute(callback, message)
    : _currentWorker.dispatch(callback, message);

class _ParserJob<M, R> {
  const _ParserJob(this.id, this.callback, this.message);

  final int id;
  final ComputeCallback<M, R> callback;
  final M message;

  FutureOr<R> run() => callback(message);
}

void _runParserWorker(SendPort reply) {
  final requests = ReceivePort();
  reply.send(requests.sendPort);
  requests.listen((message) async {
    final job = message as _ParserJob<Object?, Object?>;
    try {
      reply.send((job.id, await job.run()));
    } catch (error, stack) {
      try {
        reply.send((job.id, error, stack));
      } on ArgumentError {
        reply.send((
          job.id,
          RemoteError(error.toString(), stack.toString()),
          stack,
        ));
      }
    }
  });
}

class _ParserWorker {
  _ParserWorker() {
    _replies.handler = _receive;
    unawaited(_spawn());
  }

  final _replies = RawReceivePort();
  final _ready = Completer<SendPort>();
  final _pending = <int, Completer<Object?>>{};
  int _nextJob = 0;
  Object? _failure;

  Future<SendPort> get ready => _ready.future;

  Future<void> _spawn() async {
    try {
      final reply = _replies.sendPort;
      await Isolate.spawn(
        _runParserWorker,
        reply,
        onExit: reply,
        onError: reply,
        debugName: 'forum-parser',
      );
    } catch (error, stack) {
      _close(error, stack);
    }
  }

  void _receive(Object? message) {
    switch (message) {
      case final SendPort port:
        _ready.complete(port);
      case (final int id, final result):
        _pending.remove(id)?.complete(result);
      case (final int id, final Object error, final StackTrace stack):
        _pending.remove(id)?.completeError(error, stack);
      case [final String error, final String stack]:
        _close(RemoteError(error, stack));
      case null:
        _close(StateError('Forum parser isolate exited'));
    }
  }

  void _close(Object error, [StackTrace? stack]) {
    _failure = error;
    _replies.close();
    if (identical(_worker, this)) _worker = null;
    if (!_ready.isCompleted) _ready.completeError(error, stack);
    for (final job in _pending.values) {
      job.completeError(error, stack);
    }
    _pending.clear();
  }

  Future<R> dispatch<M, R>(ComputeCallback<M, R> callback, M message) async {
    final port = await ready;
    if (_failure case final error?) throw error;
    final id = ++_nextJob;
    final result = _pending[id] = Completer<Object?>();
    try {
      port.send(_ParserJob(id, callback, message));
      return (await result.future) as R;
    } finally {
      _pending.remove(id);
    }
  }
}
