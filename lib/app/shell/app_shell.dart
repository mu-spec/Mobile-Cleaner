import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/navigation/exit_confirmation.dart';
import 'package:mobile_cleaner/app/route_observer.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<_DestinationData> _destinations = <_DestinationData>[
    _DestinationData(
      key: Key('nav_home'),
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    _DestinationData(
      key: Key('nav_clean'),
      icon: Icons.auto_fix_high_outlined,
      activeIcon: Icons.auto_fix_high_rounded,
      label: 'Clean',
    ),
    _DestinationData(
      key: Key('nav_photos'),
      icon: Icons.photo_library_outlined,
      activeIcon: Icons.photo_library_rounded,
      label: 'Photos',
    ),
    _DestinationData(
      key: Key('nav_files'),
      icon: Icons.folder_outlined,
      activeIcon: Icons.folder_rounded,
      label: 'Files',
    ),
    _DestinationData(
      key: Key('nav_apps'),
      icon: Icons.apps_outlined,
      activeIcon: Icons.apps_rounded,
      label: 'Apps',
    ),
    _DestinationData(
      key: Key('nav_settings'),
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BottomNavigationBarThemeData navigationTheme =
        theme.bottomNavigationBarTheme;
    final Color selectedColor =
        navigationTheme.selectedItemColor ?? theme.colorScheme.primary;
    final Color unselectedColor =
        navigationTheme.unselectedItemColor ??
        theme.colorScheme.onSurfaceVariant;
    final Color backgroundColor =
        navigationTheme.backgroundColor ?? theme.colorScheme.surface;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _handleSystemBack();
        }
      },
      child: Scaffold(
        body: widget.navigationShell,
        bottomNavigationBar: Material(
          color: backgroundColor,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 58,
                child: Row(
                  children: <Widget>[
                    for (int index = 0; index < _destinations.length; index++)
                      Expanded(
                        child: _BottomDestination(
                          data: _destinations[index],
                          selected:
                              widget.navigationShell.currentIndex == index,
                          selectedColor: selectedColor,
                          unselectedColor: unselectedColor,
                          onTap: () => _onDestinationSelected(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleSystemBack() {
    if (widget.navigationShell.currentIndex != 0) {
      _onDestinationSelected(0);
      return;
    }
    showExitConfirmation(context);
  }

  void _onDestinationSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
    setStorageHomeVisible(index == 0);
  }
}

class _DestinationData {
  const _DestinationData({
    required this.key,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final Key key;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _BottomDestination extends StatelessWidget {
  const _BottomDestination({
    required this.data,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final _DestinationData data;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? selectedColor : unselectedColor;

    return Semantics(
      button: true,
      selected: selected,
      label: data.label,
      child: ExcludeSemantics(
        child: InkWell(
          key: data.key,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 5, 2, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  selected ? data.activeIcon : data.icon,
                  size: selected ? 23 : 22,
                  color: color,
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        data.label,
                        maxLines: 1,
                        style: TextStyle(
                          color: color,
                          fontSize: selected ? 10.5 : 9.5,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
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
