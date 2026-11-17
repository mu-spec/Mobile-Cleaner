import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phone_storage_cleaner/features/files/domain/delete_result.dart';
import 'package:phone_storage_cleaner/features/files/domain/delete_progress.dart';
import 'package:phone_storage_cleaner/features/files/domain/scanned_file.dart';

/// Deletes files the user selected and confirmed.
///
/// Implementations must never delete without the caller having confirmed
/// first, and must report partial outcomes honestly.
abstract interface class DeleteRepository {
  Future<DeleteResult> deleteFiles(List<ScannedFile> files);
}

final Provider<DeleteRepository> deleteRepositoryProvider =
    Provider<DeleteRepository>((ref) => PlatformDeleteRepository());

class PlatformDeleteRepository implements DeleteRepository {
  PlatformDeleteRepository({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName =
      'com.KoreAppsTek.PhoneStorageCleaner/delete';

  final MethodChannel _channel;

  @override
  Future<DeleteResult> deleteFiles(List<ScannedFile> files) async {
    if (files.isEmpty) {
      return const DeleteResult(
        deletedFiles: <ScannedFile>[],
        failures: <DeleteFailure>[],
      );
    }

    try {
      final Map<Object?, Object?>? payload = await _channel
          .invokeMapMethod<Object?, Object?>('deleteFiles', <String, Object>{
            if (DeleteProgressOperation.current != null)
              'progressId': DeleteProgressOperation.current!.id,
            'uris': files
                .map((ScannedFile file) => file.uri)
                .toList(growable: false),
            // Diagnostics only. The native side logs these under
            // [DELETE_DEBUG]; deletion still routes purely on the URI.
            'debugItems': files
                .map(
                  (ScannedFile file) => <String, Object?>{
                    'uri': file.uri,
                    'category': file.category.key,
                    'path': file.path,
                    'name': file.name,
                    'sizeBytes': file.sizeBytes,
                    'mimeType': file.mimeType,
                  },
                )
                .toList(growable: false),
          });

      if (payload == null) {
        return _allFailed(files, 'The delete service did not respond.');
      }
      return parseResult(payload, files);
    } on PlatformException catch (error) {
      return _allFailed(files, error.message ?? 'Delete failed.');
    } on MissingPluginException {
      return _allFailed(files, 'Deleting is not available on this device.');
    }
  }

  /// Maps the platform payload back onto the selected files.
  ///
  /// Exposed for testing.
  static DeleteResult parseResult(
    Map<Object?, Object?> payload,
    List<ScannedFile> requested,
  ) {
    final Map<String, ScannedFile> byUri = <String, ScannedFile>{
      for (final ScannedFile file in requested) file.uri: file,
    };

    final Set<String> deletedUris = <String>{};
    final Object? rawDeleted = payload['deletedUris'];
    if (rawDeleted is List<Object?>) {
      for (final Object? uri in rawDeleted) {
        if (uri is String && uri.isNotEmpty) {
          deletedUris.add(uri);
        }
      }
    }

    final List<DeleteFailure> failures = <DeleteFailure>[];
    final Object? rawFailed = payload['failed'];
    if (rawFailed is List<Object?>) {
      for (final Object? entry in rawFailed) {
        if (entry is! Map<Object?, Object?>) {
          continue;
        }
        final Object? uri = entry['uri'];
        if (uri is! String ||
            uri.isEmpty ||
            !byUri.containsKey(uri) ||
            failures.any((failure) => failure.uri == uri)) {
          continue;
        }
        // A URI reported both deleted and failed is treated as failed, which
        // is the safer reading: never claim a file is gone when unsure.
        deletedUris.remove(uri);
        final Object? reason = entry['reason'];
        failures.add(
          DeleteFailure(
            uri: uri,
            reason: reason is String && reason.isNotEmpty
                ? reason
                : 'Could not delete this file.',
          ),
        );
      }
    }

    final skipped = <String>{};
    final rawSkipped = payload['skippedUris'];
    if (rawSkipped is List) {
      skipped.addAll(rawSkipped.whereType<String>().where(byUri.containsKey));
    }
    // An absent/skipped item is not a successful cleaning, even in a
    // contradictory platform payload. Unknown requested outcomes fail closed.
    deletedUris.removeAll(skipped);
    final reportedFailures = failures.map((f) => f.uri).toSet();
    skipped.removeAll(reportedFailures);
    deletedUris.retainWhere(byUri.containsKey);
    for (final uri in byUri.keys) {
      if (!deletedUris.contains(uri) &&
          !skipped.contains(uri) &&
          !reportedFailures.contains(uri) &&
          payload['userCancelled'] != true) {
        failures.add(
          DeleteFailure(uri: uri, reason: 'Deletion was not confirmed.'),
        );
      }
    }
    final Map<String, int>? confirmedSizes = payload['accountingVersion'] == 1
        ? {}
        : null;
    final sizes = payload['confirmedBytesByUri'];
    if (confirmedSizes != null && sizes is Map) {
      for (final uri in deletedUris) {
        final size = sizes[uri];
        if (size is int && size >= 0) confirmedSizes[uri] = size;
      }
    }
    final List<ScannedFile> deletedFiles = <ScannedFile>[
      for (final String uri in deletedUris)
        if (byUri[uri] != null) byUri[uri]!,
    ];

    return DeleteResult(
      deletedFiles: deletedFiles,
      failures: failures,
      userCancelled: payload['userCancelled'] == true,
      skippedUris: skipped.toList(growable: false),
      confirmedBytesByUri: confirmedSizes,
    );
  }

  DeleteResult _allFailed(List<ScannedFile> files, String reason) {
    final operation = DeleteProgressOperation.current;
    if (operation != null) return operation.failureResult(reason);
    return DeleteResult(
      deletedFiles: const <ScannedFile>[],
      failures: <DeleteFailure>[
        for (final ScannedFile file in files)
          DeleteFailure(uri: file.uri, reason: reason),
      ],
    );
  }
}
