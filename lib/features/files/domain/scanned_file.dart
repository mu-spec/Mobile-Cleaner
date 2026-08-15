import 'package:mobile_cleaner/features/files/domain/file_category.dart';

/// A single user-visible file discovered by the scanner.
///
/// This is the reusable model every later phase (Clean, Photos, Large Files,
/// Duplicates) builds on, so it stays free of Flutter and platform imports.
class ScannedFile {
  const ScannedFile({
    required this.id,
    required this.name,
    required this.path,
    required this.uri,
    required this.sizeBytes,
    required this.category,
    required this.dateModified,
    this.mimeType,
    this.relativePath,
  }) : assert(sizeBytes >= 0, 'sizeBytes cannot be negative');

  /// Stable identifier. MediaStore row id when available, otherwise the path.
  final String id;

  /// Display name including extension, e.g. `IMG_20240118.jpg`.
  final String name;

  /// Absolute filesystem path when the platform exposes one.
  final String path;

  /// Content URI usable for previewing or deleting, e.g.
  /// `content://media/external/images/media/1234`.
  final String uri;

  /// File size in bytes.
  final int sizeBytes;

  /// Category bucket the file was discovered in.
  final FileCategory category;

  /// Last modified timestamp reported by the platform.
  final DateTime dateModified;

  /// MIME type when known, e.g. `image/jpeg`.
  final String? mimeType;

  /// Bucket-relative path, e.g. `DCIM/Camera/`.
  final String? relativePath;

  /// True when Android will let this app delete the file.
  ///
  /// Deletion goes through either MediaStore or the Storage Access Framework,
  /// and both need a `content://` URI. A `file://` URI comes from the legacy
  /// pre-scoped-storage directory walk, and `ContentResolver.delete` cannot
  /// act on it, so offering Delete for one would fail at the platform.
  bool get isDeletable => uri.startsWith('content://');

  /// True when the platform can render a visual preview of this file.
  ///
  /// Only images and videos get thumbnails; everything else uses an icon.
  bool get supportsThumbnail =>
      category == FileCategory.images ||
      category == FileCategory.videos ||
      (mimeType?.startsWith('image/') ?? false) ||
      (mimeType?.startsWith('video/') ?? false);

  /// True when the file is an Android installer package.
  bool get isApk =>
      extension == 'apk' ||
      mimeType == 'application/vnd.android.package-archive';

  /// Lowercase extension without the dot, e.g. `jpg`. Empty when absent.
  String get extension {
    final int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  /// Folder that contains the file, derived from [relativePath] or [path].
  String get folderName {
    final String source = (relativePath != null && relativePath!.isNotEmpty)
        ? relativePath!
        : path;
    final List<String> parts = source
        .split('/')
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return category.label;
    }
    // Drop the file name itself when the source was a full path.
    if (parts.last == name && parts.length > 1) {
      return parts[parts.length - 2];
    }
    return parts.last;
  }

  ScannedFile copyWith({
    String? id,
    String? name,
    String? path,
    String? uri,
    int? sizeBytes,
    FileCategory? category,
    DateTime? dateModified,
    String? mimeType,
    String? relativePath,
  }) {
    return ScannedFile(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      uri: uri ?? this.uri,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      category: category ?? this.category,
      dateModified: dateModified ?? this.dateModified,
      mimeType: mimeType ?? this.mimeType,
      relativePath: relativePath ?? this.relativePath,
    );
  }

  /// Builds a model from the raw map returned by the Android bridge.
  ///
  /// Returns `null` when the row is unusable (no identity or no name), so a
  /// single malformed MediaStore row can never break an entire scan.
  static ScannedFile? fromPlatformMap(
    Map<Object?, Object?> map, {
    FileCategory? fallbackCategory,
  }) {
    final String path = _readString(map['path']) ?? '';
    final String uri = _readString(map['uri']) ?? '';
    if (path.isEmpty && uri.isEmpty) {
      return null;
    }

    String name = _readString(map['name']) ?? '';
    if (name.isEmpty && path.isNotEmpty) {
      name = path.split('/').last;
    }
    if (name.isEmpty) {
      return null;
    }

    final int sizeBytes = _readInt(map['sizeBytes']) ?? 0;
    final int millis = _readInt(map['dateModifiedMillis']) ?? 0;

    return ScannedFile(
      id: _readString(map['id']) ?? (uri.isNotEmpty ? uri : path),
      name: name,
      path: path,
      uri: uri.isNotEmpty ? uri : 'file://$path',
      sizeBytes: sizeBytes < 0 ? 0 : sizeBytes,
      category: map['category'] == null
          ? (fallbackCategory ?? FileCategory.other)
          : FileCategory.fromKey(_readString(map['category'])),
      dateModified: DateTime.fromMillisecondsSinceEpoch(
        millis > 0 ? millis : 0,
      ),
      mimeType: _readString(map['mimeType']),
      relativePath: _readString(map['relativePath']),
    );
  }

  static String? _readString(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScannedFile &&
          other.id == id &&
          other.uri == uri &&
          other.sizeBytes == sizeBytes);

  @override
  int get hashCode => Object.hash(id, uri, sizeBytes);

  @override
  String toString() =>
      'ScannedFile(name: $name, category: ${category.key}, '
      'sizeBytes: $sizeBytes)';
}
