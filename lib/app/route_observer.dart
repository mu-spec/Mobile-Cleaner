import 'package:flutter/material.dart';

/// Increments whenever the Home storage ring should replay its finite
/// entrance animation.
final ValueNotifier<int> storageRingReplay = ValueNotifier<int>(0);

bool _isHomeVisible = true;

/// Tracks bottom-tab visibility and replays only when Home becomes visible.
void setStorageHomeVisible(bool visible) {
  if (_isHomeVisible == visible) {
    return;
  }
  _isHomeVisible = visible;
  if (visible) {
    storageRingReplay.value++;
  }
}

/// Replays after a full-screen route above Home is popped.
void replayStorageRing() {
  if (_isHomeVisible) {
    storageRingReplay.value++;
  }
}

/// Observes pushed-screen returns without coupling the ring to the router.
final RouteObserver<PageRoute<dynamic>> storageRouteObserver =
    _StorageRouteObserver();

class _StorageRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute<dynamic> && previousRoute != null) {
      replayStorageRing();
    }
  }
}
