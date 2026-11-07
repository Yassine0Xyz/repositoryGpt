import 'package:flutter/widgets.dart';

import '../diagnostics/core/diagnostics_service.dart';

class DiagnosticsRouteObserver extends RouteObserver<ModalRoute<dynamic>> {
  String _routeName(Route<dynamic>? route) {
    final name = route?.settings.name;
    return (name == null || name.isEmpty) ? route.runtimeType.toString() : name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    DiagnosticsService.instance.routeChanged(_routeName(route), action: 'push');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    DiagnosticsService.instance.routeChanged(_routeName(previousRoute), action: 'pop');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    DiagnosticsService.instance.routeChanged(_routeName(newRoute), action: 'replace');
  }
}

final DiagnosticsRouteObserver appRouteObserver = DiagnosticsRouteObserver();
