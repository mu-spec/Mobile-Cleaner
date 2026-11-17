import 'package:phone_storage_cleaner/features/cleaner/domain/scan_launch_target.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/permission_snapshot.dart';

/// A single route-to-capability policy, including deep links and tool shortcuts.
PermissionFeature? permissionFeatureFor(Uri location) =>
    switch (location.path) {
      '/scan-progress' => switch (ScanLaunchTarget.fromRouteValue(
        location.queryParameters['scan'],
      )) {
        ScanLaunchTarget.apps => PermissionFeature.none,
        ScanLaunchTarget.screenshots ||
        ScanLaunchTarget.photoCleanup => PermissionFeature.photos,
        ScanLaunchTarget.largeVideos => PermissionFeature.videos,
        _ => PermissionFeature.media,
      },
      '/photos' ||
      '/screenshot-cleaner' ||
      '/large-photos' ||
      '/photo-duplicates' ||
      '/similar-photos' => PermissionFeature.photos,
      '/videos' => PermissionFeature.videos,
      '/apps' => PermissionFeature.none,
      '/files' ||
      '/apk-cleaner' ||
      '/downloads-cleaner' => PermissionFeature.nonMedia,
      '/file-category' => switch (location.queryParameters['category']) {
        'images' => PermissionFeature.photos,
        'videos' => PermissionFeature.videos,
        'audio' => PermissionFeature.audio,
        _ => PermissionFeature.nonMedia,
      },
      '/large-files' || '/duplicates' || '/clean' => PermissionFeature.media,
      _ => null,
    };

/// Only local, recognized feature routes may be resumed after permission UI.
Uri? permissionDestination(String? raw) {
  if (raw == null) {
    return null;
  }
  final Uri? location = Uri.tryParse(raw);
  if (location == null ||
      location.hasScheme ||
      location.hasAuthority ||
      permissionFeatureFor(location) == null) {
    return null;
  }
  return location;
}
