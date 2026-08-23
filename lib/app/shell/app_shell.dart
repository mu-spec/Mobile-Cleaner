import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      // A subtle top divider separates the bar from content; colors (white
      // surface, blue selection, gray rest) come from the app theme so the
      // bar stays in step with the design system in both brightnesses.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: navigationShell.currentIndex,
          onTap: _onDestinationSelected,
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined, key: Key('nav_home')),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_fix_high_outlined, key: Key('nav_clean')),
              activeIcon: Icon(Icons.auto_fix_high_rounded),
              label: 'Clean',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.photo_library_outlined, key: Key('nav_photos')),
              activeIcon: Icon(Icons.photo_library_rounded),
              label: 'Photos',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined, key: Key('nav_files')),
              activeIcon: Icon(Icons.folder_rounded),
              label: 'Files',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.apps_outlined, key: Key('nav_apps')),
              activeIcon: Icon(Icons.apps_rounded),
              label: 'Apps',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined, key: Key('nav_settings')),
              activeIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
