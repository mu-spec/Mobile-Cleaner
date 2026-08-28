import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/navigation/root_back_button.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/file_scan_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/category_files_screen.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_category_card.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/folder_access_banner.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Files tab: folder access, real categories, then cleanup shortcuts.
class FilesScreen extends ConsumerWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<FileScanResult> scan = ref.watch(fileScanProvider);
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Scaffold(
      key: const Key('files_screen'),
      appBar: AppBar(
        toolbarHeight: 60,
        leading: const RootBackButton(buttonKey: Key('files_back_button')),
        titleSpacing: 4,
        title: Text(
          'Files',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(fileScanProvider);
            await ref.read(fileScanProvider.future);
          },
          child: scan.when(
            loading: () => const FilesScanningView(),
            error: (Object error, StackTrace stackTrace) => FilesErrorView(
              error: error,
              onRetry: () => ref.invalidate(fileScanProvider),
              onPermissions: () => context.push(AppRoutes.permissions),
            ),
            data: (FileScanResult result) => _FilesOverview(result: result),
          ),
        ),
      ),
    );
  }
}

class _FilesOverview extends StatelessWidget {
  const _FilesOverview({required this.result});

  final FileScanResult result;

  void _openCategory(BuildContext context, FileCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryFilesScreen(category: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool nothingFound = result.isEmpty;

    return ListView(
      key: const Key('files_overview'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        // Deliberately always available: users can grant another useful
        // folder even after Android no longer marks the grant as required.
        const FolderAccessBanner(),
        const SizedBox(height: 22),
        _SectionTitle(
          key: const Key('files_categories_section'),
          title: 'Categories',
          subtitle: 'Tap a category to review its files.',
        ),
        const SizedBox(height: 12),
        GridView.count(
          key: const Key('files_category_grid'),
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.12,
          children: <Widget>[
            for (final FileCategory category in FileCategory.scannable)
              FileCategoryCard(
                summary: result.summaryFor(category),
                onTap: () => _openCategory(context, category),
              ),
          ],
        ),
        const SizedBox(height: 22),
        _DeviceFilesSummary(result: result),
        const SizedBox(height: 12),
        const _FileToolsCard(),
        if (nothingFound) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            'Grant media or folder access, then pull down to scan again.',
            key: const Key('files_empty_hint'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (!nothingFound) ...<Widget>[
          const SizedBox(height: 24),
          _SectionTitle(
            title: 'Largest files',
            subtitle: 'Review the biggest items found on this phone.',
          ),
          const SizedBox(height: 8),
          for (final ScannedFile file in result.largestFiles(limit: 10))
            ScannedFileTile(file: file),
        ],
        if (result.truncated) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            'Showing the top results per category. Rescan after cleaning to '
            'see more.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.35,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _DeviceFilesSummary extends StatelessWidget {
  const _DeviceFilesSummary({required this.result});

  final FileScanResult result;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final bool empty = result.isEmpty;

    return Container(
      key: const Key('files_summary_card'),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
        boxShadow: <BoxShadow>[
          if (!isDark)
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  empty ? 'No files found' : 'Files on this phone',
                  key: const Key('files_summary_title'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  empty
                      ? 'Ready for a new scan'
                      : '${result.totalFiles} files · '
                            '${ByteFormatter.format(result.totalBytes)}',
                  key: const Key('files_summary_value'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.actionBlue.withValues(alpha: 0.15)
                  : AppColors.softBlue,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Center(
              child: PhosphorIcon(
                empty
                    ? PhosphorIconsDuotone.folderDashed
                    : PhosphorIconsDuotone.chartDonut,
                size: 25,
                color: empty
                    ? theme.colorScheme.onSurfaceVariant
                    : AppColors.actionBlue,
                duotoneSecondaryColor: empty
                    ? theme.colorScheme.onSurfaceVariant
                    : AppColors.cleanupOrange,
                duotoneSecondaryOpacity: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileToolsCard extends StatelessWidget {
  const _FileToolsCard();

  static const List<_FileTool> _tools = <_FileTool>[
    _FileTool(
      keyName: 'open_large_files',
      title: 'Large Files',
      subtitle: 'Find your biggest space users',
      route: AppRoutes.largeFiles,
      icon: PhosphorIconsDuotone.gauge,
      foreground: Color(0xFF245FCE),
      secondary: Color(0xFF8CB8FF),
      background: Color(0xFFEAF2FF),
    ),
    _FileTool(
      keyName: 'open_downloads_cleaner',
      title: 'Downloads Cleaner',
      subtitle: 'Clear out old downloads',
      route: AppRoutes.downloadsCleaner,
      icon: PhosphorIconsDuotone.broom,
      foreground: Color(0xFF315FC1),
      secondary: Color(0xFF92B5FA),
      background: Color(0xFFEDF3FF),
    ),
    _FileTool(
      keyName: 'open_apk_cleaner',
      title: 'APK Cleaner',
      subtitle: 'Remove leftover installers',
      route: AppRoutes.apkCleaner,
      icon: PhosphorIconsDuotone.androidLogo,
      foreground: Color(0xFFF07C08),
      secondary: Color(0xFFFFC46F),
      background: Color(0xFFFFF0DC),
    ),
    _FileTool(
      keyName: 'open_videos',
      title: 'Videos',
      subtitle: 'Manage large videos',
      route: AppRoutes.videos,
      icon: PhosphorIconsDuotone.filmSlate,
      foreground: Color(0xFFE54555),
      secondary: Color(0xFFFFA0AD),
      background: Color(0xFFFFEAED),
    ),
    _FileTool(
      keyName: 'open_duplicates',
      title: 'Duplicates',
      subtitle: 'Find byte-identical copies',
      route: AppRoutes.duplicates,
      icon: PhosphorIconsDuotone.copy,
      foreground: Color(0xFF6B55D9),
      secondary: Color(0xFFB7A9FF),
      background: Color(0xFFF0EDFF),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color border = isDark ? AppColors.darkBorder : AppColors.border;

    return Container(
      key: const Key('files_tools_card'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: <BoxShadow>[
          if (!isDark)
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.045),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
        ],
      ),
      child: Column(
        children: <Widget>[
          for (int index = 0; index < _tools.length; index++) ...<Widget>[
            _FileToolRow(tool: _tools[index]),
            if (index != _tools.length - 1)
              Divider(height: 1, indent: 70, endIndent: 14, color: border),
          ],
        ],
      ),
    );
  }
}

class _FileToolRow extends StatelessWidget {
  const _FileToolRow({required this.tool});

  final _FileTool tool;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key(tool.keyName),
        onTap: () => context.push(tool.route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
          child: Row(
            children: <Widget>[
              Container(
                key: Key('${tool.keyName}_icon'),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? tool.foreground.withValues(alpha: 0.16)
                      : tool.background,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: tool.foreground.withValues(
                      alpha: isDark ? 0.25 : 0.08,
                    ),
                  ),
                ),
                child: Center(
                  child: PhosphorIcon(
                    tool.icon,
                    size: 26,
                    color: tool.foreground,
                    duotoneSecondaryColor: tool.secondary,
                    duotoneSecondaryOpacity: 1,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      tool.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tool.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileTool {
  const _FileTool({
    required this.keyName,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
    required this.foreground,
    required this.secondary,
    required this.background,
  });

  final String keyName;
  final String title;
  final String subtitle;
  final String route;
  final IconData icon;
  final Color foreground;
  final Color secondary;
  final Color background;
}
