import 'package:phone_storage_cleaner/features/permissions/domain/app_permission_status.dart';

/// Runtime capabilities are deliberately separate from persisted SAF grants.
enum PermissionKind { storage, photos, videos, audio }

enum PermissionFeature { none, photos, videos, audio, media, nonMedia }

class PermissionSnapshot {
  PermissionSnapshot({
    required this.sdkInt,
    required Map<PermissionKind, AppPermissionStatus> statuses,
    Set<String> folderUris = const <String>{},
  }) : statuses = Map<PermissionKind, AppPermissionStatus>.unmodifiable(
         statuses,
       ),
       folderUris = Set<String>.unmodifiable(folderUris);

  final int sdkInt;
  final Map<PermissionKind, AppPermissionStatus> statuses;

  /// Actual persisted Android tree grants, not unrestricted storage access.
  final Set<String> folderUris;

  Set<PermissionKind> requiredFor(PermissionFeature feature) {
    if (feature == PermissionFeature.none ||
        (feature == PermissionFeature.nonMedia && sdkInt >= 29)) {
      // Scoped non-media tools can read their visible MediaStore rows and
      // explicitly granted SAF trees. READ_MEDIA_* cannot expand that scope.
      return const <PermissionKind>{};
    }
    if (sdkInt < 33) {
      return const <PermissionKind>{PermissionKind.storage};
    }
    return switch (feature) {
      PermissionFeature.photos => const <PermissionKind>{PermissionKind.photos},
      PermissionFeature.videos => const <PermissionKind>{PermissionKind.videos},
      PermissionFeature.audio => const <PermissionKind>{PermissionKind.audio},
      PermissionFeature.media => const <PermissionKind>{
        PermissionKind.photos,
        PermissionKind.videos,
        PermissionKind.audio,
      },
      PermissionFeature.none ||
      PermissionFeature.nonMedia => const <PermissionKind>{},
    };
  }

  AppPermissionStatus statusOf(PermissionKind kind) =>
      statuses[kind] ?? AppPermissionStatus.denied;

  bool allows(PermissionKind kind) {
    final AppPermissionStatus status = statusOf(kind);
    return status == AppPermissionStatus.granted ||
        (status == AppPermissionStatus.limited &&
            (kind == PermissionKind.photos || kind == PermissionKind.videos));
  }

  Set<PermissionKind> missingFor(PermissionFeature feature) => <PermissionKind>{
    for (final PermissionKind kind in requiredFor(feature))
      if (!allows(kind)) kind,
  };

  bool allowsFeature(PermissionFeature feature) =>
      missingFor(feature).isEmpty ||
      // General discovery can show the accessible subset. This is not a
      // full-storage grant: missing media kinds and SAF scope stay explicit.
      (feature == PermissionFeature.media &&
          (requiredFor(feature).any(allows) ||
              (sdkInt >= 29 && folderUris.isNotEmpty)));

  AppPermissionStatus statusFor(PermissionFeature feature) {
    final Set<PermissionKind> missing = missingFor(feature);
    if (missing.isEmpty) {
      return requiredFor(feature).any(
            (PermissionKind kind) =>
                statusOf(kind) == AppPermissionStatus.limited,
          )
          ? AppPermissionStatus.limited
          : AppPermissionStatus.granted;
    }
    if (allowsFeature(feature)) {
      return AppPermissionStatus.limited;
    }
    // Still offer requestable capabilities, even if another is blocked.
    if (missing.any(
      (PermissionKind kind) => statusOf(kind) == AppPermissionStatus.denied,
    )) {
      return AppPermissionStatus.denied;
    }
    if (missing.any(
      (PermissionKind kind) =>
          statusOf(kind) == AppPermissionStatus.permanentlyDenied,
    )) {
      return AppPermissionStatus.permanentlyDenied;
    }
    return AppPermissionStatus.restricted;
  }

  @override
  bool operator ==(Object other) =>
      other is PermissionSnapshot &&
      sdkInt == other.sdkInt &&
      statuses.length == other.statuses.length &&
      statuses.entries.every(
        (entry) => other.statuses[entry.key] == entry.value,
      ) &&
      folderUris.length == other.folderUris.length &&
      folderUris.every(other.folderUris.contains);

  @override
  int get hashCode => Object.hash(
    sdkInt,
    Object.hashAllUnordered(
      statuses.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAllUnordered(folderUris),
  );
}
