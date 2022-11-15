## 对getx 源码的改造及原因

1. #### 为什么要改造源码  
    - [在复杂场景下logic 会绑错路由的情况](https://juejin.cn/post/7064536758351839262)
    - 上面的链接是Getx 4.6.1的改造,这次针对 `get: 5.0.0-beta.52` 修改,主要针对与5.0.0 推出的`Bind`适配
2. #### 改造思路
   - 首先要理解作者推出`Bind`的思路,这次5.0.0升级废弃了`Bindings`
    ```dart
    /// [Bindings] should be extended or implemented.
    /// When using `GetMaterialApp`, all `GetPage`s and navigation
    /// methods (like Get.to()) have a `binding` property that takes an
    /// instance of Bindings to manage the
    /// dependencies() (via Get.put()) for the Route you are opening.
    // ignore: one_member_abstracts
    @Deprecated('Use Binding instead')
    abstract class Bindings extends BindingsInterface<void> {
      @override
      void dependencies();
    }
    ```
   然后推出`Binding`
   ```dart
   /// [Binding] should be extended.
   /// When using `GetMaterialApp`, all `GetPage`s and navigation
   /// methods (like Get.to()) have a `binding` property that takes an
   /// instance of Bindings to manage the
   /// dependencies() (via Get.put()) for the Route you are opening.
   // ignore: one_member_abstracts
   abstract class Binding extends BindingsInterface<List<Bind>> {}
   ```
   区别在`dependencies()` 返回值,现在为`List<Bind>`, 我们知道这个`dependencies()`方法作用是给`GetPage`注入依赖,在推入`GetPage`入栈时`BuildWidget`调用
   ```dart 
    // get 4.6.1
    ...
    final localbindings = [
      if (bindings != null) ...bindings!,
      if (binding != null) ...[binding!]
    ];
    final bindingsToBind = middlewareRunner.runOnBindingsStart(localbindings);
    if (bindingsToBind != null) {
      for (final binding in bindingsToBind) {
        binding.dependencies();
      }
    }

    final pageToBuild = middlewareRunner.runOnPageBuildStart(page)!;
    _child = middlewareRunner.runOnPageBuilt(pageToBuild());
    return _child!;
    ...
   ```
   ```dart
   //get 5.0.0
   final localbinds = [if (binds != null) ...binds!];

    final bindingsToBind = middlewareRunner
        .runOnBindingsStart(bindings.isNotEmpty ? bindings : localbinds);

    final pageToBuild = middlewareRunner.runOnPageBuildStart(page)!;

    if (bindingsToBind != null && bindingsToBind.isNotEmpty) {
      if (bindingsToBind is List<BindingsInterface>) {
        for (final item in bindingsToBind) {
          final dep = item.dependencies();
          //为了兼容4.x.x,如果返回List<Bind> 则使用Binds 包裹
          if (dep is List<Bind>) {
            _child = Binds(
              child: middlewareRunner.runOnPageBuilt(pageToBuild()),
              binds: dep,
            );
          }
          // 如果返回void,则是4.x.x版本
        }
      } else if (bindingsToBind is List<Bind>) {
        //处理直接GetPage直接传参binds时情况
        _child = Binds(
          child: middlewareRunner.runOnPageBuilt(pageToBuild()),
          binds: bindingsToBind,
        );
      }
    }

    return _child ??= middlewareRunner.runOnPageBuilt(pageToBuild());
   ```
   那么这里出现的`Binds`做了什么处理呢
   ```dart
   class Binds extends StatelessWidget {
    //简单的无状态Widget
    final List<Bind<dynamic>> binds;
    final Widget child;

    Binds({
      Key? key,
      required this.binds,
      required this.child,
    })
        : assert(binds.isNotEmpty),
          super(key: key);

     @override
    Widget build(BuildContext context) =>
    //将binds倒序迭代包裹本身,并生成一个Widget并返回
        binds.reversed.fold(child, (widget, e) => e._copyWithChild(widget));
   }
   ```
   接下来看`Bind`又是啥,`_copyWithChild(widget)`又做了什么处理
   ```dart
   //本身是一个抽象类,提供_copyWithChild()接口,且本身是无状态Widget,所以可以在Binds.build()迭代并返回
   abstract class Bind<T> extends StatelessWidget {
    ...

    @factory
    Bind<T> _copyWithChild(Widget child);

    //提供一个builder直接调用私有实现
    factory Bind.builder({
        ...
      }) =>
      _FactoryBind<T>(
        ...
      );
   }
   //实现类
   class _FactoryBind<T> extends Bind<T> {
  
    @override
    Bind<T> _copyWithChild(Widget child) {
      return Bind<T>.builder(
        ...
    );
   }

   @override
    Widget build(BuildContext context) {
      //最终返回一个Binder,具体实现都在Binder中
      return Binder<T>(
      ...
      child: child!,
      );
     }
    }

   ```  
   重点来了,前面都的处理都是提供接口以及迭代包括,那么处理逻辑都存在Binder中  
   ```dart
   //继承InheritedWidget,可通过上下文做数据共享
   class Binder<T> extends InheritedWidget {
    /// Create an inherited widget that updates its dependents when [controller]
    /// sends notifications.
    ///
    /// The [child] argument is required
    const Binder({
      ...
    }) : super(key: key, child: child);

    ...

    @override
    bool updateShouldNotify(Binder<T> oldWidget) {
      return oldWidget.id != id ||
          oldWidget.global != global ||
          oldWidget.autoRemove != autoRemove ||
          oldWidget.assignId != assignId;
    }

    @override
    InheritedElement createElement() => BindElement<T>(this);
    }
    //具体逻辑操作在element体现,具体源码见 https://github.com/jonataslaw/getx/blob/master/lib/get_state_manager/src/simple/get_state.dart
    //这里只关注 initState 与 dispose
    class BindElement<T> extends InheritedElement {
    BindElement(Binder<T> widget) : super(widget) {
      //在element初始化时调用initState(); tips: widget挂载时(Element inflateWidget(Widget newWidget, Object? newSlot))调用XXElement.createElement();
      initState();
    }

    ...


    void initState() {
      widget.initState?.call(this);

      var isRegistered = Get.isRegistered<T>(tag: widget.tag);

      //是否注册到全局单例
      if (widget.global) {
        if (isRegistered) {
          //已经注册,重置
          if (Get.isPrepared<T>(tag: widget.tag)) {
            _isCreator = true;
          } else {
            _isCreator = false;
          }

          _controllerBuilder = () => Get.find<T>(tag: widget.tag);
        } else {
          _controllerBuilder =
              () => (widget.create?.call(this) ?? widget.init?.call());
          _isCreator = true;
          //注册到全局单例池,等同于4.x.x 之前在void dependencies(){
            //Get.lazyPut<T>(_controllerBuilder!, tag: widget.tag);
            //or
            //Get.put<T>(_controllerBuilder!(), tag: widget.tag);
          //}
          if (widget.lazy) {
            Get.lazyPut<T>(_controllerBuilder!, tag: widget.tag);
          } else {
            Get.put<T>(_controllerBuilder!(), tag: widget.tag);
          }
        }
      } else {
        _controllerBuilder =
            (widget.create != null ? () => widget.create!.call(this) : null) ??
                widget.init;
        _isCreator = true;
        _needStart = true;
      }
    }

    ...

    void dispose() {
      widget.dispose?.call(this);
      if (_isCreator! || widget.assignId) {
        //可以通过autoRemove 由自身控制其生命周期
        if (widget.autoRemove && Get.isRegistered<T>(tag: widget.tag)) {
          Get.delete<T>(tag: widget.tag);
        }
      }

      ...
    }

    ...

    @override
    void unmount() {
      //卸载时调用dispose()
      dispose();
      super.unmount();
    }
   }  
   ```  
   通过翻阅源码,我大胆猜测作者使用`Bind`目的是拓展GetPage.bindings的功能,将组件put依赖的能力封装到`Bind`中,并拓展其自动管理生命周期的能力,4.x.x版本组件的依赖跟组件本身并不是强关联,`Bingings`里面不能很好的控制其生命周期,生命周期的控制是通过`RouterReportManager`加上`Get.find()`维护一个Map<routeName,List<depedencyKey>>,通过监听GetRoute路由的动作来控制depedency的销毁  
  3. #### 开始改造  
     为啥还需要改造呢?复杂业务情况下,我们希望组件依赖的生命周期不能跟随组件的生命周期,而是类似与之前文章的根据路由的操作而定
   而[在复杂场景下logic 会绑错路由的情况](https://juejin.cn/post/7064536758351839262)这个问题依旧存在,不同的是,现在可以在`put()` or `lazyPut()` 拿到当前context,继而拿到当前路由,但是我们知道,`RouterReportManager`绑定depedencyKey是在`Get.find()`,所以4.x.x的改造思路是在find时加上context绑定到正确的路由上,那么现在的做法需要怎么做呢,首先我们假定`RouterReportManager`中currentRoute不可信,[问题见](https://github.com/jonataslaw/getx/issues/1927). 可信的routeName从哪里获取,`Bind .put() or .lazyPut() `时一定是对的,所以需要在`RouterReportManager`中维护一个`Map<BindRoute,epedencyKey>`来维系对应路由  
     ```dart
       class RouterReportManager<T> {
        ...
        ///保存bind 加载的depedencyKey,绑定到对应的context.route上
        final Map<String, T> _depeKey2BindRoute = {};
        ...

        ///获取可能bind的route
        T? _bindRoute(String depedencyKey) => _depeKey2BindRoute[depedencyKey]??_current;

        ///上报依赖绑定的对应的bindContext.route
        void reportDepeKey2BindRoute(String depedencyKey, T? routeName) {
          if (!_depeKey2BindRoute.containsKey(depedencyKey)) {
            if (routeName != null) {
              _depeKey2BindRoute.addAll({depedencyKey: routeName});
            }
          }
        }
        ///Get.find 时 修正绑定的route
        void reportDependencyLinkedToRoute(String depedencyKey) {
          final _bind = _bindRoute(depedencyKey);
          if (_bind == null) return;
          if (_routesKey.containsKey(_bind ?? _current)) {
            _routesKey[_bind]!.add(depedencyKey);
          } else {
            _routesKey[_bind] = <String>[depedencyKey];
          }
        }
      }
     ```
     还剩一个问题,怎么调用`reportDepeKey2BindRoute()`上报  
     ```dart
      static Bind lazyPut<S>(InstanceBuilderCallback<S> builder, {
        String? tag,
        bool fenix = true,
        // VoidCallback? onInit,
        VoidCallback? onClose,
        bool autoRemove = true, //tip 业务会用到,直接在源码上修改开出去使用
      }) {
        Get.lazyPut<S>(builder, tag: tag, fenix: fenix);
        return _FactoryBind<S>(
          tag: tag,
          autoRemove: autoRemove,
          initState: (_) {
            //onInit
            //不能在initState中调用context.dependOnInheritedWidgetOfExactType,所以加个帧回调
            //上报
            SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
              RouterReportManager.instance
                  .reportDepeKey2BindRoute(Get.getKey(S, tag), ModalRoute.of(_));
            });
          },
          dispose: (_) {
            onClose?.call();
          },
        );
      }
     ```  
     到此为,改造完成,业务使用,例:  
     ```dart
      class LoginBinding extends Binding {
        @override
        List<Bind> dependencies() {
          return [
            Bind.lazyPut(() => LoginController()),
          ];
        }
      }
     ```  
     `GetView`不需要丑陋的继承context,也能在find时找到正确的context2bind   
4. #### 尾声    
    纯个人理解,难免片面或者有误,有不同的看法多多交流,谢谢