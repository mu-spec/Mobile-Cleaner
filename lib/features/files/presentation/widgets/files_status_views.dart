import 'package:flutter/material.dart';
import 'package:mobile_cleaner/core/errors/app_failure.dart';

/// Shown while a scan is in flight.
class FilesScanningView extends StatelessWidget {
  const FilesScanningView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('files_scanning'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(
            'Scanning your files…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Reading names, sizes, and dates only.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when a scan fails, with a shortcut to permissions when relevant.
class FilesErrorView extends StatelessWidget {
  const FilesErrorView({
    required this.error,
    required this.onRetry,
    required this.onPermissions,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onPermissions;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AppFailure failure = AppFailure.from(error);

    return ListView(
      key: const Key('files_error'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: <Widget>[
        const SizedBox(height: 60),
        Icon(
          _iconFor(failure.kind),
          size: 52,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          _headlineFor(failure.kind),
          key: const Key('files_error_headline'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          failure.message,
          key: const Key('files_error_message'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (failure.technicalDetail != null) ...<Widget>[
          const SizedBox(height: 10),
          // Small print, but present: a screenshot of this screen should be
          // enough to diagnose the problem without asking for logcat.
          Text(
            failure.technicalDetail!,
            key: const Key('files_error_detail'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 20),
        if (failure.needsPermission)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('files_permission_button'),
              onPressed: onPermissions,
              icon: const Icon(Icons.shield_outlined),
              label: const Text('Review permissions'),
            ),
          ),
        // Retrying a permission problem or an unsupported feature would fail
        // identically, so the action is not offered.
        if (failure.isRetryable) ...<Widget>[
          const SizedBox(height: 10),
          TextButton.icon(
            key: const Key('files_retry_button'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ],
    );
  }

  static IconData _iconFor(FailureKind kind) => switch (kind) {
    FailureKind.permissionDenied => Icons.lock_outline_rounded,
    FailureKind.missingFile => Icons.search_off_rounded,
    FailureKind.deleteFailed => Icons.delete_forever_outlined,
    FailureKind.storageUnavailable => Icons.sd_card_alert_outlined,
    FailureKind.cancelled => Icons.cancel_outlined,
    FailureKind.unsupported => Icons.block_outlined,
    FailureKind.unknown => Icons.error_outline,
  };

  static String _headlineFor(FailureKind kind) => switch (kind) {
    FailureKind.permissionDenied => 'Storage access is required',
    FailureKind.missingFile => 'Those files have moved',
    FailureKind.deleteFailed => 'Nothing was removed',
    FailureKind.storageUnavailable => 'Storage unavailable',
    FailureKind.cancelled => 'Cancelled',
    FailureKind.unsupported => 'Not available here',
    FailureKind.unknown => 'We could not scan your files',
  };
}
