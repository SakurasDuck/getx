import 'dart:collection';

import 'package:flutter/widgets.dart';

import '../../get.dart';

class RouterReportManager<T> {
  /// Holds a reference to `Get.reference` when the Instance was
  /// created to manage the memory.
  final Map<T?, List<String>> _routesKey = {};

  /// Stores the onClose() references of instances created with `Get.create()`
  /// using the `Get.reference`.
  /// Experimental feature to keep the lifecycle and memory management with
  /// non-singleton instances.
  final Map<T?, HashSet<Function>> _routesByCreate = {};

  ///保存bind 加载的depedencyKey,绑定到对应的context.route上
  final Map<String, T> _depeKey2BindRoute = {};

  static RouterReportManager? _instance;

  RouterReportManager._();

  static RouterReportManager get instance =>
      _instance ??= RouterReportManager._();

  static void dispose() {
    _instance = null;
  }

  void printInstanceStack() {
    Get.log(_routesKey.toString());
  }

  T? _current;

  ///获取可能bind的route,没有为current
  T? _bindRoute(String depedencyKey) =>
      _depeKey2BindRoute[depedencyKey] ?? _current;

  // ignore: use_setters_to_change_properties
  void reportCurrentRoute(T newRoute) {
    _current = newRoute;
  }

  ///上报依赖绑定的对应的bindContext.route
  void reportDepeKey2BindRoute(String depedencyKey, T? routeName) {
    if (!_depeKey2BindRoute.containsKey(depedencyKey)) {
      if (routeName != null) {
        _depeKey2BindRoute.addAll({depedencyKey: routeName});
      }
    }
  }

  /// Links a Class instance [S] (or [tag]) to the current route.
  /// Requires usage of `GetMaterialApp`.
  void reportDependencyLinkedToRoute(String depedencyKey) {
    final _bind = _bindRoute(depedencyKey);
    if (_bind == null) return;
    if (_routesKey.containsKey(_bind)) {
      _routesKey[_bind]!.add(depedencyKey);
    } else {
      _routesKey[_bind] = <String>[depedencyKey];
    }
  }

  void clearRouteKeys() {
    _routesKey.clear();
    _routesByCreate.clear();
    _depeKey2BindRoute.clear();
  }

  void appendRouteByCreate(GetLifeCycleMixin i, String depedencyKey) {
    final _bind = _bindRoute(depedencyKey);
    if (_bind == null) return;
    _routesByCreate[_bind] ??= HashSet<Function>();
    // _routesByCreate[Get.reference]!.add(i.onDelete as Function);
    _routesByCreate[_bind]!.add(i.onDelete);
  }

  void reportRouteDispose(T disposed) {
    if (Get.smartManagement != SmartManagement.onlyBuilder) {
      ambiguate(Engine.instance)!.addPostFrameCallback((_) {
        _removeDependencyByRoute(disposed);
      });
    }
  }

  void reportRouteWillDispose(T disposed) {
    final keysToRemove = <String>[];

    _routesKey[disposed]?.forEach(keysToRemove.add);

    /// Removes `Get.create()` instances registered in `routeName`.
    if (_routesByCreate.containsKey(disposed)) {
      for (final onClose in _routesByCreate[disposed]!) {
        // assure the [DisposableInterface] instance holding a reference
        // to onClose() wasn't disposed.
        onClose();
      }
      _routesByCreate[disposed]!.clear();
      _routesByCreate.remove(disposed);
    }

    for (final element in keysToRemove) {
      Get.markAsDirty(key: element);

      //_routesKey.remove(element);
    }

    //删除bind
    _depeKey2BindRoute.remove(disposed);

    keysToRemove.clear();
  }

  /// Clears from memory registered Instances associated with [routeName] when
  /// using `Get.smartManagement` as [SmartManagement.full] or
  /// [SmartManagement.keepFactory]
  /// Meant for internal usage of `GetPageRoute` and `GetDialogRoute`
  void _removeDependencyByRoute(T routeName) {
    final keysToRemove = <String>[];

    _routesKey[routeName]?.forEach(keysToRemove.add);

    /// Removes `Get.create()` instances registered in `routeName`.
    if (_routesByCreate.containsKey(routeName)) {
      for (final onClose in _routesByCreate[routeName]!) {
        // assure the [DisposableInterface] instance holding a reference
        // to onClose() wasn't disposed.
        onClose();
      }
      _routesByCreate[routeName]!.clear();
      _routesByCreate.remove(routeName);
    }

    for (final element in keysToRemove) {
      final value = Get.delete(key: element);
      if (value) {
        _routesKey[routeName]?.remove(element);
      }
    }

    //删除bind
    _depeKey2BindRoute.remove(routeName);

    keysToRemove.clear();
  }
}
