import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ScanOutcome { running, succeeded, failed, cancelled, partial }

/// Counts describe a stage, not an invented percentage of a composite scan.
class ScanSnapshot {
  const ScanSnapshot({
    required this.id,
    this.stage = 'Discovering',
    this.processed = 0,
    this.total,
    this.fraction,
    this.outcome = ScanOutcome.running,
    this.unit = 'items checked',
  });
  final String id;
  final String stage;
  final int processed;
  final int? total;
  final double? fraction;
  final ScanOutcome outcome;
  final String unit;
  bool get successful => outcome == ScanOutcome.succeeded;
}

final scanProgressRegistryProvider = Provider<ScanProgressRegistry>((ref) {
  final registry = ScanProgressRegistry();
  ref.onDispose(registry.dispose);
  return registry;
});
final scanProgressProvider = StreamProvider.family<ScanSnapshot, String>((
  ref,
  key,
) {
  return ref.watch(scanProgressRegistryProvider).watch(key);
});

/// The provider owns its work, not a screen that may share its cached future.
/// Invalidating/disposing that provider cancels its requests. A departing screen
/// only detaches its own presentation scope, never another consumer's work.
Future<T> observeScan<T>(
  Ref ref,
  String key,
  Future<T> Function() action, {
  bool numeric = false,
}) {
  final operation = ref
      .read(scanProgressRegistryProvider)
      .begin(key, numeric: numeric);
  ref.onDispose(operation.cancel);
  return operation.run(action);
}

/// Attach cached/in-flight provider work too, not only newly built providers.
/// This keeps a second consumer from treating another consumer's partial
/// discovery as a successful scan just because its Future resolved normally.
Future<T> scanDependency<T>(Ref ref, String key, Future<T> future) {
  final child = ref.read(scanProgressRegistryProvider)._current[key];
  if (child != null) ScanOperation.current?._attach(child);
  return future;
}

class ScanProgressRegistry {
  final Map<String, ScanOperation> _current = {};
  final StreamController<String> _changes = StreamController<String>.broadcast(
    sync: true,
  );
  bool _disposed = false;
  ScanOperation begin(String key, {bool numeric = false}) {
    final operation = ScanOperation(numeric: numeric);
    // A replacement generation must not receive the previous run's events.
    _current[key] = operation;
    operation.updates.listen((_) {
      if (!_disposed) _changes.add(key);
    });
    if (!_disposed) _changes.add(key);
    return operation;
  }

  void attachCurrent(String key) {
    final child = _current[key];
    if (child != null) ScanOperation.current?._attach(child);
  }

  Stream<ScanSnapshot> watch(String key) => Stream<ScanSnapshot>.multi((sink) {
    final subscription = _changes.stream.listen((changed) {
      if (changed == key && _current[key] != null) {
        sink.add(_current[key]!.snapshot);
      }
    }, onDone: sink.close);
    if (_current[key] != null) sink.add(_current[key]!.snapshot);
    sink.onCancel = subscription.cancel;
  });
  void dispose() {
    _disposed = true;
    for (final operation in _current.values) {
      operation.cancel();
    }
    unawaited(_changes.close());
  }
}

class ScanOperation {
  ScanOperation({this.numeric = false}) : id = 'scan-${++_nextId}' {
    snapshot = ScanSnapshot(id: id);
  }
  static int _nextId = 0;
  static final Object _zoneKey = Object();
  static ScanOperation? get current => Zone.current[_zoneKey] as ScanOperation?;
  final String id;
  final bool numeric;
  late ScanSnapshot snapshot;
  final StreamController<ScanSnapshot> _updates =
      StreamController<ScanSnapshot>.broadcast(sync: true);
  Stream<ScanSnapshot> get updates => _updates.stream;
  final Set<NativeScanRequest> _requests = {};
  final List<StreamSubscription<ScanSnapshot>> _children = [];
  final Set<String> _attached = {};
  bool _closed = false;
  bool _incomplete = false;
  double? _confirmed;
  String? _numericSource;

  Future<T> run<T>(Future<T> Function() action) async {
    final parent = current;
    if (parent != null && parent != this) parent._attach(this);
    try {
      final T value = await runZoned(action, zoneValues: {_zoneKey: this});
      if (!_closed) {
        _finish(_incomplete ? ScanOutcome.partial : ScanOutcome.succeeded);
      }
      return value;
    } catch (_) {
      if (!_closed) _finish(ScanOutcome.failed);
      rethrow;
    }
  }

  void _attach(ScanOperation child) {
    if (_closed || identical(child, this) || !_attached.add(child.id)) return;
    void receive(ScanSnapshot event) {
      if (_closed) return;
      if (event.outcome == ScanOutcome.failed ||
          event.outcome == ScanOutcome.partial ||
          event.outcome == ScanOutcome.cancelled) {
        _incomplete = true;
      }
      _accept(
        event.successful ? 'Waiting for remaining scan work' : event.stage,
        event.processed,
        event.total,
        event.unit,
        fraction: event.fraction,
        source: child.id,
      );
    }

    receive(child.snapshot);
    _children.add(child.updates.listen(receive));
  }

  void stage(String label) {
    if (!_closed) _accept(label, 0, null, 'items checked');
  }

  void markIncomplete() {
    if (!_closed) _incomplete = true;
  }

  void acceptNative(Map<Object?, Object?> event, String requestId) {
    if (_closed || event['requestId'] != requestId) return;
    final processed = event['processed'];
    final total = event['total'];
    if (processed is! int ||
        processed < 0 ||
        (total != null && (total is! int || total < processed))) {
      return;
    }
    if (event['outcome'] == 'failed' ||
        event['outcome'] == 'partial' ||
        event['outcome'] == 'cancelled') {
      _incomplete = true;
    }
    final double? fraction =
        event['numeric'] == true && total is int && total > 0
        ? processed / total
        : null;
    _accept(
      event['stage'] is String ? event['stage']! as String : 'Scanning',
      processed,
      total as int?,
      event['unit'] is String ? event['unit']! as String : 'items checked',
      fraction: fraction,
      source: requestId,
    );
  }

  void _accept(
    String stage,
    int processed,
    int? total,
    String unit, {
    double? fraction,
    String? source,
  }) {
    // Only explicitly single-worklist operations can use a stage fraction.
    // Never average stages or let a completed child finish its parent.
    if (numeric &&
        fraction != null &&
        fraction.isFinite &&
        fraction >= 0 &&
        fraction < 1) {
      _numericSource ??= source;
      if (_numericSource == source &&
          (_confirmed == null || fraction > _confirmed!)) {
        _confirmed = fraction;
      }
    }
    snapshot = ScanSnapshot(
      id: id,
      stage: stage,
      processed: processed,
      total: total,
      unit: unit,
      fraction: _confirmed,
    );
    _updates.add(snapshot);
  }

  void _finish(ScanOutcome outcome) {
    _closed = true;
    snapshot = ScanSnapshot(
      id: id,
      stage: outcome == ScanOutcome.succeeded
          ? 'Scan complete'
          : snapshot.stage,
      processed: snapshot.processed,
      total: snapshot.total,
      unit: snapshot.unit,
      fraction: outcome == ScanOutcome.succeeded ? 1 : _confirmed,
      outcome: outcome,
    );
    _updates.add(snapshot);
    for (final subscription in _children) {
      unawaited(subscription.cancel());
    }
    _children.clear();
    unawaited(_updates.close());
  }

  void cancel() {
    if (_closed) return;
    for (final request in _requests.toList()) {
      request.cancel();
    }
    _finish(ScanOutcome.cancelled);
  }

  NativeScanRequest request() {
    final request = NativeScanRequest._(this);
    if (_closed) {
      throw PlatformException(
        code: 'SCAN_CANCELLED',
        message: 'Scan no longer owns this work.',
      );
    }
    _requests.add(request);
    return request;
  }
}

/// One engine-wide handler multiplexes independent request IDs. No event can
/// update a replaced session, including messages queued before cancellation.
class NativeScanRequest {
  NativeScanRequest._(this.operation)
    : id = '${operation.id}-request-${++_nextId}' {
    _ensureHandler();
    _active[id] = this;
  }
  static int _nextId = 0;
  static const channel = MethodChannel(
    'com.KoreAppsTek.PhoneStorageCleaner/scan_progress',
  );
  static final Map<String, NativeScanRequest> _active = {};
  final ScanOperation operation;
  final String id;
  bool _closed = false;
  static void _ensureHandler() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'progress' && call.arguments is Map) {
        final event = (call.arguments as Map).cast<Object?, Object?>();
        final request = _active[event['requestId']];
        if (request != null && !request._closed) {
          request.operation.acceptNative(event, request.id);
        }
      }
    });
  }

  void close() {
    _closed = true;
    _active.remove(id);
    operation._requests.remove(this);
  }

  void cancel() {
    close();
    unawaited(
      channel
          .invokeMethod<void>('cancel', {'requestId': id})
          .catchError((Object _) {}),
    );
  }

  static Future<Map<Object?, Object?>?> invokeMap(
    MethodChannel transport,
    String method,
    Map<String, Object> arguments,
  ) async {
    final operation = ScanOperation.current;
    final request = operation?.request();
    try {
      final payload = await transport.invokeMapMethod<Object?, Object?>(
        method,
        {...arguments, if (request != null) 'progressId': request.id},
      );
      if (payload == null) operation?.markIncomplete();
      if (payload != null && payload.containsKey('scanOutcome')) {
        if (payload['scanOutcome'] != 'succeeded') operation?.markIncomplete();
        final result = payload['scanPayload'];
        if (result is! Map) {
          operation?.markIncomplete();
          return null;
        }
        return result.cast<Object?, Object?>();
      }
      return payload;
    } catch (_) {
      operation?.markIncomplete();
      rethrow;
    } finally {
      request?.close();
    }
  }
}
