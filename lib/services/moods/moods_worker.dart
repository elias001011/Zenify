import 'dart:async';
import 'dart:isolate';

/// A background reading whose owner no longer wants its answer.
class MoodsCancelled implements Exception {
  const MoodsCancelled();
}

/// Owns the isolates used for catalog readings. Cancelling also stops their
/// HTTP clients, rather than letting a hidden feature finish a hundred reads.
class MoodsWorker {
  final _jobs = <_Job<dynamic>>{};

  Future<T> run<T>(Future<T> Function() task) {
    final job = _Job<T>();
    _jobs.add(job);
    job.port.listen((message) {
      if (job.result.isCompleted) return;
      if (message is (bool, Object?)) {
        if (message.$1) {
          job.result.complete(message.$2 as T);
        } else {
          job.result.completeError(StateError('${message.$2}'));
        }
      } else {
        job.result.completeError(StateError('Moods worker exited: $message'));
      }
    });
    unawaited(_start(job, task));
    return job.result.future.whenComplete(() {
      _jobs.remove(job);
      job.port.close();
      job.isolate?.kill(priority: Isolate.immediate);
    });
  }

  Future<void> _start<T>(_Job<T> job, Future<T> Function() task) async {
    try {
      final isolate = await Isolate.spawn(
        _work<T>,
        (task: task, output: job.port.sendPort),
        paused: true,
        onError: job.port.sendPort,
        onExit: job.port.sendPort,
      );
      job.isolate = isolate;
      if (job.result.isCompleted) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        isolate.resume(isolate.pauseCapability!);
      }
    } catch (error, stack) {
      if (!job.result.isCompleted) job.result.completeError(error, stack);
    }
  }

  void cancel() {
    for (final job in _jobs.toList()) {
      job.isolate?.kill(priority: Isolate.immediate);
      if (!job.result.isCompleted) {
        job.result.completeError(const MoodsCancelled());
      }
    }
  }
}

class _Job<T> {
  final port = ReceivePort();
  final result = Completer<T>();
  Isolate? isolate;
}

Future<void> _work<T>(
  ({Future<T> Function() task, SendPort output}) work,
) async {
  try {
    Isolate.exit(work.output, (true, await work.task()));
  } catch (error) {
    work.output.send((false, error.toString()));
  }
}
