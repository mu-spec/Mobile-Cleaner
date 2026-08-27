import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/navigation/root_back_button.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/core/utils/date_formatter.dart';
import 'package:mobile_cleaner/features/apps/data/installed_apps_repository.dart';
import 'package:mobile_cleaner/features/apps/domain/app_inventory.dart';
import 'package:mobile_cleaner/features/apps/domain/installed_app.dart';
import 'package:mobile_cleaner/features/apps/presentation/providers/installed_apps_provider.dart';
import 'package:mobile_cleaner/features/apps/presentation/screens/app_details_screen.dart';
import 'package:mobile_cleaner/features/apps/presentation/widgets/app_icon.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Installed apps arranged as the supplied reference: sort controls, one
/// honest size summary, then a compact app list. App actions live on the full
/// detail screen opened from each row.
class AppsScreen extends ConsumerStatefulWidget {
  const AppsScreen({super.key});

  @override
  ConsumerState<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends ConsumerState<AppsScreen>
    with WidgetsBindingObserver {
  AppSort _sort = AppSort.defaultSort;
  String? _pendingUninstall;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _confirmPendingUninstall();
    }
  }

  InstalledAppsRepository get _repository =>
      ref.read(installedAppsRepositoryProvider);

  void _report(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(key: const Key('apps_message'), content: Text(message)),
      );
  }

  Future<void> _open(InstalledApp app) async {
    final bool started = await _repository.openApp(app.packageName);
    if (!started) {
      _report('${app.name} could not be opened.');
    }
  }

  Future<void> _openSettings(InstalledApp app) async {
    final bool started = await _repository.openAppSettings(app.packageName);
    if (!started) {
      _report('App settings are unavailable for ${app.name}.');
    }
  }

  Future<void> _uninstall(InstalledApp app) async {
    final bool started = await _repository.requestUninstall(app.packageName);
    if (!started) {
      _report(
        app.isSystemApp
            ? '${app.name} is a system app and cannot be uninstalled.'
            : '${app.name} could not be uninstalled.',
      );
      return;
    }
    if (mounted) {
      setState(() => _pendingUninstall = app.packageName);
    }
  }

  Future<void> _confirmPendingUninstall() async {
    final String? pending = _pendingUninstall;
    if (pending == null) {
      return;
    }
    final bool stillInstalled = await _repository.isInstalled(pending);
    if (!mounted) {
      return;
    }
    setState(() => _pendingUninstall = null);
    if (!stillInstalled) {
      refreshInstalledApps(ref);
      _report('Uninstalled.');
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  void _showDetails(InstalledApp app) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppDetailsScreen(
          app: app,
          onOpen: () => _open(app),
          onSettings: () => _openSettings(app),
          onUninstall: () => _uninstall(app),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AppInventory> inventory = ref.watch(
      appInventoryProvider((_sort, AppFilter.defaultFilter)),
    );
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Scaffold(
      key: const Key('apps_screen'),
      appBar: AppBar(
        toolbarHeight: 60,
        leading: const RootBackButton(buttonKey: Key('apps_back_button')),
        titleSpacing: 4,
        title: Text(
          'Apps',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        actions: <Widget>[
          IconButton(
            key: const Key('apps_refresh'),
            tooltip: 'Refresh',
            onPressed: () => refreshInstalledApps(ref),
            icon: const Icon(Icons.refresh_rounded, size: 27),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: inventory.when(
          loading: () => const FilesScanningView(),
          error: (Object error, StackTrace stackTrace) => FilesErrorView(
            error: error,
            onRetry: () => refreshInstalledApps(ref),
            onPermissions: () => refreshInstalledApps(ref),
          ),
          data: (AppInventory data) => Column(
            children: <Widget>[
              _SortBar(
                sort: _sort,
                onSort: (AppSort value) {
                  setState(() => _sort = value);
                },
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    refreshInstalledApps(ref);
                    await ref.read(installedAppsProvider.future);
                  },
                  child: data.isEmpty
                      ? const _NoApps()
                      : _AppList(inventory: data, onDetails: _showDetails),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The four compact controls shown in the reference.
class _SortBar extends StatelessWidget {
  const _SortBar({required this.sort, required this.onSort});

  final AppSort sort;
  final ValueChanged<AppSort> onSort;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 58,
      child: SingleChildScrollView(
        key: const Key('apps_filter_bar'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final AppSort option in AppSort.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: Key('app_sort_${option.name}'),
                  label: Text(option.label),
                  selected: option == sort,
                  onSelected: (_) => onSort(option),
                  showCheckmark: option == sort,
                  checkmarkColor: Colors.white,
                  selectedColor: isDark
                      ? AppColors.darkPrimary
                      : AppColors.brandBlue,
                  backgroundColor: isDark
                      ? AppColors.darkSurfaceElevated
                      : AppColors.card,
                  labelStyle: theme.textTheme.bodySmall?.copyWith(
                    color: option == sort
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                  side: BorderSide(
                    color: option == sort
                        ? Colors.transparent
                        : theme.colorScheme.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppList extends StatelessWidget {
  const _AppList({required this.inventory, required this.onDetails});

  final AppInventory inventory;
  final ValueChanged<InstalledApp> onDetails;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('apps_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      itemCount: inventory.appCount + 1,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TotalCard(inventory: inventory),
          );
        }
        final InstalledApp app = inventory.apps[index - 1];
        return _AppRow(app: app, onTap: () => onDetails(app));
      },
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.onTap});

  final InstalledApp app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final String updated = app.updatedAt == null
        ? 'Update date unavailable'
        : 'Updated ${DateFormatter.format(app.updatedAt!)}';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : AppColors.card,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('app_card_${app.packageName}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 11, 4, 11),
            child: Row(
              children: <Widget>[
                AppIcon(app: app, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        app.name,
                        key: Key('app_name_${app.packageName}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ByteFormatter.format(app.bestKnownBytes),
                        key: Key('app_size_${app.packageName}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        updated,
                        key: Key('app_detail_${app.packageName}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('app_more_${app.packageName}'),
                  tooltip: 'View ${app.name} details',
                  onPressed: onTap,
                  icon: PhosphorIcon(
                    PhosphorIconsDuotone.dotsThreeVertical,
                    size: 21,
                    color: theme.colorScheme.onSurface,
                    duotoneSecondaryColor: theme.colorScheme.onSurfaceVariant,
                    duotoneSecondaryOpacity: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.inventory});

  final AppInventory inventory;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final int count = inventory.appCount;

    return Container(
      key: const Key('apps_total_card'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
        boxShadow: <BoxShadow>[
          if (!isDark)
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            inventory.hasUsageAccess
                ? 'Space used by apps'
                : 'App size, excluding data',
            key: const Key('apps_total_label'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            ByteFormatter.format(inventory.totalBytes),
            key: const Key('apps_total_bytes'),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: isDark ? AppColors.darkOrange : AppColors.cleanupOrange,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$count ${count == 1 ? 'app' : 'apps'}',
            key: const Key('apps_count'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PhosphorIcon(
                PhosphorIconsDuotone.info,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
                duotoneSecondaryColor: theme.colorScheme.onSurfaceVariant,
                duotoneSecondaryOpacity: 0.45,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Android only lets this app see apps with a launcher icon, '
                  'so this list is shorter than system settings.',
                  key: const Key('apps_visibility_note'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoApps extends StatelessWidget {
  const _NoApps();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('apps_empty'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        const SizedBox(height: 60),
        PhosphorIcon(
          PhosphorIconsDuotone.appWindow,
          size: 56,
          color: colors.primary,
          duotoneSecondaryColor: colors.primary.withValues(alpha: 0.45),
          duotoneSecondaryOpacity: 1,
        ),
        const SizedBox(height: 16),
        Text(
          'No apps to show',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Android did not report any installed apps this app is allowed to '
          'see.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
