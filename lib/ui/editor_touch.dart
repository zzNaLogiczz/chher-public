/// 将真实编辑区触摸通知Android；不改变焦点、草稿或输入连接。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/app_log.dart';

typedef EditorTouchBuilder =
    Widget Function(
      BuildContext context,
      FocusNode focusNode,
      VoidCallback onTap,
    );

/// 明确的编辑入口在获得焦点后调用；复用字段自身的生命周期守卫。
abstract final class EditorTouch {
  static void notifyFromUserFocus(BuildContext context, FocusNode focusNode) {
    if (!context.mounted || focusNode.context?.mounted != true) return;
    final guard = focusNode.context!
        .findAncestorStateOfType<_EditorTouchGuardState>();
    if (guard != null && identical(guard._focusNode, focusNode)) {
      guard._scheduleNotification();
    }
  }
}

/// builder须将onTap接到TextField，并启用onTapAlwaysCalled以覆盖已聚焦再点。
class EditorTouchGuard extends StatefulWidget {
  final FocusNode? focusNode;
  final EditorTouchBuilder builder;
  final bool notifyOnUserEntry;
  final bool enabled;

  const EditorTouchGuard({
    super.key,
    this.focusNode,
    this.notifyOnUserEntry = false,
    this.enabled = true,
    required this.builder,
  });

  @override
  State<EditorTouchGuard> createState() => _EditorTouchGuardState();
}

class _EditorTouchGuardState extends State<EditorTouchGuard>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('chh/editor_touch');
  late FocusNode _focusNode;
  int _tapGeneration = 0;
  bool _active = true;
  bool _entryConsumed = false;
  ModalRoute<dynamic>? _route;
  Animation<double>? _waitingAnimation;
  AnimationStatusListener? _waitingListener;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'editor-touch');
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (_route?.isCurrent == false) _cancelPending();
    _notifyEntryIfNeeded();
  }

  @override
  void didUpdateWidget(covariant EditorTouchGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _cancelPending();
      if (oldWidget.focusNode == null) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'editor-touch');
    }
    if (oldWidget.enabled && !widget.enabled) _cancelPending();
    if (oldWidget.notifyOnUserEntry != widget.notifyOnUserEntry) {
      _cancelPending();
      _entryConsumed = false;
      _notifyEntryIfNeeded();
    }
  }

  void _notifyEntryIfNeeded() {
    if (widget.notifyOnUserEntry && !_entryConsumed) {
      _entryConsumed = true;
      _scheduleNotification();
    }
  }

  void _cancelPending() {
    _tapGeneration++;
    if (_waitingListener != null) {
      _waitingAnimation?.removeStatusListener(_waitingListener!);
    }
    _waitingAnimation = null;
    _waitingListener = null;
  }

  void _scheduleNotification() {
    if (!widget.enabled ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _cancelPending();
    final generation = _tapGeneration;
    final target = _focusNode;
    _queueFrame(generation, target);
  }

  void _queueFrame(int generation, FocusNode target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 首帧autofocus由FocusManager的microtask落定，先让它完成再读焦点。
      scheduleMicrotask(() => _notifyAfterFrame(generation, target));
    });
    // 已聚焦的再点击未必产生新帧，不能依赖光标定时器执行通知。
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _notifyAfterFrame(int generation, FocusNode target) {
    if (!mounted ||
        !_active ||
        !widget.enabled ||
        generation != _tapGeneration ||
        !identical(target, _focusNode) ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) ||
        _route?.isCurrent == false) {
      return;
    }
    final animation = _route?.animation;
    if (animation != null && animation.status != AnimationStatus.completed) {
      _waitingAnimation = animation;
      late final AnimationStatusListener listener;
      listener = (status) {
        if (status != AnimationStatus.completed) return;
        animation.removeStatusListener(listener);
        if (!identical(_waitingListener, listener)) return;
        _waitingAnimation = null;
        _waitingListener = null;
        _queueFrame(generation, target);
      };
      _waitingListener = listener;
      animation.addStatusListener(listener);
      return;
    }
    if (target.context?.mounted != true || !target.hasFocus) return;
    unawaited(_notifyNative());
  }

  Future<void> _notifyNative() async {
    try {
      await _channel.invokeMethod<bool>('editorTapped');
    } catch (error) {
      // 通知失败不影响标准输入流程，不重试、不改用户输入状态。
      AppLog.w('IME', '编辑区触摸通知失败 ${error.runtimeType}');
    }
  }

  @override
  void deactivate() {
    _active = false;
    _cancelPending();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 只撤销离开前台的旧意图；恢复前台不会自动显示键盘或抢焦点。
    if (state != AppLifecycleState.resumed) _cancelPending();
  }

  @override
  void dispose() {
    _cancelPending();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _focusNode, _scheduleNotification);
}
