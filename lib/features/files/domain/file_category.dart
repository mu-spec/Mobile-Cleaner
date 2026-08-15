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
  apks('apks', 'APKs'),
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

  /// Categories exposed to the user in the Files dashboard, in display order.
  static const List<FileCategory> scannable = <FileCategory>[
    FileCategory.images,
    FileCategory.videos,
    FileCategory.audio,
    FileCategory.documents,
    FileCategory.downloads,
    FileCategory.apks,
  ];

  /// Message shown when the category holds no files.
  String get emptyMessage => switch (this) {
    FileCategory.images => 'No images found',
    FileCategory.videos => 'No videos found',
    FileCategory.audio => 'No audio files found',
    FileCategory.documents => 'No documents found',
    FileCategory.downloads => 'No downloads found',
    FileCategory.apks => 'No APK files found',
    FileCategory.other => 'No other files found',
  };

  /// Short explanation shown under the category title.
  String get description => switch (this) {
    FileCategory.images => 'Photos, screenshots, and saved pictures',
    FileCategory.videos => 'Recordings, clips, and downloaded video',
    FileCategory.audio => 'Music, voice notes, and sound files',
    FileCategory.documents => 'PDFs, office files, text, and archives',
    FileCategory.downloads => 'Everything saved to your Downloads folder',
    FileCategory.apks => 'Installer packages that are safe to remove',
    FileCategory.other => 'Files that do not fit another category',
  };
}

/// How a category list is ordered in the UI.
enum FileListSort {
  largest('Largest', 'Largest first'),
  smallest('Smallest', 'Smallest first'),
  newest('Newest', 'Newest first'),
  oldest('Oldest', 'Oldest first'),
  name('Name', 'Name (A-Z)');

  const FileListSort(this.shortLabel, this.label);

  /// Compact label used in chips and menu rows.
  final String shortLabel;

  /// Descriptive label shown in the list header.
  final String label;
}

/// Sort order requested from the native scanner.
enum FileSortOrder {
  sizeDesc('size_desc'),
  dateDesc('date_desc'),
  nameAsc('name_asc');

  const FileSortOrder(this.key);

  final String key;
}
