/// Categories of user-visible files the scanner can discover.
///
/// The [key] value is the contract shared with the Android MediaStore bridge
/// and must stay in sync with `FileScannerBridge.kt`.
enum FileCategory {
  images('images', 'Images'),
  videos('videos', 'Videos'),
  audio('audio', 'Audio'),
  documents('documents', 'Documents'),
  downloads('downloads', 'Downloads'),
  other('other', 'Other');

  const FileCategory(this.key, this.label);

  final String key;
  final String label;

  static FileCategory fromKey(String? key) {
    return FileCategory.values.firstWhere(
      (FileCategory category) => category.key == key,
      orElse: () => FileCategory.other,
    );
  }

  /// Categories exposed to the user in the Files dashboard.
  static const List<FileCategory> scannable = <FileCategory>[
    FileCategory.images,
    FileCategory.videos,
    FileCategory.audio,
    FileCategory.documents,
    FileCategory.downloads,
  ];
}

/// Sort order requested from the native scanner.
enum FileSortOrder {
  sizeDesc('size_desc'),
  dateDesc('date_desc'),
  nameAsc('name_asc');

  const FileSortOrder(this.key);

  final String key;
}
