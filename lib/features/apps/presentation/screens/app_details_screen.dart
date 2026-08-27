import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/apps/domain/installed_app.dart';
import 'package:mobile_cleaner/features/apps/presentation/widgets/app_icon.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

enum _AppDetailMenuAction { open, settings, uninstall }

/// Full, factual details for one installed app.
class AppDetailsScreen extends StatelessWidget {
  const AppDetailsScreen({
    required this.app,
    required this.onOpen,
    required this.onSettings,
    required this.onUninstall,
    super.key,
  });

  final InstalledApp app;
  final VoidCallback onOpen;
  final VoidCallback onSettings;
  final VoidCallback onUninstall;

  String get _versionLabel {
    final String? name = app.versionName;
    if (name != null && name.isNotEmpty) {
      return 'Version $name';
    }
    final int? code = app.versionCode;
    return code == null ? 'Version unavailable' : 'Version $code';
  }

  void _handleMenu(_AppDetailMenuAction action) {
    switch (action) {
      case _AppDetailMenuAction.open:
        onOpen();
      case _AppDetailMenuAction.settings:
        onSettings();
      case _AppDetailMenuAction.uninstall:
        onUninstall();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Scaffold(
      key: Key('app_details_screen_${app.packageName}'),
      appBar: AppBar(
        toolbarHeight: 60,
        leading: IconButton(
          key: Key('app_details_back_${app.packageName}'),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        titleSpacing: 4,
        title: Text(
          app.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        actions: <Widget>[
          PopupMenuButton<_AppDetailMenuAction>(
            key: Key('app_details_menu_${app.packageName}'),
            tooltip: 'App actions',
            onSelected: _handleMenu,
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<_AppDetailMenuAction>>[
                  PopupMenuItem<_AppDetailMenuAction>(
                    value: _AppDetailMenuAction.open,
                    enabled: app.canOpen,
                    child: const Text('Open'),
                  ),
                  const PopupMenuItem<_AppDetailMenuAction>(
                    value: _AppDetailMenuAction.settings,
                    child: Text('App Settings'),
                  ),
                  PopupMenuItem<_AppDetailMenuAction>(
                    value: _AppDetailMenuAction.uninstall,
                    enabled: !app.isSystemApp,
                    child: const Text('Uninstall'),
                  ),
                ],
            icon: const Icon(Icons.more_vert_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListView(
          key: Key('app_details_list_${app.packageName}'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: <Widget>[
            _AppIdentity(app: app, versionLabel: _versionLabel),
            const SizedBox(height: 16),
            _AppSizeDetails(app: app),
            const SizedBox(height: 16),
            _AppDetailActions(
              app: app,
              onOpen: onOpen,
              onSettings: onSettings,
              onUninstall: onUninstall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AppIdentity extends StatelessWidget {
  const _AppIdentity({required this.app, required this.versionLabel});

  final InstalledApp app;
  final String versionLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      key: Key('app_details_identity_${app.packageName}'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        AppIcon(app: app, size: 72),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                app.name,
                key: Key('app_details_name_${app.packageName}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                versionLabel,
                key: Key('app_details_version_${app.packageName}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                app.packageName,
                key: Key('app_details_package_${app.packageName}'),
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
      ],
    );
  }
}

class _AppSizeDetails extends StatelessWidget {
  const _AppSizeDetails({required this.app});

  final InstalledApp app;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final int? total = app.totalBytes;
    final int displayedTotal = total ?? app.apkBytes;

    return Container(
      key: Key('app_details_size_card_${app.packageName}'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
            'App size',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            ByteFormatter.format(displayedTotal),
            key: Key('app_details_total_${app.packageName}'),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: isDark ? AppColors.darkOrange : AppColors.cleanupOrange,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.45,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            total == null ? 'Excluding data' : 'Including data and cache',
            key: Key('app_details_size_scope_${app.packageName}'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _SizeLine(
            label: 'App',
            value: ByteFormatter.format(app.appBytes ?? app.apkBytes),
            valueKey: Key('app_details_app_bytes_${app.packageName}'),
          ),
          _SizeLine(
            label: 'Data',
            value: app.dataBytes == null
                ? 'Not available'
                : ByteFormatter.format(app.dataBytes!),
            valueKey: Key('app_details_data_bytes_${app.packageName}'),
          ),
          _SizeLine(
            label: 'Cache',
            value: app.cacheBytes == null
                ? 'Not available'
                : ByteFormatter.format(app.cacheBytes!),
            valueKey: Key('app_details_cache_bytes_${app.packageName}'),
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _SizeLine extends StatelessWidget {
  const _SizeLine({
    required this.label,
    required this.value,
    required this.valueKey,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final Key valueKey;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              )
            : null,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            key: valueKey,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: value == 'Not available'
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppDetailActions extends StatelessWidget {
  const _AppDetailActions({
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
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      key: Key('app_details_actions_${app.packageName}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _DetailActionButton(
                  buttonKey: Key('app_open_${app.packageName}'),
                  icon: PhosphorIconsDuotone.playCircle,
                  label: 'Open',
                  onPressed: app.canOpen ? onOpen : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DetailActionButton(
                  buttonKey: Key('app_settings_${app.packageName}'),
                  icon: PhosphorIconsDuotone.gearSix,
                  label: 'App Settings',
                  onPressed: onSettings,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DetailActionButton(
            buttonKey: Key('app_uninstall_${app.packageName}'),
            icon: PhosphorIconsDuotone.trash,
            label: 'Uninstall',
            onPressed: app.isSystemApp ? null : onUninstall,
            destructive: true,
          ),
        ],
      ),
    );
  }
}

class _DetailActionButton extends StatelessWidget {
  const _DetailActionButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color foreground = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: buttonKey,
        onPressed: onPressed,
        icon: PhosphorIcon(
          icon,
          size: 18,
          color: foreground,
          duotoneSecondaryColor: foreground.withValues(alpha: 0.45),
          duotoneSecondaryOpacity: 1,
        ),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          side: BorderSide(color: foreground.withValues(alpha: 0.25)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
