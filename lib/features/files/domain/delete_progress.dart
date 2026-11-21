import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:phone_storage_cleaner/features/files/domain/delete_result.dart';
import 'package:phone_storage_cleaner/features/files/domain/scanned_file.dart';

/// One immutable view of confirmed outcomes, never a timer or byte estimate.
class DeleteProgressSnapshot {
  const DeleteProgressSnapshot({
    required this.total,
    this.deleted = const {},
    this.failed = const {},
    this.skipped = const {},
    this.confirmedBytes = 0,
    this.currentUri,
    this.phase = 'preparing',
    this.terminal = false,
    this.successful = false,
  });
  final int total;
  final Set<String> deleted;
  final Set<String> failed;
  final Set<String> skipped;
  final int confirmedBytes;
  final String? currentUri;
  final String phase;
  final bool terminal;
  final bool successful;
  int get processed => deleted.length + failed.length + skipped.length;
  double? get fraction => total > 0 ? processed / total : null;
}

/// UI-owned observation scope. Leaving a widget only detaches observation;
/// it cannot revoke Android consent or pretend to cancel an in-flight delete.
/// Custom/older repositories without telemetry remain at zero until their
/// real result resolves. They never need to implement a second deletion API.
class DeleteProgressOperation extends ChangeNotifier {
  DeleteProgressOperation(List<ScannedFile> files)
    : files = {for (final file in files) file.uri: file},
      id = 'delete-${++_nextId}' {
    snapshot = DeleteProgressSnapshot(total: this.files.length);
  }
  static int _nextId = 0;
  static final _zoneKey = Object();
  static DeleteProgressOperation? get current =>
      Zone.current[_zoneKey] as DeleteProgressOperation?;
  static const channel = MethodChannel(
    'com.KoreAppsTek.PhoneStorageCleaner/delete_progress',
  );
  static final Map<String, DeleteProgressOperation> _active = {};
  final String id;
  final Map<String, ScannedFile> files;
  late DeleteProgressSnapshot snapshot;
  bool _disposed = false;
  bool _finished = false;
  int _sequence = -1;
  Map<String, int> _sizes = {};
  DeleteResult failureResult(String reason) => DeleteResult(
    deletedFiles: [for (final uri in snapshot.deleted) files[uri]!],
    failures: [
      for (final uri in files.keys)
        if (!snapshot.deleted.contains(uri) && !snapshot.skipped.contains(uri))
          DeleteFailure(uri: uri, reason: reason),
    ],
    skippedUris: snapshot.skipped.toList(),
    confirmedBytesByUri: Map.unmodifiable(_sizes),
  );

  /// Reconcile even a custom repository's final batch against selected URIs.
  /// Failure wins over skip, which wins over success; one URI counts once.
  DeleteResult _reconcile(DeleteResult result) {
    final failures = {
      for (final failure in result.failures)
        if (files.containsKey(failure.uri)) failure.uri: failure,
    };
    final skipped = result.skippedUris.where(files.containsKey).toSet()
      ..removeAll(failures.keys);
    final deleted = <String, ScannedFile>{
      for (final file in result.deletedFiles)
        if (files.containsKey(file.uri) &&
            !failures.containsKey(file.uri) &&
            !skipped.contains(file.uri))
          file.uri: files[file.uri]!,
    };
    if (!result.userCancelled) {
      for (final uri in files.keys) {
        if (!deleted.containsKey(uri) &&
            !skipped.contains(uri) &&
            !failures.containsKey(uri)) {
          failures[uri] = DeleteFailure(
            uri: uri,
            reason: 'Deletion was not confirmed.',
          );
        }
      }
    }
    final sizes = result.confirmedBytesByUri;
    return DeleteResult(
      deletedFiles: deleted.values.toList(),
      failures: failures.values.toList(),
      skippedUris: skipped.toList(),
      userCancelled: result.userCancelled,
      confirmedBytesByUri: sizes == null
          ? null
          : {
              for (final uri in deleted.keys)
                if (sizes[uri] != null && sizes[uri]! >= 0) uri: sizes[uri]!,
            },
    );
  }

  Future<DeleteResult> run(Future<DeleteResult> Function() action) async {
    if (_disposed || _finished || _active.containsKey(id)) {
      throw StateError('A deletion observation scope can run only once.');
    }
    _active[id] = this;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'progress' && call.arguments is Map) {
        final event = (call.arguments as Map).cast<Object?, Object?>();
        _active[event['requestId']]?.accept(event);
      }
    });
    try {
      DeleteResult result;
      try {
        result = await runZoned(action, zoneValues: {_zoneKey: this});
      } catch (_) {
        result = failureResult('Deletion could not be confirmed.');
      }
      result = _reconcile(result);
      _finished = true;
      if (!_disposed) {
        snapshot = DeleteProgressSnapshot(
          total: files.length,
          deleted: Set.unmodifiable(
            result.deletedFiles.map((f) => f.uri).where(files.containsKey),
          ),
          failed: Set.unmodifiable(
            result.failures.map((f) => f.uri).where(files.containsKey),
          ),
          skipped: Set.unmodifiable(
            result.skippedUris.where(files.containsKey),
          ),
          confirmedBytes: result.freedBytes,
          terminal: true,
          phase: result.userCancelled
              ? 'cancelled'
              : result.isCompleteSuccess
              ? 'complete'
              : 'partial',
          successful: result.isCompleteSuccess,
        );
        notifyListeners();
      }
      return result;
    } finally {
      _active.remove(id);
    }
  }

  void accept(Map<Object?, Object?> event) {
    if (_disposed || _finished || event['requestId'] != id) return;
    final sequence = event['sequence'];
    final outcomes = event['outcomes'];
    final sizes = event['confirmedBytesByUri'];
    if (sequence is! int ||
        sequence <= _sequence ||
        outcomes is! Map ||
        sizes is! Map) {
      return;
    }
    final deleted = <String>{}, failed = <String>{}, skipped = <String>{};
    var bytes = 0;
    for (final entry in outcomes.entries) {
      if (!files.containsKey(entry.key)) return;
      switch (entry.value) {
        case 'deleted':
          deleted.add(entry.key as String);
          final size = sizes[entry.key];
          if (size != null && (size is! int || size < 0)) return;
          bytes += size is int ? size : 0;
        case 'failed':
          failed.add(entry.key as String);
        case 'skipped':
          skipped.add(entry.key as String);
        default:
          return;
      }
    }
    // Cumulative native evidence is append-only. Reject contradictory/replayed
    // callbacks rather than counting a URI twice or rewinding confirmed work.
    if (!deleted.containsAll(snapshot.deleted) ||
        !failed.containsAll(snapshot.failed) ||
        !skipped.containsAll(snapshot.skipped) ||
        bytes < snapshot.confirmedBytes) {
      return;
    }
    for (final entry in _sizes.entries) {
      if (sizes[entry.key] != entry.value) return;
    }
    _sequence = sequence;
    _sizes = {
      for (final uri in deleted)
        if (sizes[uri] is int) uri: sizes[uri] as int,
    };
    snapshot = DeleteProgressSnapshot(
      total: files.length,
      deleted: Set.unmodifiable(deleted),
      failed: Set.unmodifiable(failed),
      skipped: Set.unmodifiable(skipped),
      confirmedBytes: bytes,
      currentUri: files.containsKey(event['currentUri'])
          ? event['currentUri'] as String
          : null,
      phase: event['phase'] is String ? event['phase'] as String : 'deleting',
    );
    // A native terminal notification is not the method result. Do not declare
    // parent success or navigate until the actual repository future resolves.
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _active.remove(id);
    super.dispose();
  }
}
