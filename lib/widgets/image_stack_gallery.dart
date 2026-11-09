import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'image_grid.dart';
import 'net_image.dart';
import 'image_stack_mode_toggle.dart';

typedef StackImageProviderBuilder =
    ImageProvider<Object> Function(String url, int decodeWidth);

/// B 方案「画框」: 一组图共用一个中位比例画框, 翻页时版面不动。
/// 展开为纵向原比例列表; 过渡用「揭幕线」—— 舞台高度弹簧 + 裁剪,
/// 全体卡片与高度同拍位移动画, 线下不可见, 没有交叉飞行也没有空白淡窗。
class ImageStackGallery extends StatefulWidget {
  final List<String> urls;
  final List<String> gallery;
  final int galleryStartIndex;
  final bool compact;
  final bool? expanded;
  final ValueChanged<bool>? onExpandedChanged;
  @visibleForTesting
  final StackImageProviderBuilder? imageProviderBuilder;

  const ImageStackGallery({
    super.key,
    required this.urls,
    required this.gallery,
    required this.galleryStartIndex,
    this.compact = false,
    this.expanded,
    this.onExpandedChanged,
    this.imageProviderBuilder,
  }) : assert(urls.length >= 2);

  @override
  State<ImageStackGallery> createState() => _ImageStackGalleryState();
}

/// 展开态单张自然比例图(外层延展行与对照场景复用)。
class ImageStackExpandedImage extends StatelessWidget {
  final String url;
  final List<String> gallery;
  final int galleryIndex, index, total;
  final bool compact;
  final StackImageProviderBuilder? imageProviderBuilder;
  const ImageStackExpandedImage({
    super.key,
    required this.url,
    required this.gallery,
    required this.galleryIndex,
    required this.index,
    required this.total,
    this.compact = false,
    this.imageProviderBuilder,
  });

  void _open(BuildContext context) {
    if (!context.mounted ||
        galleryIndex < 0 ||
        galleryIndex >= gallery.length) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ImageViewerPage(urls: gallery, initialIndex: galleryIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final t = AppTokens.of(context);
      final width = constraints.maxWidth;
      final decode = boundedImageDecodeWidth(
        width,
        MediaQuery.devicePixelRatioOf(context),
      );
      final radius = BorderRadius.circular(
        compact ? AppRadii.sm - 2 : AppRadii.sm,
      );
      Widget frame(Widget child) => Semantics(
        container: true,
        image: true,
        button: true,
        label: '查看连续图片第 ${index + 1} 张，共 $total 张',
        onTap: () => _open(context),
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: () => _open(context),
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: t.shadowE1,
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: t.separator,
                      width: AppSpace.hairline,
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
      Widget placeholder(String label) => frame(
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Semantics(
            label: label,
            child: ColoredBox(
              color: t.fill,
              child: Center(child: Icon(AppIcons.image, color: t.text3)),
            ),
          ),
        ),
      );
      return Image(
        image:
            imageProviderBuilder?.call(url, decode) ??
            boundedNetworkImageBox(url, decode, 2048),
        width: width,
        fit: BoxFit.fitWidth,
        filterQuality: FilterQuality.low,
        gaplessPlayback: false,
        excludeFromSemantics: true,
        frameBuilder: (context, child, number, sync) =>
            number != null || sync ? frame(child) : placeholder('图片加载中'),
        errorBuilder: (context, _, _) => placeholder('图片暂时无法加载'),
      );
    },
  );
}

// ---------------------------------------------------------------- geometry

/// 一张卡的全量位姿。全部通道走同一条 reveal 弹簧, 翻页插值时天然同步。
class _Geom {
  final double x, y, w, h, s, o, veil, amb;
  const _Geom(
    this.x,
    this.y,
    this.w,
    this.h, {
    this.s = 1,
    this.o = 1,
    this.veil = 0,
    this.amb = 0,
  });

  static _Geom lerp(_Geom a, _Geom b, double t) => _Geom(
    a.x + (b.x - a.x) * t,
    a.y + (b.y - a.y) * t,
    a.w + (b.w - a.w) * t,
    a.h + (b.h - a.h) * t,
    s: a.s + (b.s - a.s) * t,
    o: a.o + (b.o - a.o) * t,
    veil: a.veil + (b.veil - a.veil) * t,
    amb: a.amb + (b.amb - a.amb) * t,
  );

  /// 静止速度向量(每维 px/s), 只给 x 维注入翻页释放速度。
  static _Geom vx(double x) => _Geom(x, 0, 0, 0, s: 0, o: 0, veil: 0, amb: 0);
}

final _geomConverter = MotionConverter<_Geom>.custom(
  normalize: (g) => [g.x, g.y, g.w, g.h, g.s, g.o, g.veil, g.amb],
  denormalize: (v) =>
      _Geom(v[0], v[1], v[2], v[3], s: v[4], o: v[5], veil: v[6], amb: v[7]),
);

/// 每张图的观测状态: 64px 探针取比例(画框取中位数), 显示后回填原始宽。
class _PhotoVM {
  final String url;
  double ratio = 4 / 3;
  bool ratioKnown = false;
  bool failed = false;
  bool probing = false;
  double natW = double.infinity; // 物理像素; 未知前不设小图上限
  _PhotoVM(this.url);
}

class _CardRig {
  final int i;
  final MotionController<_Geom> geom;
  _CardRig(this.i, this.geom);
  bool get moving => geom.isAnimating;
  _Geom get g => geom.value;
  void dispose() => geom.dispose();
}

enum _StackMode { deck, toList, list, toStack }

class _ImageStackGalleryState extends State<ImageStackGallery>
    with TickerProviderStateMixin {
  /// 独立命名空间: 避免与子树内 Scrollable 的 PageStorage 偏移条目冲突。
  static const _storageId = 'image-stack-state';
  static const _longRatio = 0.4;
  static const _flickSpeed = 450.0;

  late List<_PhotoVM> _photos;
  List<_CardRig> _rigs = [];
  Listenable? _tick;

  _StackMode _mode = _StackMode.deck;
  late final SingleMotionController _modeT;
  late final SingleMotionController _hV;
  bool _hVActive = false;
  bool _isTrans = false;
  int _index = 0;
  int _viewIndex = 0;
  bool _restored = false;
  bool _expanded = false;
  double _stageW = 0;
  double? _pixelRatio;
  double _dragAccum = 0;

  // 收起锚定: 过渡中以锚点卡的位移补偿外层滚动, 不把读者带回组顶。
  int? _anchorK;
  double _anchorScroll0 = 0;
  double _anchorY0 = 0;
  late final SingleMotionController _anchorExtra;
  bool _userDriving = false;

  final _riffleTimers = <Timer>{};

  ScrollPosition? _scrollPos;
  /// 外层滚动变化信号: 悬浮行子树订阅它, 逐帧重算吸附位置。
  /// 值为自增 tick 而非滚动值: 每次滚动 tick 必变, 保证必通知。
  final ValueNotifier<int> _scrollSignal = ValueNotifier<int>(0);
  bool _metricsPending = false;
  Set<int> _visibleCards = const {};

  bool get _reduced => MediaQuery.disableAnimationsOf(context);
  bool get _isListLike =>
      _mode == _StackMode.list || _mode == _StackMode.toList;
  bool get _deckLike => _mode == _StackMode.deck || _mode == _StackMode.toStack;
  double get _peek => widget.compact ? 6 : 8;
  double get _thumbH => widget.compact ? 30.0 : 36.0;
  double get _rowTotal => _thumbH + 16;

  @override
  void initState() {
    super.initState();
    _photos = [for (final url in widget.urls) _PhotoVM(url)];
    _modeT = SingleMotionController(
      motion: AppMotion.reveal,
      vsync: this,
      initialValue: 0,
    );
    _hV = SingleMotionController(
      motion: AppMotion.reveal,
      vsync: this,
      initialValue: 0,
    );
    _anchorExtra = SingleMotionController(
      motion: AppMotion.reveal,
      vsync: this,
      initialValue: 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_restored) {
      _restored = true;
      final saved = PageStorage.maybeOf(context)?.readState(
        context,
        identifier: _storageId,
      );
      if (saved is Map) {
        _expanded = saved['expanded'] == true;
        final index = saved['current'];
        if (index is int) _index = index.clamp(0, widget.urls.length - 1);
      }
      _viewIndex = _index;
      if (_expanded && _mode == _StackMode.deck) {
        _mode = _StackMode.list;
        _modeT.value = 1;
      }
      _save(); // 把 clamp 后的选择写回, 外部读 PageStorage 与状态一致
      _probeAround(_index);
      // 首帧测量吸附线: 展开态悬浮行依赖它, 没有它行会落到舞台外。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleMetrics();
      });
    }
    _observeScroll();
  }

  @override
  void didUpdateWidget(ImageStackGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls)) {
      final previous =
          oldWidget.urls[_index.clamp(0, oldWidget.urls.length - 1)];
      final positional =
          _index < widget.urls.length && widget.urls[_index] == previous;
      if (!positional) {
        final first = widget.urls.indexOf(previous);
        final unique = first >= 0 && widget.urls.lastIndexOf(previous) == first;
        _index = unique ? first : _index.clamp(0, widget.urls.length - 1);
      }
      _viewIndex = _index;
      _cancelRiffle();
      // 先换照片列表再重建 rigs, 两者数量始终一致。
      _photos = [for (final url in widget.urls) _PhotoVM(url)];
      _forceMode(_StackMode.deck);
      _probeAround(_index);
      _save();
    } else if (oldWidget.compact != widget.compact ||
        oldWidget.imageProviderBuilder != widget.imageProviderBuilder) {
      _probeAround(_index);
    }
    final want = widget.expanded;
    if (want != null && want != _isListLike && !_transitioning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && want != _isListLike) _toggle();
      });
    }
    _observeScroll();
  }

  bool get _transitioning =>
      _mode == _StackMode.toList || _mode == _StackMode.toStack;

  void _forceMode(_StackMode mode) {
    _mode = mode;
    _isTrans = false;
    _hVActive = false;
    _anchorK = null;
    _modeT.value = mode == _StackMode.list ? 1 : 0;
    if (_stageW > 0) {
      _rebuildRigs();
      if (mode == _StackMode.deck) _setValues(_posesDeck(_index));
    }
  }

  @override
  void dispose() {
    _cancelRiffle();
    _detachScroll();
    _scrollSignal.dispose();
    _modeT.dispose();
    _hV.dispose();
    _anchorExtra.dispose();
    for (final rig in _rigs) {
      rig.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- probing

  /// 只探测当前位附近的窗口(±10): 真实组通常 ≤20 张可全覆盖,
  /// 千张极端组也不会一次发起全部 64px 解码; 中位数随窗口推进逐步补全。
  void _probeAround(int center) {
    final lo = math.max(0, center - 10);
    final hi = math.min(_photos.length - 1, center + 10);
    for (var i = lo; i <= hi; i++) {
      final vm = _photos[i];
      if (!vm.ratioKnown && !vm.failed && !vm.probing) _probe(vm);
    }
  }

  /// 64px 小解码只用来取宽高比: 中位画框、长图判定、展开列表行高都靠它。
  void _probe(_PhotoVM vm) {
    vm.probing = true;
    final provider =
        widget.imageProviderBuilder?.call(vm.url, 64) ??
        boundedNetworkImageBox(vm.url, 64, 128);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        vm.ratio = info.image.width / info.image.height;
        vm.ratioKnown = true;
        vm.failed = false;
        vm.probing = false;
        info.dispose();
        stream.removeListener(listener);
        if (mounted) _onRatiosChanged();
      },
      onError: (_, _) {
        stream.removeListener(listener);
        vm.failed = true;
        vm.probing = false;
        if (mounted) _onRatiosChanged();
      },
    );
    stream.addListener(listener);
  }

  /// 中位比例变化 → 画框随弹簧过渡(规格: 比例随到达重新取中位数)。
  void _onRatiosChanged() {
    if (_transitioning) return;
    _apply(_deckLike ? _posesDeck(_index) : _posesList(), spring: true);
  }

  // ---------------------------------------------------------------- geometry

  double get _capHUse => widget.compact
      ? math.min(_stageW * 1.1, 280.0)
      : math.min(_stageW * 1.25, 400.0);

  double _medianRatio() {
    final rs = _photos.map((p) => p.ratio).toList()..sort();
    if (rs.isEmpty) return 4 / 3;
    final m = rs.length >> 1;
    return rs.length % 2 == 1 ? rs[m] : (rs[m - 1] + rs[m]) / 2;
  }

  ({double fw, double fh}) get _frame {
    final fw = math.max(1.0, _stageW - _peek * 2);
    final r = _medianRatio().clamp(0.8, 16 / 9);
    // 上限优先: 宽版心时下限(fw*0.5625)可能超过 cap, 画框仍以 cap 为准。
    final capH = _capHUse;
    final fh = (fw / r).clamp(math.min(fw * 0.5625, capH).toDouble(), capH);
    return (fw: fw, fh: fh);
  }

  List<_Geom> _posesDeck(int k, {bool gather = false}) {
    final f = _frame;
    final n = _photos.length;
    return [
      for (var i = 0; i < n; i++)
        () {
          final d = i - k;
          if (d == 0) return _Geom(0, 0, f.fw, f.fh, amb: 1);
          if (d > 0 || gather) {
            final dd = d > 0 ? math.min(d, 2) : 2;
            return _Geom(
              dd * _peek,
              0,
              f.fw,
              f.fh,
              s: dd == 1 ? 0.955 : 0.91,
              o: d >= 1 && d <= 2 ? 1 : 0,
              veil: dd == 1 ? 0.26 : 0.48,
              amb: 1,
            );
          }
          return _Geom(-f.fw - 64, 0, f.fw, f.fh, o: d == -1 ? 1 : 0, amb: 1);
        }(),
    ];
  }

  /// 展开列表尺寸: 统一铺满版心(与画框同宽), 高度按比例, 不缩窄。
  Size _listBox(_PhotoVM p) {
    final w = _stageW;
    return Size(math.max(w, 1.0), math.max(w / p.ratio, 1.0));
  }

  List<_Geom> _posesList() {
    final gap = widget.compact ? 8.0 : 12.0;
    var y = 0.0;
    final out = <_Geom>[];
    for (final p in _photos) {
      final size = _listBox(p);
      out.add(_Geom((_stageW - size.width) / 2, y, size.width, size.height));
      y += size.height + gap;
    }
    return out;
  }

  double get _listTotal {
    final last = _posesList().last;
    return last.y + last.h;
  }

  /// 画框内图片矩形: 完整显示不裁切, 空余交给氛围色;
  /// 只有长图(ratio < 0.4)铺满框宽从顶部截取, 展开/查看器仍完整显示。
  Rect _innerRect(_PhotoVM p, double w, double h) {
    final ih = w / p.ratio;
    if (ih <= h) {
      return Rect.fromLTWH(0, (h - ih) / 2, w, ih); // 宽受限: 纵向居中
    }
    if (p.ratio >= _longRatio) {
      final iw = h * p.ratio;
      return Rect.fromLTWH((w - iw) / 2, 0, iw, h); // 高受限: 横向居中
    }
    return Rect.fromLTWH(0, 0, w, h); // 长图: 顶对齐, 其余交给 cover 裁切
  }

  double _envelope() {
    if (_deckLike) {
      final poses = _posesDeck(_index);
      var top = 1.0;
      for (var d = 0; d <= 2 && _index + d < poses.length; d++) {
        final g = poses[_index + d];
        top = math.max(top, g.y + g.h * (1 + g.s) / 2);
      }
      return top;
    }
    return _listTotal;
  }

  // ---------------------------------------------------------------- applying

  void _rebuildRigs() {
    for (final rig in _rigs) {
      rig.dispose();
    }
    final poses = _deckLike ? _posesDeck(_index) : _posesList();
    _rigs = [
      for (var i = 0; i < _photos.length; i++)
        _CardRig(
          i,
          MotionController<_Geom>.motionPerDimension(
            motionPerDimension: List.filled(8, AppMotion.reveal),
            vsync: this,
            converter: _geomConverter,
            initialValue: poses[i],
          ),
        ),
    ];
    _tick = Listenable.merge([
      for (final rig in _rigs) rig.geom,
      _modeT,
      _hV,
      _anchorExtra,
    ]);
  }

  void _apply(
    List<_Geom> poses, {
    bool spring = true,
    int? velocityCard,
    double velocityX = 0,
    List<Duration>? delays,
  }) {
    for (var i = 0; i < _rigs.length && i < poses.length; i++) {
      final rig = _rigs[i];
      final target = poses[i];
      if (!_reduced && spring) {
        final velocity = velocityCard == i ? _Geom.vx(velocityX) : _Geom.vx(0);
        final delay = delays == null || i >= delays.length
            ? Duration.zero
            : delays[i];
        if (delay == Duration.zero) {
          rig.geom.animateTo(target, withVelocity: velocity);
        } else {
          late final Timer timer;
          timer = Timer(delay, () {
            _riffleTimers.remove(timer);
            if (mounted) rig.geom.animateTo(target);
          });
          _riffleTimers.add(timer);
        }
      } else {
        rig.geom.value = target;
      }
    }
  }

  void _setValues(List<_Geom> poses) {
    for (var i = 0; i < _rigs.length && i < poses.length; i++) {
      _rigs[i].geom.value = poses[i];
    }
  }

  void _cancelRiffle() {
    for (final t in _riffleTimers) {
      t.cancel();
    }
    _riffleTimers.clear();
  }

  void _save() => PageStorage.maybeOf(
    context,
  )?.writeState(context, {'current': _index, 'expanded': _isListLike},
      identifier: _storageId);

  // ---------------------------------------------------------------- paging

  void _setIndex(
    int n, {
    double velocityX = 0,
    int? velocityCard,
    bool immediate = false,
  }) {
    n = n.clamp(0, _photos.length - 1);
    final prev = _index;
    if (n == prev && !immediate) return;
    _index = n;
    _viewIndex = n;
    _cancelRiffle();
    List<Duration>? delays;
    if (!immediate && (n - prev).abs() > 1) {
      // riffle: 中间的卡依次翻过, 而不是瞬移。
      delays = [
        for (var i = 0; i < _photos.length; i++)
          Duration(
            milliseconds:
                (n > prev
                    ? (i - prev).clamp(0, n - prev)
                    : (prev - 1 - i).clamp(0, prev - n)) *
                34,
          ),
      ];
    }
    _apply(
      _posesDeck(n),
      spring: !immediate,
      velocityCard: velocityCard,
      velocityX: velocityX,
      delays: delays,
    );
    _probeAround(n);
    _save();
    _scheduleMetrics();
  }

  void _next() {
    if (_isListLike) {
      _goToList(_viewIndex + 1);
    } else {
      _setIndex(_index + 1);
    }
  }

  void _previous() {
    if (_isListLike) {
      _goToList(_viewIndex - 1);
    } else {
      _setIndex(_index - 1);
    }
  }

  /// 叠放态点缩略条 → 跳张; 列表态 → 滚动定位。
  void _goTo(int i) {
    i = i.clamp(0, _photos.length - 1);
    if (_isListLike) {
      if (i != _viewIndex) {
        _viewIndex = i;
        _scrollToCard(i);
        _save();
      }
    } else if (_mode == _StackMode.deck) {
      if (i == _index) {
        _nudge(_index == 0 ? 1 : -1);
      } else {
        _setIndex(i);
      }
    }
  }

  void _goToList(int i) {
    i = i.clamp(0, _photos.length - 1);
    _viewIndex = i;
    _scrollToCard(i);
    _save();
  }

  /// 边界反馈: 没有更多了, 带初速弹回原位(纯阻尼回摆)。
  void _nudge(int dir) {
    if (_reduced) return;
    final rig = _rigs[_index];
    rig.geom.animateTo(rig.g, withVelocity: _Geom.vx(dir * 520));
  }

  // ---------------------------------------------------------------- gestures

  double _rubber(double x, double d) => (1 - 1 / (x * 0.55 / d + 1)) * d * 1.1;

  void _dragTo(double dx) {
    if (!_deckLike) return;
    final k = _index;
    final dir = dx < 0 ? 1 : -1;
    final t = k + dir;
    final a = _posesDeck(k);
    if (t < 0 || t >= _photos.length) {
      final rx = _rubber(dx, _stageW * 0.9);
      _setValues([
        for (var i = 0; i < a.length; i++)
          i == k ? _withX(a[i], a[i].x + rx) : a[i],
      ]);
      return;
    }
    final b = _posesDeck(t);
    final raw = (dx.abs() / (_stageW * 0.9)).clamp(0.0, 1.0);
    final poses = [
      for (var i = 0; i < a.length; i++) _Geom.lerp(a[i], b[i], raw),
    ];
    if (dir == 1) {
      // 当前画框 1:1 跟手(B 版不倾斜)。
      poses[k] = _withX(a[k], a[k].x + dx);
    } else {
      final over = raw >= 1 ? _rubber((raw - 1) * _stageW, _stageW) : 0.0;
      poses[t] = _withX(
        _Geom.lerp(a[t], b[t], raw),
        a[t].x + (b[t].x - a[t].x) * math.min(raw, 1.0) + over,
      );
    }
    _setValues(poses);
  }

  static _Geom _withX(_Geom g, double x) =>
      _Geom(x, g.y, g.w, g.h, s: g.s, o: g.o, veil: g.veil, amb: g.amb);

  void _release(double dx, double vx) {
    final k = _index;
    final dir = dx < 0 ? 1 : -1;
    final t = k + dir;
    if (t < 0 || t >= _photos.length) {
      _apply(_posesDeck(k), spring: true, velocityCard: k, velocityX: vx);
      return;
    }
    final raw = dx.abs() / (_stageW * 0.9);
    final flick = vx.abs() > _flickSpeed && vx.sign == dx.sign;
    final against = vx.abs() > 300 && vx.sign != dx.sign;
    final commit = !against && (raw > 0.3 || flick);
    final mover = dir == 1 ? k : t;
    if (commit) {
      _setIndex(t, velocityCard: mover, velocityX: vx);
    } else {
      _apply(_posesDeck(k), spring: true, velocityCard: mover, velocityX: vx);
    }
  }

  void _handleCardTap(int i) {
    if (_isListLike) {
      _open(i);
      return;
    }
    if (_mode != _StackMode.deck) return;
    final d = i - _index;
    if (d == 0) {
      _open(i);
    } else if (d > 0) {
      _setIndex(i);
    }
  }

  void _open(int index) {
    if (!mounted || index < 0 || index >= widget.urls.length) return;
    final galleryIndex = widget.galleryStartIndex + index;
    if (galleryIndex < 0 || galleryIndex >= widget.gallery.length) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ImageViewerPage(urls: widget.gallery, initialIndex: galleryIndex),
      ),
    );
  }

  // ---------------------------------------------------------------- expand

  void _toggle() {
    _cancelRiffle();
    if (_isListLike) {
      _collapse();
    } else {
      _expand();
    }
  }

  void _expand() {
    if (_transitioning) return;
    final k = _index;
    // 揭幕线起点是当前画框高度: 必须在切换 _mode 前取值, 否则
    // _envelope() 已按列表态返回全高, 高度瞬间跳满、展开动画被吞掉。
    _hV.value = _envelope();
    _viewIndex = k;
    _mode = _StackMode.toList;
    _isTrans = true;
    _hVActive = true;
    _anchorK = k;
    _anchorScroll0 = _scrollPos?.pixels ?? 0;
    _anchorY0 = _rigs.isEmpty ? 0 : _rigs[k].g.y;
    _anchorExtra.value = 0;
    final poses = _posesList();
    final last = poses.last;
    widget.onExpandedChanged?.call(true);
    if (_reduced) {
      _hV.value = last.y + last.h;
      _modeT.value = 1;
      _apply(poses, spring: false);
      _settle();
      return;
    }
    _hV.animateTo(last.y + last.h);
    _modeT.animateTo(1);
    final extra = _collapseExtra(k);
    if (extra != 0) _anchorExtra.animateTo(extra);
    _apply(poses, spring: true);
    _save();
  }

  void _collapse() {
    if (_transitioning) return;
    final k = _mode == _StackMode.list ? _collapseAnchor() : _index;
    // 揭幕线起点是当前列表总高: 同样必须在切换 _mode 前取值, 否则舞台
    // 高度瞬间收到画框高度, 收起动画整个被跳过, 页面表现为滚动跳变。
    _hV.value = _isListLike ? _listTotal : _envelope();
    _index = k;
    _viewIndex = k;
    _mode = _StackMode.toStack;
    _isTrans = true;
    _hVActive = true;
    final poses = _posesDeck(k, gather: true);
    // 窗口外的卡不参与聚拢: 多卡飞向同一槽位会先叠在前方再消失。
    // 它们保持当前几何原地淡出, 由过渡窗口规则在 settle 后卸载。
    for (var i = 0; i < poses.length; i++) {
      if ((i - k).abs() <= 2) continue;
      final g = _rigs[i].g;
      poses[i] = _Geom(g.x, g.y, g.w, g.h, s: g.s, o: 0, veil: g.veil, amb: g.amb);
    }
    _anchorK = k;
    _anchorScroll0 = _scrollPos?.pixels ?? 0;
    _anchorY0 = _rigs.isEmpty ? 0 : _rigs[k].g.y;
    _anchorExtra.value = 0;
    widget.onExpandedChanged?.call(false);
    final f = _frame;
    if (_reduced) {
      _hV.value = f.fh;
      _modeT.value = 0;
      _apply(poses, spring: false);
      _settle();
      return;
    }
    _hV.animateTo(f.fh);
    _modeT.animateTo(0);
    final extra = _collapseExtra(k);
    if (extra != 0) _anchorExtra.animateTo(extra);
    _apply(poses, spring: true);
    _save();
  }

  /// 画框落点若被工具栏/顶栏遮挡, 把整组推进可视带。
  double _collapseExtra(int k) {
    final pos = _scrollPos;
    final viewport = _viewportHeight;
    final box = context.findRenderObject();
    if (pos == null || viewport == null || box is! RenderBox || !box.attached) {
      return 0;
    }
    final galleryTop = box.localToGlobal(Offset.zero).dy;
    final cardTop = galleryTop + _rigs[k].g.y;
    final minTop = _reserveTop;
    // 画框底(+行间距)不得越过悬浮行吸底线: 吸底线含底部安全区, 与
    // _measureStickyBar 同一算法。越过时行在过渡中被钉在吸底线、压在
    // 图片上, settle 后再下坠一段。
    final barTop = viewport - MediaQuery.paddingOf(context).bottom - _reserveBottom;
    final maxTop = math.max(minTop, barTop - _rowTotal - 6 - _frame.fh - 6);
    return cardTop - cardTop.clamp(minTop, maxTop);
  }

  double get _reserveTop => 60;
  double get _reserveBottom => 134;

  double? get _viewportHeight {
    final pos = _scrollPos;
    if (pos != null && pos.hasViewportDimension) return pos.viewportDimension;
    final size = MediaQuery.sizeOf(context);
    return size.height - MediaQuery.paddingOf(context).vertical;
  }

  /// 收起锚: 选中卡仍在视口内就保留选中; 已滚出视口(长列表)时才锚到
  /// 屏幕中部那张, 不把读者带回组顶部。
  int _collapseAnchor() {
    final view = _viewIndex;
    if (view >= 0 && view < _rigs.length) {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached) return view;
      final origin = box.localToGlobal(Offset.zero).dy;
      final viewport = _viewportHeight ?? 600;
      final g = _rigs[view].g;
      final top = origin + g.y;
      final bottom = top + g.h;
      if (bottom > 0 && top < viewport) return view;
    }
    return _cardInView();
  }

  int _cardInView() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return _viewIndex;
    final origin = box.localToGlobal(Offset.zero).dy;
    final viewport = _viewportHeight ?? 600;
    final line = origin + viewport * 0.4;
    var best = _viewIndex;
    var bestD = double.infinity;
    for (final rig in _rigs) {
      final g = rig.g;
      final top = origin + g.y;
      final bottom = top + g.h;
      final d = line >= top && line <= bottom
          ? -1.0
          : math.min((top - line).abs(), (bottom - line).abs());
      if (d < bestD) {
        bestD = d;
        best = rig.i;
      }
    }
    return best;
  }

  void _scrollToCard(int i) {
    final pos = _scrollPos;
    final box = context.findRenderObject();
    if (pos == null || box is! RenderBox || !box.attached) return;
    final g = _rigs[i].g;
    final origin = box.localToGlobal(Offset.zero).dy;
    final viewport = _viewportHeight ?? 600;
    final visTop = _reserveTop;
    final visBot = viewport - _reserveBottom;
    final cardTop = origin + g.y;
    final cardBottom = cardTop + g.h;
    double target = pos.pixels;
    if (g.h > visBot - visTop || cardTop < visTop) {
      target = pos.pixels + cardTop - visTop;
    } else if (cardBottom > visBot) {
      target = pos.pixels + cardBottom - visBot;
    }
    final clamped = target.clamp(0.0, pos.maxScrollExtent);
    if (_reduced) {
      pos.jumpTo(clamped);
    } else {
      pos.animateTo(
        clamped,
        duration: AppMotion.revealDuration,
        curve: AppMotion.revealCurve,
      );
    }
  }

  /// 过渡收尾: 移除揭幕裁剪, 落回稳态。
  void _settle() {
    if (!mounted || !_transitioning) return;
    final goingList = _mode == _StackMode.toList;
    setState(() {
      _mode = goingList ? _StackMode.list : _StackMode.deck;
      _isTrans = false;
      _hVActive = false;
      _anchorK = null;
      if (!goingList) _setValues(_posesDeck(_index));
    });
    _save();
    _scheduleMetrics();
  }

  // ---------------------------------------------------------------- scroll

  void _observeScroll() {
    final pos = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (identical(pos, _scrollPos)) return;
    _detachScroll();
    _scrollPos = pos;
    pos?.addListener(_onOuterScroll);
    _scheduleMetrics();
  }

  void _detachScroll() {
    _scrollPos?.removeListener(_onOuterScroll);
    _scrollPos = null;
  }

  void _onOuterScroll() {
    // 行子树直接跟随滚动: 吸附线按实时 pixels 现算, 与本次布局同帧一致,
    // 惯性滚动的仅布局帧也不会让行随内容漂移。
    _scrollSignal.value = _scrollSignal.value + 1;
    _scheduleMetrics();
  }

  void _scheduleMetrics() {
    if (_metricsPending) return;
    _metricsPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsPending = false;
      if (!mounted) return;
      _updateVisibleCards();
    });
  }

  /// 按位姿决定哪些卡挂真图: 画框态保留当前张前后窗口(供 riffle 与滑入),
  /// 列表态只挂视口上下约 1.5 屏内的卡, 千张长组也不会铺满解码请求。
  /// 同时测量缩略条的吸附线(布局完成后的全局位置, build 只读结果)。
  void _updateVisibleCards() {
    _measureStickyBar();
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || _rigs.isEmpty) return;
    Set<int> next;
    // 过渡中沿用列表窗口: 收起第一帧若直接切 deck 窗口, 窗口外的卡会
    // 被瞬间卸载闪没; 它们原地淡出, settle 后再按 deck 窗口收窄。
    if (_deckLike && !_isTrans) {
      final k = _index;
      next = {
        for (var i = k - 2; i <= k + 2; i++)
          if (i >= 0 && i < _rigs.length) i,
      };
    } else {
      final pos = _scrollPos;
      if (pos == null) return;
      final origin = box.localToGlobal(Offset.zero).dy;
      final viewport = pos.viewportDimension;
      final lo = -origin - viewport * 1.5;
      final hi = -origin + viewport * 2.5;
      final gap = widget.compact ? 8.0 : 12.0;
      var minY = 0.0;
      next = {};
      for (var i = 0; i < _photos.length; i++) {
        final size = _listBox(_photos[i]);
        if (minY > hi) break;
        if (minY + size.height >= lo) next.add(i);
        minY += size.height + gap;
      }
    }
    if (!setEquals(next, _visibleCards)) {
      setState(() => _visibleCards = next);
    }
    for (final i in next) {
      _probeAround(i);
    }
  }

  /// 阅读工具栏上方留出缩略条的 gallery 内坐标线; 测不到时保持 null(不吸附)。
  void _measureStickyBar() {
    final box = context.findRenderObject();
    final pos = _scrollPos;
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final viewport = _viewportHeight;
    if (viewport == null || pos == null || !pos.hasViewportDimension) return;
    // 只锚定内容偏移 g0 = galleryTop + pixels: 它对滚动不变, 吸附线在
    // build 里现算 line_screen - (g0 - pixels), 不依赖配对时效。
    // build 之后落地的 jumpTo 会让布局滞后于 pixels, 只有两者同代才可配。
    final g0 = box.localToGlobal(Offset.zero).dy + pos.pixels;
    if (_galleryTop0 == g0) return;
    if (_builtScroll != pos.pixels) {
      _scheduleMetrics();
      return;
    }
    setState(() => _galleryTop0 = g0);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    _pixelRatio = media.devicePixelRatio;
    // 记录本次 build 对应的滚动位置: postFrame 测量以它配对吸底线,
    // 保证 (线, 滚动) 来自同一次布局。
    final builtPos = _scrollPos;
    if (builtPos != null) _builtScroll = builtPos.pixels;
    return FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _PreviousPhotoIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NextPhotoIntent(),
      },
      actions: {
        _PreviousPhotoIntent: CallbackAction<_PreviousPhotoIntent>(
          onInvoke: (_) {
            _previous();
            return null;
          },
        ),
        _NextPhotoIntent: CallbackAction<_NextPhotoIntent>(
          onInvoke: (_) {
            _next();
            return null;
          },
        ),
      },
      child: NotificationListener<UserScrollNotification>(
        onNotification: (n) {
          _userDriving = n.direction != ScrollDirection.idle;
          return false;
        },
        child: Padding(
          padding: EdgeInsets.only(
            top: widget.compact ? 8 : 14,
            bottom: widget.compact ? 10 : 18,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w =
                  constraints.maxWidth.isFinite && constraints.maxWidth > 0
                  ? constraints.maxWidth
                  : 320.0;
              if (w != _stageW) {
                final firstWidth = _stageW == 0;
                _stageW = w;
                if (firstWidth) {
                  _rebuildRigs();
                } else if (_rigs.isNotEmpty) {
                  _apply(
                    _deckLike ? _posesDeck(_index) : _posesList(),
                    spring: _transitioning,
                  );
                }
              }
              _scheduleMetrics();
              return AnimatedBuilder(
                animation: _tick!,
                builder: (context, _) {
                  // 每次内层重建都记录本次所见滚动位置: 过渡中滚动大跳只走
                  // 这里, 外层 build 不重跑; postFrame 吸底线测量以它配对。
                  final tickPos = _scrollPos;
                  if (tickPos != null) _builtScroll = tickPos.pixels;
                  if (_transitioning &&
                      !_modeT.isAnimating &&
                      !_hV.isAnimating &&
                      !_anchorExtra.isAnimating &&
                      _rigs.every((r) => !r.moving)) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _settle(),
                    );
                  }
                  // 锚定补偿: 过渡中锚点卡的 y 变多少, 外层滚动就补多少。
                  // 帧内只算目标值, jumpTo 推迟到帧尾——布局期间动滚动位置
                  // 会让外层监听者(如阅读进度条)在 build 中 setState。
                  final anchorK = _anchorK;
                  if (anchorK != null && !_userDriving) {
                    final pos = _scrollPos;
                    if (pos != null && anchorK < _rigs.length) {
                      final delta =
                          _rigs[anchorK].g.y - _anchorY0 + _anchorExtra.value;
                      final target = (_anchorScroll0 + delta).clamp(
                        0.0,
                        pos.maxScrollExtent,
                      );
                      if ((pos.pixels - target).abs() > 0.2) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          final p = _scrollPos;
                          if (mounted &&
                              p != null &&
                              !p.isScrollingNotifier.value &&
                              (p.pixels - target).abs() > 0.2) {
                            p.jumpTo(target);
                          }
                        });
                      }
                    }
                  }
                  final height = _hVActive
                      ? math.max(1.0, _hV.value)
                      : math.max(1.0, _envelope());
                  // 只挂窗口内的卡: 窗口外的卡在屏外不可见不可点,
                  // 千张长组展开时也不铺满 widget 树。
                  final visibleNow = _visibleCards;
                  final children = [
                    for (final rig in _rigs)
                      if (visibleNow.contains(rig.i)) rig,
                  ]..sort(_zCompare);
                  final stage = SizedBox(
                    key: const ValueKey('image-stack-stage'),
                    width: double.infinity,
                    height: height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [for (final rig in children) _positioned(rig)],
                    ),
                  );
                  final clipped = ClipRect(
                    clipBehavior: _isTrans ? Clip.hardEdge : Clip.none,
                    child: stage,
                  );
                  // 流内占位: 画框态缩略条占布局空间; 过渡中随 reveal 平滑伸缩,
                  // 行本体在悬浮层跟随揭幕线, 不产生瞬移。
                  final rowSpace = _rowTotal + 8;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                            container: true,
                            explicitChildNodes: true,
                            label: _isListLike
                                ? '连续图片，第 ${_viewIndex + 1} 张，共 ${widget.urls.length} 张'
                                : '连续图片，第 ${_index + 1} 张，共 ${widget.urls.length} 张',
                            child: _deckLike
                                ? GestureDetector(
                                    behavior: HitTestBehavior.deferToChild,
                                    onHorizontalDragStart: (_) =>
                                        _dragAccum = 0,
                                    onHorizontalDragUpdate: (d) {
                                      _dragAccum += d.delta.dx;
                                      _dragTo(_dragAccum);
                                    },
                                    onHorizontalDragEnd: (d) {
                                      final dx = _dragAccum;
                                      _dragAccum = 0;
                                      _release(
                                        dx,
                                        d.velocity.pixelsPerSecond.dx,
                                      );
                                    },
                                    onHorizontalDragCancel: () =>
                                        _dragAccum = 0,
                                    child: clipped,
                                  )
                                : clipped,
                          ),
                          TweenAnimationBuilder<double>(
                            tween: Tween(end: _deckLike ? rowSpace : 0.0),
                            duration: _reduced
                                ? AppMotion.reducedFade
                                : AppMotion.revealDuration,
                            curve: _reduced
                                ? Curves.easeOut
                                : AppMotion.revealCurve,
                            builder: (_, v, _) => SizedBox(height: v),
                          ),
                        ],
                      ),
                      // 悬浮行不加位置补间: min(画框位, 吸附位)两支各自连续。
                      // 行子树订阅滚动信号: 惯性滚动等仅布局帧也逐帧重算,
                      // 行不随内容漂移; pixels 与布局同帧一致, 无滞后。
                      ValueListenableBuilder<int>(
                        valueListenable: _scrollSignal,
                        builder: (context, _, child) => Positioned(
                          left: 0,
                          right: 0,
                          top: _rowTop(height, rowSpace),
                          child: child!,
                        ),
                        child: _buildRow(context),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// 缩略条吸附: gallery 在滚动内容中的偏移(g0), 由 postFrame 测量锚定——
  /// build 中调用 localToGlobal 会踩到尚未布局的页面转场 box。g0 对滚动
  /// 不变, 行位置在 build 里换算, 滚动补偿跳变不会让行随内容下坠。
  double? _galleryTop0;
  /// 最近一次 build 见到的滚动位置: 配对门闩, 见 _measureStickyBar。
  double _builtScroll = 0;

  double _rowTop(double stageHeight, double rowSpace) {
    final flowTop = stageHeight + 6;
    // 过渡期间与展开态同用吸附线: 收起/展开动画里开关保持在点击时的
    // 视口位置不动, 由舞台内容围绕它收缩; 稳定后回到画框下方。
    if (!_isListLike && !_isTrans) return flowTop;
    final pos = _scrollPos;
    final g0 = _galleryTop0;
    if (g0 == null || pos == null || !pos.hasViewportDimension) {
      return flowTop;
    }
    // 吸底线是视口常量: 底部避开阅读工具栏(与 _collapseExtra 同一预留)。
    final lineScreen =
        pos.viewportDimension -
        MediaQuery.paddingOf(context).bottom -
        _reserveBottom -
        _rowTotal -
        6;
    var top = math.min(flowTop, lineScreen - (g0 - pos.pixels));
    // sticky 不滚出容器(web position:sticky 的语义); 同时命中区域不能超出
    // 外层 Stack(舞台高 + rowSpace)——RenderBox.hitTest 的 size 门槛会挡掉
    // 界外的悬浮行。不得钳回舞台内: 那会把行压进图片, settle 后再下坠。
    final maxTop = math.max(0.0, stageHeight + rowSpace - _rowTotal);
    return top.clamp(0.0, maxTop);
  }

  int _zCompare(_CardRig a, _CardRig b) {
    final c = _zOf(a.i).compareTo(_zOf(b.i));
    return c != 0 ? c : a.i.compareTo(b.i);
  }

  int _zOf(int i) {
    final k = _deckLike ? _index : _viewIndex;
    final d = i - k;
    // 收起聚拢时锚点前方的卡(d<0)也必须画在当前卡之后: 否则它们横穿
    // 舞台时会盖在当前图上再消失。稳定 deck 态 d<0 本就在屏外, 无影响。
    if (_deckLike) return d == 0 ? 100 : 100 - d.abs();
    return d == 0 ? 200 : 100 - d.abs();
  }

  Positioned _positioned(_CardRig rig) {
    final g = rig.g;
    return Positioned(
      key: ValueKey('image-stack-card-${rig.i}'),
      left: g.x,
      top: g.y,
      width: math.max(1.0, g.w),
      height: math.max(1.0, g.h),
      child: Transform.scale(
        scale: g.s,
        alignment: Alignment.centerRight,
        child: _frameCard(rig.i, g),
      ),
    );
  }

  Widget _frameCard(int i, _Geom g) {
    final t = AppTokens.of(context);
    final vm = _photos[i];
    final visible = _visibleCards.contains(i);
    final radius = BorderRadius.circular(
      widget.compact ? AppRadii.sm - 2 : AppRadii.sm,
    );
    final imageRect = _innerRect(vm, g.w, g.h);
    final natH = g.w / vm.ratio;
    final cropped = vm.ratio < _longRatio && g.h < natH - 1;
    final decodeW = boundedImageDecodeWidth(g.w, _pixelRatio ?? 3);

    Widget photo;
    if (!visible) {
      photo = ColoredBox(color: t.fill);
    } else if (vm.failed) {
      // 失败占位保持纯色卡面, 不放图标(整组验收要求画布无图标、无文字)。
      photo = ColoredBox(color: t.fill);
    } else {
      photo = Image(
        key: ValueKey('image-stack-photo-$i'),
        image:
            widget.imageProviderBuilder?.call(vm.url, decodeW) ??
            boundedNetworkImageBox(vm.url, decodeW, 2048),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        // 显示后回填原始宽: 小图不再铺满版心(2 倍像素上限, 不硬放大)。
        // 只有解码宽被源图限制(小于解码上限)时才视为小图, 大图的解码宽是封顶值。
        frameBuilder: (context, child, frame, sync) {
          final raw = child is RawImage ? child.image : null;
          if (raw != null &&
              (frame != null || sync) &&
              raw.width < decodeW - 1 &&
              raw.width < vm.natW) {
            vm.natW = raw.width.toDouble();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _onRatiosChanged();
            });
          }
          return child;
        },
        errorBuilder: (_, _, _) => ColoredBox(
          color: t.fill,
          child: Center(child: Icon(AppIcons.image, color: t.text3)),
        ),
      );
    }

    final ambOpacity = visible ? g.amb.clamp(0.0, 1.0) : 0.0;
    final veilOpacity = g.veil.clamp(0.0, 1.0);
    final listLike = _isListLike;

    final content = Stack(
      fit: StackFit.expand,
      children: [
        // 氛围色: 18px 低清解码放大铺底, 不做实时模糊(性能红线)。
        if (ambOpacity > 0.004)
          IgnorePointer(
            child: Opacity(
              opacity: ambOpacity,
              child: Image(
                image:
                    widget.imageProviderBuilder?.call(vm.url, 18) ??
                    boundedNetworkImageBox(vm.url, 18, 48),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                excludeFromSemantics: true,
                // 氛围层加载失败直接留空, 绝不让默认错误红字进入画布。
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        Positioned.fromRect(rect: imageRect, child: photo),
        if (cropped)
          Positioned(left: 8, bottom: 8, child: _longChip()),
        if (veilOpacity > 0.004)
          IgnorePointer(
            child: ColoredBox(color: t.bg.withValues(alpha: veilOpacity)),
          ),
      ],
    );

    return RepaintBoundary(
      child: Semantics(
        container: true,
        image: true,
        button: true,
        label: listLike
            ? '查看连续图片第 ${i + 1} 张，共 ${widget.urls.length} 张'
            : '查看第 ${i + 1} 张图片',
        onTap: () => _handleCardTap(i),
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: () => _handleCardTap(i),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: t.shadowE1,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: t.separator,
                    width: AppSpace.hairline,
                  ),
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _longChip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppTokens.of(context).scrim,
      borderRadius: BorderRadius.circular(AppRadii.xs),
    ),
    child: Text(
      '长图',
      style: AppType.footnote.copyWith(color: Radix.whiteA12, height: 1.1),
    ),
  );

  // ---------------------------------------------------------------- row

  Widget _buildRow(BuildContext context) {
    final current = _isListLike ? _viewIndex : _index;
    // 缩略条只在堆叠态显示; 展开列表态只保留堆叠开关(位置恒定, 不随态跳),
    // 避免悬浮条压在展开图片上。
    final scrub = AnimatedOpacity(
      opacity: _deckLike ? 1.0 : 0.0,
      duration: _reduced ? AppMotion.reducedFade : AppMotion.fade,
      curve: Curves.easeOut,
      child: IgnorePointer(
        ignoring: !_deckLike,
        child: _ScrubRow(
          photos: _photos,
          current: current,
          thumbH: _thumbH,
          imageProviderBuilder: widget.imageProviderBuilder,
          reduced: _reduced,
          onPick: _goTo,
        ),
      ),
    );
    return Padding(
      key: const ValueKey('image-stack-row'),
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: SizedBox(
        height: _rowTotal,
        child: Row(
          children: [
            Expanded(child: scrub),
            const SizedBox(width: 8),
            ImageStackModeToggle(
              key: const ValueKey('image-stack-mode'),
              expanded: _isListLike,
              onPressed: _toggle,
              total: widget.urls.length,
              progress: _transitioning ? _modeT.value : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 缩略条: 当前张按真实比例展开, 其余压成窄条; 可点可拖, 触控高度 44dp+。
class _ScrubRow extends StatelessWidget {
  final List<_PhotoVM> photos;
  final int current;
  final double thumbH;
  final StackImageProviderBuilder? imageProviderBuilder;
  final bool reduced;
  final ValueChanged<int> onPick;

  const _ScrubRow({
    required this.photos,
    required this.current,
    required this.thumbH,
    required this.imageProviderBuilder,
    required this.reduced,
    required this.onPick,
  });

  /// 长组按均匀采样展示最多 24 条(含首尾); 当前张的条始终保留。
  /// 点选映射回真实索引, 长组也能整条拖动跳转。
  static const _maxThumbs = 24;

  List<int> _shown() {
    final n = photos.length;
    if (n <= _maxThumbs) return [for (var i = 0; i < n; i++) i];
    final sampled = [
      for (var k = 0; k < _maxThumbs; k++)
        (k * (n - 1) / (_maxThumbs - 1)).round(),
    ];
    if (!sampled.contains(current)) {
      var pos = 0;
      while (pos < sampled.length && sampled[pos] < current) {
        pos++;
      }
      sampled.insert(pos, current);
    }
    return sampled;
  }

  List<double> widthsFor(double width) {
    final shown = _shown();
    final n = shown.length;
    if (n == 0) return const [];
    final act = (thumbH * photos[current.clamp(0, photos.length - 1)].ratio)
        .clamp(thumbH * 0.6, thumbH * 2.4);
    const gap = 2.0;
    final others = n - 1;
    final other = others > 0
        ? ((width - act - gap * others) / others).clamp(4.0, thumbH * 0.62)
        : 0.0;
    return [for (final i in shown) i == current ? act : other];
  }

  void _pick(double x, List<double> ws) {
    final shown = _shown();
    var acc = 0.0;
    for (var i = 0; i < ws.length; i++) {
      acc += ws[i] + 2;
      if (x < acc - 1) {
        if (shown[i] != current) onPick(shown[i]);
        return;
      }
    }
    if (ws.isNotEmpty && shown.last != current) onPick(shown.last);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final ws = widthsFor(constraints.maxWidth);
        final shown = _shown();
        final frozen = List<double>.of(ws);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _pick(d.localPosition.dx, frozen),
          onHorizontalDragStart: (d) => _pick(d.localPosition.dx, frozen),
          onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, frozen),
          child: SizedBox(
            height: thumbH + 8,
            // 横向滚动容器当 clip 用: select 弹簧过冲瞬间超出分配宽度的部分
            // 被静默裁掉, 等效 web 版 overflow hidden, 不触发 Flex 溢出断言。
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  for (var i = 0; i < shown.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        right: i == shown.length - 1 ? 0 : 2,
                      ),
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey('scrub-${shown[i]}'),
                        tween: Tween(end: ws[i]),
                        duration: reduced
                            ? AppMotion.reducedFade
                            : AppMotion.curveOf(AppMotion.select).duration,
                        curve: reduced
                            ? Curves.easeOut
                            : AppMotion.curveOf(AppMotion.select),
                        builder: (_, w, _) => Opacity(
                          opacity: shown[i] == current ? 1 : 0.5,
                          child: Container(
                            width: math.max(2.0, w),
                            height: thumbH,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: t.fill,
                              borderRadius: BorderRadius.circular(AppRadii.bar),
                            ),
                            // 长组只有当前条挂真图, 其余压窄条保持纯色,
                            // 解码请求不随组规模增长。
                            child:
                                w > 6 &&
                                    (photos.length <= 12 || shown[i] == current)
                                ? Image(
                                    image:
                                        imageProviderBuilder?.call(
                                          photos[shown[i]].url,
                                          128,
                                        ) ??
                                        boundedNetworkImageBox(
                                          photos[shown[i]].url,
                                          128,
                                          128,
                                        ),
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.low,
                                    gaplessPlayback: true,
                                    excludeFromSemantics: true,
                                    // 缩略失败保持纯色条, 不显示默认错误红字。
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreviousPhotoIntent extends Intent {
  const _PreviousPhotoIntent();
}

class _NextPhotoIntent extends Intent {
  const _NextPhotoIntent();
}
