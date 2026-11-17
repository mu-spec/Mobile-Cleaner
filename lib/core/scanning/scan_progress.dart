import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ScanOutcome { running, succeeded, failed, cancelled, partial }

/// A measured stage is not an estimate of the parent operation's percentage.
class ScanStage {
  const ScanStage({
    required this.id,
    required this.name,
    this.processed = 0,
    this.total,
    this.unit = 'items checked',
    this.outcome = ScanOutcome.running,
  });
  final String id;
  final String name;
  final int processed;
  final int? total;
  final String unit;
  final ScanOutcome outcome;
  double? get fraction => total == null
      ? null
      : total! > 0
      ? processed / total!
      : outcome == ScanOutcome.succeeded
      ? 1
      : null;
  bool get complete =>
      fraction == 1 &&
      (outcome == ScanOutcome.running || outcome == ScanOutcome.succeeded);
  bool get terminal => outcome != ScanOutcome.running;
  String get description =>
      'Stage: $name · $processed${total == null ? '' : ' / $total'} $unit'
      '${complete ? ' · stage complete' : ''}';
}

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
    this.displayStage,
  });
  final String id;
  final String stage;
  final int processed;
  final int? total;
  final double? fraction;
  final ScanOutcome outcome;
  final String unit;
  final ScanStage? displayStage;
  bool get successful => outcome == ScanOutcome.succeeded;
  double? get stageFraction =>
      displayStage == null ? fraction : displayStage!.fraction;
  String? get stageDescription => displayStage?.description;
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
  // Legacy call-site hint only. Fractions now always belong to displayStage,
  // never to a weighted or aggregated whole-operation estimate.
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
  // Insertion order is the explicit deterministic branch priority. Stay on the
  // earliest active source, even if another branch delivers more events.
  final Map<String, ScanStage?> _sources = {};
  final Set<String> _finishedSources = {};
  final Map<String, int> _sequences = {};
  final Map<String, int> _ordinals = {};
  final Map<String, ScanStage> _nativeStages = {};
  String? _selectedSource;
  ScanStage? _displayStage;
  int _localStage = 0;

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
    _sources[child.id] = null;
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
        source: child.id,
        displayStage: event.displayStage,
        sourceFinished: event.outcome != ScanOutcome.running,
      );
    }

    if (child.snapshot.outcome == ScanOutcome.running) {
      receive(child.snapshot);
    } else {
      // Cached terminal results propagate status, never replay a completed arc.
      _finishedSources.add(child.id);
      if (!child.snapshot.successful) _incomplete = true;
    }
    _children.add(child.updates.listen(receive));
  }

  void stage(String label) {
    if (_closed) return;
    final source = '$id:local-${++_localStage}';
    // Local analysis follows awaited discovery/hashing. It is deliberately
    // unmeasured unless the algorithm supplies real completed/total counts.
    for (final key in _sources.keys.where(
      (key) => key.startsWith('$id:local-'),
    )) {
      _finishedSources.add(key);
    }
    _accept(
      label,
      0,
      null,
      'items checked',
      source: source,
      displayStage: ScanStage(id: source, name: label),
    );
  }

  void markIncomplete() {
    if (!_closed) _incomplete = true;
  }

  void acceptNative(Map<Object?, Object?> event, String requestId) {
    if (_closed ||
        event['requestId'] != requestId ||
        !_requests.any((request) => request.id == requestId) ||
        _finishedSources.contains(requestId))
      return;
    final processed = event['processed'];
    final total = event['total'];
    if (processed is! int ||
        processed < 0 ||
        (total != null && (total is! int || total < processed)))
      return;
    final sequence = event['sequence'];
    final ordinal = event['stageIndex'];
    if (sequence is! int ||
        sequence < 0 ||
        sequence <= (_sequences[requestId] ?? -1))
      return;
    if (ordinal is! int ||
        ordinal < 0 ||
        ordinal < (_ordinals[requestId] ?? -1))
      return;
    final name = event['stage'] is String
        ? event['stage']! as String
        : 'Scanning';
    final stageId = '$requestId:stage-$ordinal';
    final previous = _nativeStages[requestId];
    if (previous?.id == stageId &&
        (processed < previous!.processed ||
            previous.name != name ||
            (previous.total != null && previous.total != total)))
      return;
    final outcome = switch (event['outcome']) {
      'succeeded' || 'stageComplete' => ScanOutcome.succeeded,
      'failed' => ScanOutcome.failed,
      'cancelled' => ScanOutcome.cancelled,
      'partial' => ScanOutcome.partial,
      _ => ScanOutcome.running,
    };
    if (previous?.id == stageId && previous!.terminal) return;
    _sequences[requestId] = sequence;
    _ordinals[requestId] = ordinal;
    if (outcome == ScanOutcome.failed ||
        outcome == ScanOutcome.partial ||
        outcome == ScanOutcome.cancelled)
      _incomplete = true;
    final measured = ScanStage(
      id: stageId,
      name: name,
      processed: processed,
      total: total as int?,
      unit: event['unit'] is String
          ? event['unit']! as String
          : 'items checked',
      outcome: outcome,
    );
    _nativeStages[requestId] = measured;
    _accept(
      name,
      processed,
      measured.total,
      measured.unit,
      source: requestId,
      displayStage: measured,
      sourceFinished:
          outcome != ScanOutcome.running && event['outcome'] != 'stageComplete',
    );
  }

  void _selectStage(String source, ScanStage? stage, bool finished) {
    final wasSelected =
        _selectedSource == source ||
        (_selectedSource == null && _displayStage == null);
    _sources.putIfAbsent(source, () => null);
    _sources[source] =
        stage ?? ScanStage(id: '$source:pending', name: 'Discovering');
    if (finished) _finishedSources.add(source);
    if (_selectedSource == null || _finishedSources.contains(_selectedSource)) {
      final active = _sources.keys.where(
        (key) => !_finishedSources.contains(key),
      );
      _selectedSource = active.isEmpty ? null : active.first;
    }
    if (_selectedSource != null) {
      _displayStage = _sources[_selectedSource];
    } else if (wasSelected || _displayStage?.id == stage?.id) {
      _displayStage = stage;
    }
  }

  void endRequest(String requestId) {
    if (_closed) return;
    final stage = _nativeStages[requestId];
    _selectStage(requestId, stage, true);
    _publish();
  }

  void _publish() {
    snapshot = ScanSnapshot(
      id: id,
      stage: _displayStage?.name ?? 'Discovering',
      processed: _displayStage?.processed ?? 0,
      total: _displayStage?.total,
      unit: _displayStage?.unit ?? 'items checked',
      fraction: _displayStage?.fraction,
      displayStage: _displayStage,
    );
    _updates.add(snapshot);
  }

  void _accept(
    String stage,
    int processed,
    int? total,
    String unit, {
    String? source,
    ScanStage? displayStage,
    bool sourceFinished = false,
  }) {
    if (source != null) _selectStage(source, displayStage, sourceFinished);
    snapshot = ScanSnapshot(
      id: id,
      displayStage: _displayStage,
      stage: _displayStage?.name ?? stage,
      processed: _displayStage?.processed ?? processed,
      total: _displayStage == null ? total : _displayStage!.total,
      unit: _displayStage?.unit ?? unit,
      fraction: _displayStage?.fraction,
    );
    _updates.add(snapshot);
  }

  void _finish(ScanOutcome outcome) {
    _closed = true;
    for (final request in _requests.toList()) {
      request.close();
    }
    snapshot = ScanSnapshot(
      id: id,
      stage: outcome == ScanOutcome.succeeded
          ? 'Scan complete'
          : snapshot.stage,
      processed: snapshot.processed,
      total: snapshot.total,
      unit: snapshot.unit,
      fraction: outcome == ScanOutcome.succeeded ? 1 : _displayStage?.fraction,
      displayStage: _displayStage,
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
    if (_closed) {
      throw PlatformException(
        code: 'SCAN_CANCELLED',
        message: 'Scan no longer owns this work.',
      );
    }
    final request = NativeScanRequest._(this);
    _sources[request.id] = ScanStage(
      id: '${request.id}:pending',
      name: 'Discovering',
    );
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
    if (_closed) return;
    _closed = true;
    _active.remove(id);
    operation._requests.remove(this);
    operation.endRequest(id);
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
        if (request != null && payload['scanStage'] is Map) {
          operation?.acceptNative(
            (payload['scanStage'] as Map).cast<Object?, Object?>(),
            request.id,
          );
        }
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
