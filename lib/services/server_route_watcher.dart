import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'subsonic_service.dart';

/// Re-decides between the server's LAN and public address whenever the network may have changed: a
/// connectivity change, or the app returning to the foreground (a laptop waking on another network
/// reports nothing else).
class ServerRouteWatcher with WidgetsBindingObserver {
  ServerRouteWatcher(this._service,
      {Stream<List<ConnectivityResult>>? connectivityChanges})
      : _changes = connectivityChanges;

  final SubsonicService _service;
  final Stream<List<ConnectivityResult>>? _changes;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  void start() {
    _sub = (_changes ?? Connectivity().onConnectivityChanged)
        .listen((_) => unawaited(_service.refreshRoute()));
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_service.refreshRoute());
    }
  }

  void dispose() {
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
