import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/core/ui/responsive.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/core/utils/date_formatter.dart';
import 'package:mobile_cleaner/features/apps/data/installed_apps_repository.dart';
import 'package:mobile_cleaner/features/apps/domain/app_inventory.dart';
import 'package:mobile_cleaner/features/apps/domain/installed_app.dart';
import 'package:mobile_cleaner/features/apps/presentation/providers/installed_apps_provider.dart';
import 'package:mobile_cleaner/features/apps/presentation/widgets/app_icon.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';

/// Apps: installed applications, as far as Android permits reading them.
///
/// ## Honest about its own limits
///
/// The list is apps with a **launcher icon**, because that is what the
/// `<queries>` declaration reveals without `QUERY_ALL_PACKAGES` — a
/// Play-restricted permission this app does not use. The count will therefore
/// not match system Settings, and the screen says so rather than pretending
/// to be complete.
///
/// Full size figures need Usage Access, which Android only grants from system
/// Settings. Without it the APK size is shown and labelled as such.
///
/// ## Nothing is uninstalled by this app
///
/// Open, App Settings, and Uninstall are all handoffs to Android. The
/// uninstall confirmation is the platform's own; this screen only re-reads the
/// list afterwards to see what happened.
class AppsScreen extends ConsumerStatefulWidget {
  const AppsScreen({super.key});

  @override
  ConsumerState<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends ConsumerState<AppsScreen>
    with WidgetsBindingObserver {
  AppSort _sort = AppSort.defaultSort;
  AppFilter _filter = AppFilter.defaultFilter;

  /// Package awaiting confirmation that Android actually removed it.
  String? _pendingUninstall;

  @override
  void initState() {
    super.initState();
    // The uninstall dialog belongs to Android, and leaving this app is the
    // only signal that it was shown. Resuming is when the outcome can be
    // checked.
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

  void _selectSort(AppSort sort) => setState(() => _sort = sort);

  void _selectFilter(AppFilter filter) => setState(() => _filter = filter);

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

  /// Hands the app to Android's uninstaller, then verifies the outcome.
  ///
  /// The platform dialog does not report back, so the only reliable way to
  /// know whether the user went through with it is to ask afterwards whether
  /// the package is still there.
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
    setState(() => _pendingUninstall = app.packageName);
  }

  /// Checks a pending uninstall once the user comes back to this screen.
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
      // Only refresh when something actually changed, so a cancelled
      // uninstall does not cost a full re-read and icon rasterisation.
      refreshInstalledApps(ref);
      _report('Uninstalled.');
    }
  }

  Future<void> _requestUsageAccess() async {
    final bool opened = await _repository.openUsageAccessSettings();
    if (!opened) {
      _report('Usage access settings are unavailable on this device.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AppInventory> inventory = ref.watch(
      appInventoryProvider((_sort, _filter)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apps'),
        actions: <Widget>[
          IconButton(
            key: const Key('apps_refresh'),
            tooltip: 'Refresh',
            onPressed: () => refreshInstalledApps(ref),
            icon: const Icon(Icons.refresh_rounded),
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
            // Reading apps needs no storage permission, so the permissions
            // route would be a dead end. Retrying is the only real remedy.
            onPermissions: () => refreshInstalledApps(ref),
          ),
          data: (AppInventory data) => Column(
            children: <Widget>[
              _FilterBar(
                sort: _sort,
                filter: _filter,
                onSort: _selectSort,
                onFilter: _selectFilter,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    refreshInstalledApps(ref);
                    await ref.read(installedAppsProvider.future);
                  },
                  child: data.isEmpty
                      ? const _NoApps()
                      : _AppList(
                          inventory: data,
                          onOpen: _open,
                          onSettings: _openSettings,
                          onUninstall: _uninstall,
                          onGrantUsageAccess: _requestUsageAccess,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sort chips plus the system-app filter.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.sort,
    required this.filter,
    required this.onSort,
    required this.onFilter,
  });

  final AppSort sort;
  final AppFilter filter;
  final ValueChanged<AppSort> onSort;
  final ValueChanged<AppFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    // Horizontally scrollable: six chips overflow any phone.
    return SizedBox(
      // Grows with the user's text scale so chip labels are never clipped.
      height: Responsive.chipBarHeight(context),
      child: ListView(
        key: const Key('apps_filter_bar'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        children: <Widget>[
          for (final AppSort option in AppSort.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('app_sort_${option.name}'),
                label: Text(option.label),
                selected: option == sort,
                onSelected: (_) => onSort(option),
                visualDensity: VisualDensity.compact,
              ),
            ),
          const SizedBox(width: 8),
          for (final AppFilter option in AppFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                key: Key('app_filter_${option.name}'),
                label: Text(option.label),
                selected: option == filter,
                onSelected: (_) => onFilter(option),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _AppList extends StatelessWidget {
  const _AppList({
    required this.inventory,
    required this.onOpen,
    required this.onSettings,
    required this.onUninstall,
    required this.onGrantUsageAccess,
  });

  final AppInventory inventory;
  final ValueChanged<InstalledApp> onOpen;
  final ValueChanged<InstalledApp> onSettings;
  final ValueChanged<InstalledApp> onUninstall;
  final VoidCallback onGrantUsageAccess;

  @override
  Widget build(BuildContext context) {
    final bool showUsagePrompt = inventory.canImproveSizes;
    final int headerCount = showUsagePrompt ? 2 : 1;

    // Lazily built: each row decodes an icon, so building every row up front
    // would stall the UI thread on a device with hundreds of apps.
    return ListView.builder(
      key: const Key('apps_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      itemCount: inventory.appCount + headerCount,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return _TotalCard(inventory: inventory);
        }
        if (showUsagePrompt && index == 1) {
          return _UsageAccessCard(onGrant: onGrantUsageAccess);
        }

        final InstalledApp app = inventory.apps[index - headerCount];
        return _AppRow(
          app: app,
          onOpen: () => onOpen(app),
          onSettings: () => onSettings(app),
          onUninstall: () => onUninstall(app),
        );
      },
    );
  }
}

/// One app: icon, name, size, and the three actions.
class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.onOpen,
    required this.onSettings,
    required this.onUninstall,
  });

  final InstalledApp app;
  final VoidCallback onOpen;
  final VoidCallback onSettings;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: Key('app_card_${app.packageName}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                AppIcon(app: app),
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
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _sizeLabel(app),
                        key: Key('app_size_${app.packageName}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      Text(
                        _subtitleFor(app),
                        key: Key('app_detail_${app.packageName}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Scrollable: three labelled actions overflow a narrow phone, and
            // an overflowing Row would throw rather than clip.
            SizedBox(
              height: 44,
              child: ListView(
                key: Key('app_actions_${app.packageName}'),
                scrollDirection: Axis.horizontal,
                reverse: true,
                children: <Widget>[
                  _ActionButton(
                    actionKey: Key('app_uninstall_${app.packageName}'),
                    icon: Icons.delete_outline_rounded,
                    label: 'Uninstall',
                    // Android refuses for system apps; say so up front rather
                    // than opening a dialog that will fail.
                    onPressed: app.isSystemApp ? null : onUninstall,
                    destructive: true,
                  ),
                  _ActionButton(
                    actionKey: Key('app_settings_${app.packageName}'),
                    icon: Icons.settings_outlined,
                    label: 'App Settings',
                    onPressed: onSettings,
                  ),
                  _ActionButton(
                    actionKey: Key('app_open_${app.packageName}'),
                    icon: Icons.launch_rounded,
                    label: 'Open',
                    onPressed: app.canOpen ? onOpen : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The headline size, labelled honestly about what it covers.
  static String _sizeLabel(InstalledApp app) {
    final int? total = app.totalBytes;
    if (total != null) {
      return ByteFormatter.format(total);
    }
    // Not the full footprint, so do not present it as one.
    return '${ByteFormatter.format(app.apkBytes)} app';
  }

  static String _subtitleFor(InstalledApp app) {
    final List<String> parts = <String>[];
    if (app.hasDetailedSize) {
      parts.add('${ByteFormatter.format(app.dataBytes ?? 0)} data');
      final int cache = app.cacheBytes ?? 0;
      if (cache > 0) {
        parts.add('${ByteFormatter.format(cache)} cache');
      }
    }
    if (app.isSystemApp) {
      parts.add('System');
    }
    if (parts.isEmpty && app.updatedAt != null) {
      parts.add('Updated ${DateFormatter.relative(app.updatedAt!)}');
    }
    if (parts.isEmpty) {
      parts.add(app.packageName);
    }
    return parts.join(' · ');
  }
}

/// One action. Height-constrained only, never width.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: TextButton.icon(
        key: actionKey,
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: destructive ? colors.error : colors.primary,
          // Height only. A minimum width here could force an infinite width
          // inside a horizontal list.
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );
  }
}

/// Explains that sizes are partial, and offers the only route to fixing it.
class _UsageAccessCard extends StatelessWidget {
  const _UsageAccessCard({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: const Key('apps_usage_access_card'),
      margin: const EdgeInsets.only(top: 12),
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.query_stats_rounded,
                  size: 18,
                  color: colors.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Showing app sizes only',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Android needs Usage Access before it will report app data and '
              'cache. It can only be granted from system settings.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('apps_grant_usage_access'),
                onPressed: onGrant,
                child: const Text('Open settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Headline: how many apps and how much space.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.inventory});

  final AppInventory inventory;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final int count = inventory.appCount;

    return Card(
      key: const Key('apps_total_card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              inventory.hasUsageAccess
                  ? 'Space used by apps'
                  : 'App size, excluding data',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              ByteFormatter.format(inventory.totalBytes),
              key: const Key('apps_total_bytes'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$count ${count == 1 ? 'app' : 'apps'}',
              key: const Key('apps_count'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Android only lets this app see apps with a launcher '
                    'icon, so this list is shorter than system settings.',
                    key: const Key('apps_visibility_note'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
        Icon(Icons.apps_rounded, size: 56, color: colors.primary),
        const SizedBox(height: 16),
        Text(
          'No apps to show',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Android did not report any installed apps this app is allowed to '
          'see. Try including system apps.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
