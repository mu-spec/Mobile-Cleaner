import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// A short, reportable description of what actually went wrong.
  ///
  /// `PlatformException.toString()` is long and starts with noise, so the
  /// message and details are preferred when present.
  static String _describe(Object error) {
    if (error is PlatformException) {
      final String detail = error.details is String
          ? error.details as String
          : '';
      final String message = error.message ?? '';
      final String body = <String>[
        message,
        detail,
      ].where((String part) => part.isNotEmpty).join(' — ');
      return body.isEmpty ? error.code : '${error.code}: $body';
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final bool permissionIssue = error.toString().contains('PERMISSION');
    return ListView(
      key: const Key('files_error'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: <Widget>[
        const SizedBox(height: 60),
        Icon(
          permissionIssue ? Icons.lock_outline_rounded : Icons.error_outline,
          size: 52,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          permissionIssue
              ? 'Storage access is required'
              : 'We could not scan your files',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        // The underlying reason, so a user can report something actionable
        // instead of just a screenshot of the headline.
        Text(
          _describe(error),
          key: const Key('files_error_detail'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (permissionIssue)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('files_permission_button'),
              onPressed: onPermissions,
              icon: const Icon(Icons.shield_outlined),
              label: const Text('Review permissions'),
            ),
          ),
        const SizedBox(height: 10),
        TextButton.icon(
          key: const Key('files_retry_button'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
