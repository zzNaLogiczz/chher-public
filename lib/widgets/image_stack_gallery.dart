import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show listEquals, setEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../ui/reading_bar.dart';

import 'package:flutter/services.dart';
import '../design/image_stack_tokens.dart';
import 'image_stack_photo.dart';

import '../design/icons.dart';
import '../design/reading.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'image_grid.dart';
import 'net_image.dart';
import 'image_stack_mode_toggle.dart';

typedef StackImageProviderBuilder =
    ImageProvider<Object> Function(String url, int decodeWidth);

/// A fixed paper frame with a windowed, continuous-position photo deck.
class ImageStackGallery extends StatefulWidget {
  final List<String> urls;
  final List<double?>? aspectRatios;
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
    this.aspectRatios,
    required this.gallery,
    required this.galleryStartIndex,
    this.compact = false,
    this.expanded,
    this.onExpandedChanged,
    this.imageProviderBuilder,
  }) : assert(urls.length >= 2),
       assert(aspectRatios == null || aspectRatios.length == urls.length);

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
      final radius = BorderRadius.circular(ImageStackTokens.expandedRadius);
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
            child: ClipRRect(borderRadius: radius, child: child),
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

/// Frame geometry uses known source ratios; long screenshots contribute 0.5.
@visibleForTesting
Size imageStackFrame(
  Iterable<double> ratios,
  double width, {
  bool compact = false,
}) {
  final values =
      ratios
          .map(
            (r) => r < ImageStackTokens.longRatio
                ? ImageStackTokens.longFrameRatio
                : r,
          )
          .toList()
        ..sort();
  if (values.isEmpty) values.add(4 / 3);
  final cap = compact
      ? ImageStackTokens.compactFrameHeight
      : ImageStackTokens.frameHeight;
  final minimum = compact
      ? ImageStackTokens.compactMinFrameHeight
      : ImageStackTokens.minFrameHeight;
  final edge = compact
      ? ImageStackTokens.compactBorder
      : ImageStackTokens.border;
  if (values.last < .9) {
    final w = math.min(width, (cap - 2 * edge) * values.last + 2 * edge);
    return Size(w, math.min(cap, (w - 2 * edge) / values.last + 2 * edge));
  }
  final m = values.length ~/ 2;
  final median = values.length.isOdd
      ? values[m]
      : (values[m - 1] + values[m]) / 2;
  return Size(width, (width / median).clamp(minimum, cap));
}

@visibleForTesting
int imageStackReleaseTarget(
  double start,
  double position,
  double velocity,
  int count,
) {
  final base = start.round();
  final delta = position - base;
  final step = velocity.abs() > ImageStackTokens.swipeVelocity
      ? -velocity.sign.toInt()
      : delta.abs() > ImageStackTokens.swipeFraction
      ? delta.sign.toInt()
      : 0;
  return (base + step).clamp(0, count - 1);
}

class _PhotoVM {
  final String url;
  double ratio = 4 / 3;
  bool known = false, decoded = false, failed = false, probing = false;
  PhotoAtmosphere? atmosphere;
  _PhotoVM(this.url, double? sourceRatio) {
    if (sourceRatio != null && sourceRatio.isFinite && sourceRatio > 0) {
      ratio = sourceRatio;
      known = true;
    }
  }
}

class _ImageStackGalleryState extends State<ImageStackGallery>
    with TickerProviderStateMixin {
  late List<_PhotoVM> _photos;
  late List<double?> _knownRatios;
  final _probes = <_PhotoVM, (ImageStream, ImageStreamListener)>{};
  late final AnimationController _position, _flip, _pop, _hint;
  final _scrollSignal = ValueNotifier(0);
  final _collapseOverlay = OverlayPortalController();
  ScrollPosition? _scroll;
  Set<int> _window = {};
  List<Rect>? _listCache;
  Size? _frameCache;
  List<double>? _frameRatios;
  double? _reservedFrameHeight;
  bool _ratiosDirty = false;
  final _photoWidgets = <int, Widget>{};
  final _flipFrom = <int, Rect>{};
  final _flipIntervals = <int, Interval>{};
  double _width = 0, _dragStart = 0, _dragX = 0;
  bool _expanded = false, _restored = false, _preferencesApplied = false;
  bool _restoredExpansion = false;
  bool _metricsPending = false, _hintStarted = false;
  int _index = 0, _geometryBuilds = 0, _frameVisits = 0;
  double? _galleryOrigin;
  double _lastScrollPixels = 0;

  @visibleForTesting
  int get debugActiveCardMotions =>
      (_position.isAnimating || _hint.isAnimating ? 2 : 0) +
      (_flip.isAnimating ? _flipFrom.length : 0) +
      (_pop.isAnimating ? 1 : 0);
  @visibleForTesting
  int get debugCardControllers => 0;
  @visibleForTesting
  int get debugGeometryBuilds => _geometryBuilds;
  @visibleForTesting
  int get debugFrameRigVisits => _frameVisits;
  @visibleForTesting
  int get debugProbeCount => _probes.length;
  bool get _reduced => MediaQuery.disableAnimationsOf(context);
  double get _travel => _frame.width + ImageStackTokens.travelExtra;
  double get _livePosition => _position.value + _hint.value / _travel;
  double get _frameCap => widget.compact
      ? ImageStackTokens.compactFrameHeight
      : ImageStackTokens.frameHeight;
  double get _reservation =>
      _expanded ? 0 : math.max(0, (_reservedFrameHeight ?? 0) - _frame.height);
  Size get _frame => _frameCache ??= () {
    _geometryBuilds++;
    if (_frameRatios == null) return Size(_width, _frameCap);
    return imageStackFrame(_frameRatios!, _width, compact: widget.compact);
  }();
  List<Rect> get _list => _listCache ??= () {
    _geometryBuilds++;
    double y = 0;
    return _photos.map((p) {
      final rect = Rect.fromLTWH(0, y, _width, _width / p.ratio);
      y += rect.height + ImageStackTokens.gap;
      return rect;
    }).toList();
  }();
  double get _height =>
      _expanded ? _list.last.bottom : _frame.height + ImageStackTokens.deckFoot;
  Rect get _deckRect => Rect.fromLTWH(
    (_width - _frame.width) / 2,
    0,
    _frame.width,
    _frame.height,
  );

  @override
  void initState() {
    super.initState();
    _photos = [
      for (var i = 0; i < widget.urls.length; i++)
        _PhotoVM(widget.urls[i], widget.aspectRatios?[i]),
    ];
    _knownRatios = [
      for (final photo in _photos) photo.known ? photo.ratio : null,
    ];
    _position = AnimationController.unbounded(vsync: this)
      ..addListener(_onPosition);
    _flip = AnimationController(vsync: this, value: 1);
    _pop = AnimationController.unbounded(vsync: this, value: 1);
    _hint = AnimationController.unbounded(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _photoWidgets.clear();
    if (!_restored) {
      _restored = true;
      // Use the group's PageStorageKey path; a shared identifier aliases all decks.
      final saved = PageStorage.maybeOf(context)?.readState(context);
      if (saved is Map) {
        if (saved['expanded'] case final bool expanded) {
          _expanded = expanded;
          _restoredExpansion = true;
        }
        if (saved['urls'] is List &&
            listEquals(saved['urls'] as List, widget.urls)) {
          if (saved['ratios'] is List<double>) {
            _frameRatios = saved['ratios'] as List<double>;
          }
          final ratios = saved['photoRatios'];
          if (ratios is List && ratios.length == _photos.length) {
            for (var i = 0; i < _photos.length; i++) {
              final ratio = ratios[i];
              if (!_photos[i].known &&
                  ratio is num &&
                  ratio.isFinite &&
                  ratio > 0) {
                _photos[i].ratio = ratio.toDouble();
                _photos[i].known = true;
                _knownRatios[i] = ratio.toDouble();
              }
            }
          }
        }
        if (saved['current'] is int) {
          _index = (saved['current'] as int).clamp(0, _photos.length - 1);
        }
      }
      _expanded = widget.expanded ?? _expanded;
      _position.value = _index.toDouble();
      _window = _deckWindow(_index);
      _probeAround(_index);
    }
    final prefs = ReadingScope.maybeOf(context);
    if (!_preferencesApplied && (prefs?.ready ?? true)) {
      _preferencesApplied = true;
      // The preference is a default for unseen groups, never a replacement for
      // a recycled group's own choice. Changing an offscreen group from a deck
      // to a full column invalidates the sliver's retained scroll geometry.
      _expanded =
          widget.expanded ??
          (_restoredExpansion
              ? _expanded
              : prefs?.prefs.imagesExpanded ?? _expanded);
    }
    final scroll = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (!identical(scroll, _scroll)) {
      _scroll?.removeListener(_onScroll);
      _scroll = scroll;
      _lastScrollPixels = scroll?.pixels ?? 0;
      _scroll?.addListener(_onScroll);
    }
    if (_reduced) {
      _position.value = _index.toDouble();
      _flip.value = 1;
      _pop.value = 1;
      _hint.value = 0;
    }
    _save();
    _scheduleMetrics();
  }

  @override
  void didUpdateWidget(ImageStackGallery old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.urls, widget.urls)) {
      final previous = old.urls[_index.clamp(0, old.urls.length - 1)];
      final found = widget.urls.indexOf(previous);
      _index = found >= 0 && widget.urls.lastIndexOf(previous) == found
          ? found
          : _index.clamp(0, widget.urls.length - 1);
      _cancelProbes();
      _photoWidgets.clear();
      _photos = [
        for (var i = 0; i < widget.urls.length; i++)
          _PhotoVM(widget.urls[i], widget.aspectRatios?[i]),
      ];
      _knownRatios = [
        for (final photo in _photos) photo.known ? photo.ratio : null,
      ];
      _frameRatios = null;
      _reservedFrameHeight = null;
      _frameCache = null;
      _listCache = null;
      _position.value = _index.toDouble();
      _window = _deckWindow(_index);
      _probeAround(_index);
    }
    if (old.compact != widget.compact) _frameCache = null;
    if (old.imageProviderBuilder != widget.imageProviderBuilder) {
      _cancelProbes();
      _probeAround(_index);
    }
    if (widget.expanded != null && widget.expanded != _expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.expanded != _expanded) _toggle();
      });
    }
  }

  void _save() => PageStorage.maybeOf(context)?.writeState(context, {
    'current': _index,
    'expanded': _expanded,
    'urls': widget.urls,
    'ratios': _frameRatios,
    // Keep one shared snapshot; each completed probe updates its own slot.
    // No full-gallery copy or extra write is needed on every decode/scroll.
    'photoRatios': _knownRatios,
  });

  void _probeAround(int center) {
    for (
      var i = math.max(0, center - 10);
      i <= math.min(_photos.length - 1, center + 10);
      i++
    ) {
      final vm = _photos[i];
      if (vm.decoded || vm.failed || vm.probing) continue;
      vm.probing = true;
      final provider =
          widget.imageProviderBuilder?.call(vm.url, 64) ??
          boundedNetworkImageBox(vm.url, 64, 128);
      final stream = provider.resolve(createLocalImageConfiguration(context));
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (_probes[vm]?.$2 != listener) {
            info.dispose();
            return;
          }
          if (!vm.known) vm.ratio = info.image.width / info.image.height;
          vm.known = true;
          vm.decoded = true;
          _knownRatios[i] = vm.ratio;
          PhotoAtmosphere.fromImage(
            '${vm.url}:${provider.hashCode}',
            info.image,
          ).then((sample) {
            if (!mounted || !_photos.contains(vm)) return;
            vm.atmosphere = sample;
            final i = _photos.indexOf(vm);
            _photoWidgets.remove(i);
            if (_window.contains(i)) setState(() {});
          }, onError: (Object _, StackTrace _) {});
          info.dispose();
          _detachProbe(vm);
          _ratiosChanged();
        },
        onError: (_, _) {
          if (_probes[vm]?.$2 != listener) return;
          vm.failed = true;
          _detachProbe(vm);
          _ratiosChanged();
        },
      );
      _probes[vm] = (stream, listener);
      stream.addListener(listener);
    }
  }

  void _detachProbe(_PhotoVM vm) {
    final probe = _probes.remove(vm);
    probe?.$1.removeListener(probe.$2);
    vm.probing = false;
  }

  void _cancelProbes() {
    for (final vm in _probes.keys.toList()) {
      _detachProbe(vm);
    }
  }

  void _ratiosChanged() {
    if (!mounted) return;
    _listCache = null;
    _photoWidgets.clear();
    _ratiosDirty = true;
    _scheduleMetrics();
  }

  void _lockFrame() {
    if (_frameRatios != null ||
        !_photos.skip(_index).take(3).every((p) => p.known || p.failed)) {
      return;
    }
    _frameRatios = _photos
        .where((p) => p.known)
        .map((p) => p.ratio)
        .toList(growable: false);
    _frameCache = null;
    _ratiosDirty = true;
    _save();
  }

  void _onPosition() {
    final n = _position.value.round().clamp(0, _photos.length - 1);
    if (n != _index) {
      _index = n;
      _save();
      _scheduleMetrics();
    }
  }

  void _setIndex(int n, {bool immediate = false, double? velocity}) {
    _lockFrame();
    n = n.clamp(0, _photos.length - 1);
    _hint.value = 0;
    AppMotion.settle(
      _position,
      target: n.toDouble(),
      motion: AppMotion.sheet,
      velocity: velocity,
      reduced: _reduced || immediate,
    );
    _probeAround(n);
    _scheduleMetrics();
  }

  void _step(int d) {
    if (_frameRatios == null) return;
    if (_expanded) {
      final n = (_index + d).clamp(0, _photos.length - 1);
      _index = n;
      final box = context.findRenderObject();
      if (_scroll != null && box is RenderBox) {
        AppMotion.scrollTo(
          _scroll!,
          _scroll!.pixels +
              box.localToGlobal(Offset.zero).dy +
              _list[n].top -
              60,
          reduced: _reduced,
        );
      }
      _save();
    } else {
      _setIndex(_index + d);
    }
  }

  double _rubber(double value) =>
      (1 - 1 / (value * .55 / (_frame.width * .4) + 1)) * _frame.width * .4;
  void _dragBegin(DragStartDetails d) {
    _lockFrame();
    _position.stop();
    _hint.value = 0;
    _dragStart = _position.value;
    _dragX = 0;
  }

  void _dragUpdate(DragUpdateDetails d) {
    _dragX += d.delta.dx;
    var p = _dragStart - _dragX / _travel;
    if (p < 0) p = -_rubber(-p * _travel) / _travel;
    if (p > _photos.length - 1) {
      p =
          _photos.length -
          1 +
          _rubber((p - _photos.length + 1) * _travel) / _travel;
    }
    _position.value = p;
  }

  void _dragEnd(double velocity) {
    final target = imageStackReleaseTarget(
      _dragStart,
      _position.value,
      velocity,
      _photos.length,
    );
    _dragX = 0;
    _setIndex(target, velocity: -velocity / _travel);
  }

  void _open(int i) {
    // Group navigation is intentionally bounded to this consecutive run.
    openImageViewer(
      context,
      urls: widget.urls,
      initialIndex: i,
      heroTagForIndex: (n) => (this, n),
      previewImageForIndex: _provider,
      onPageChanged: (n) {
        if (!mounted) return;
        _setIndex(n, immediate: true);
        if (_expanded) _step(0);
      },
    );
  }

  int _middleCard() {
    final origin = _galleryOrigin ?? 0;
    final middle = MediaQuery.sizeOf(context).height / 2;
    var best = _index, distance = double.infinity;
    for (final i in _listWindow()) {
      final rect = _list[i];
      if (origin + rect.top <= middle && origin + rect.bottom >= middle) {
        return i;
      }
      final d = (origin + rect.center.dy - middle).abs();
      if (d < distance) {
        best = i;
        distance = d;
      }
    }
    return best;
  }

  Rect _deckPhotoRect(int i) {
    final edge = widget.compact
        ? ImageStackTokens.compactBorder
        : ImageStackTokens.border;
    final well = _deckRect.deflate(edge);
    final ratio = _photos[i].ratio;
    if (ratio < ImageStackTokens.longRatio ||
        ImageStackPhoto.fillsWell(ratio, well.size.aspectRatio)) {
      return well;
    }
    return ImageStackPhoto.mountedRect(well.size, ratio).shift(well.topLeft);
  }

  Rect _currentListRect(int i) {
    if (_flip.value < 1 && _flipFrom.containsKey(i)) {
      return Rect.lerp(
        _flipFrom[i],
        _list[i],
        _flipIntervals[i]!.transform(_flip.value),
      )!;
    }
    return _list[i];
  }

  void _toggle() {
    if (_frameRatios == null) return;
    _preferencesApplied = true;
    _lockFrame();
    _position.stop();
    _hint.value = 0;
    final k = _expanded ? _middleCard() : _index;
    final before = _expanded ? _currentListRect(k) : _deckPhotoRect(k);
    final scroll0 = _scroll?.pixels ?? 0;
    final origin = _galleryOrigin ?? 0;
    final opening = !_expanded;
    final oldHeight = _height;
    final newHeight = opening
        ? _list.last.bottom
        : _frame.height + ImageStackTokens.deckFoot;
    final after = opening ? _list[k] : _deckPhotoRect(k);
    final delta = after.top - before.top;
    final duration = AppMotion.revealDuration;
    final total = duration + AppMotion.riffleStep * 3;
    _flip.stop();
    _flipFrom.clear();
    _flipIntervals.clear();
    // Final layout and inverse transforms enter the same frame. The later
    // scroll correction is added to the inverse transform, keeping it stationary.
    if (opening && !_reduced) {
      final view = MediaQuery.sizeOf(context).height;
      final candidates = <int>[k];
      for (
        var i = math.max(0, k - 2);
        i <= math.min(_photos.length - 1, k + 2);
        i++
      ) {
        final top = origin + _list[i].top - delta;
        if (i != k && top <= view && top + _list[i].height >= 0) {
          candidates.add(i);
        }
      }
      for (final i in candidates.take(3)) {
        _flipFrom[i] = i == k ? before : _deckPhotoRect(i);
        final delay = AppMotion.riffleStep * (i - k).abs().clamp(0, 3);
        _flipIntervals[i] = Interval(
          delay.inMicroseconds / total.inMicroseconds,
          (delay + duration).inMicroseconds / total.inMicroseconds,
          curve: AppMotion.revealCurve,
        );
      }
    }
    setState(() {
      _index = k;
      _position.value = k.toDouble();
      _expanded = opening;
      _photoWidgets.clear();
      _window = opening
          ? {..._listWindow(), ..._flipFrom.keys, k}
          : _deckWindow(k);
      _flip.value = opening && !_reduced ? 0 : 1;
      _pop.value = 1;
    });
    final prefs = ReadingScope.maybeOf(context);
    if (prefs != null) prefs.set(prefs.prefs.copyWith(imagesExpanded: opening));
    widget.onExpandedChanged?.call(opening);
    _save();
    // Scroll and transforms are changed before the next layout together.
    // The extent after expansion is known from the cached final geometry.
    final pos = _scroll;
    if (pos != null) {
      final nextMax = math.max(
        pos.minScrollExtent,
        pos.maxScrollExtent + newHeight - oldHeight,
      );
      pos.jumpTo((scroll0 + delta).clamp(pos.minScrollExtent, nextMax));
    }
    final actualDelta = (pos?.pixels ?? scroll0) - scroll0;
    for (final i in _flipFrom.keys.toList()) {
      _flipFrom[i] = _flipFrom[i]!.shift(Offset(0, actualDelta));
    }
    _galleryOrigin = origin - actualDelta;
    _window = {
      ...(_expanded ? _listWindow() : _deckWindow(k)),
      ..._flipFrom.keys,
    };
    _scheduleMetrics();
    if (_reduced) return;
    if (opening) {
      _flip.duration = total;
      _flip.forward(from: 0);
    } else {
      _pop.value = .96;
      AppMotion.settle(_pop, target: 1, motion: AppMotion.pop);
    }
  }

  Set<int> _deckWindow(int center) => {
    for (var i = center - 2; i <= center + 2; i++)
      if (i >= 0 && i < _photos.length) i,
  };
  Set<int> _listWindow() {
    final origin = _galleryOrigin ?? 0;
    final view =
        _scroll?.viewportDimension ?? MediaQuery.sizeOf(context).height;
    final lo = -origin - view * 1.5, hi = -origin + view * 2.5;
    var l = 0, r = _list.length;
    while (l < r) {
      final m = (l + r) ~/ 2;
      if (_list[m].bottom < lo) {
        l = m + 1;
      } else {
        r = m;
      }
    }
    return {for (var i = l; i < _list.length && _list[i].top <= hi; i++) i};
  }

  void _onScroll() {
    final pixels = _scroll?.pixels ?? 0;
    if (_galleryOrigin != null) {
      _galleryOrigin = _galleryOrigin! + _lastScrollPixels - pixels;
    }
    _lastScrollPixels = pixels;
    _scrollSignal.value++;
    _scheduleMetrics();
  }

  void _scheduleMetrics() {
    if (_metricsPending) return;
    _metricsPending = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsPending = false;
      if (mounted) _updateMetrics();
    });
  }

  void _updateMetrics() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || _width == 0) return;
    _lastScrollPixels = _scroll?.pixels ?? 0;
    _galleryOrigin =
        box.localToGlobal(Offset.zero).dy + (widget.compact ? 8 : 14);
    final next = _expanded ? _listWindow() : _deckWindow(_index);
    _lockFrame();
    // Release the loading estimate as soon as the final frame is known.
    // Only compensate scroll when the entire gallery is above the viewport;
    // a visible deck must not leave its old loading height below the caption.
    final spare = _reservation;
    if (spare > 0) {
      WidgetsBinding.instance.scheduleFrameCallback((_) {
        if (!mounted || _reservedFrameHeight == null || _expanded) return;
        final currentBox = context.findRenderObject();
        if (currentBox is! RenderBox || !currentBox.hasSize) return;
        final currentTop = currentBox.localToGlobal(Offset.zero).dy;
        final aboveViewport = currentTop + currentBox.size.height <= 0;
        // Correct offset and extent together before layout, never after paint.
        setState(() => _reservedFrameHeight = null);
        if (aboveViewport && _scroll != null) {
          _scroll!.jumpTo(
            math.max(_scroll!.minScrollExtent, _scroll!.pixels - spare),
          );
        }
      });
    }
    if (!setEquals(next, _window) || _ratiosDirty) {
      setState(() => _window = next);
      _ratiosDirty = false;
    }
    _photoWidgets.removeWhere((i, _) => !next.contains(i));
    for (final i in next) {
      _probeAround(i);
    }
    if (_expanded && !_collapseOverlay.isShowing) _collapseOverlay.show();
    _scrollSignal.value++;
    _maybeHint();
  }

  void _maybeHint() {
    if (_frameRatios == null ||
        _hintStarted ||
        _expanded ||
        _reduced ||
        _width == 0) {
      return;
    }
    if (!TickerMode.valuesOf(context).enabled ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final origin = _galleryOrigin;
    final view = MediaQuery.sizeOf(context).height;
    if (origin == null || origin < 0 || origin + _frame.height > view) return;
    final prefs = ReadingScope.maybeOf(context);
    if (prefs == null || !prefs.ready) return;
    _hintStarted = true;
    // Claim synchronously so multiple visible groups cannot repeat the cue.
    if (!prefs.claimImageStackHint()) return;
    AppMotion.settle(
      _hint,
      target: ImageStackTokens.hintDistance,
      motion: AppMotion.select,
    ).whenCompleteOrCancel(() {
      if (mounted && _hint.value == ImageStackTokens.hintDistance) {
        AppMotion.settle(_hint, target: 0, motion: AppMotion.select);
      }
    });
  }

  @override
  void dispose() {
    _cancelProbes();
    _scroll?.removeListener(_onScroll);
    _scrollSignal.dispose();
    _position.dispose();
    _flip.dispose();
    _pop.dispose();
    _hint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _collapseOverlay,
    overlayChildBuilder: _collapsePill,
    child: FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _PreviousPhotoIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NextPhotoIntent(),
      },
      actions: {
        _PreviousPhotoIntent: CallbackAction<_PreviousPhotoIntent>(
          onInvoke: (_) {
            _step(-1);
            return null;
          },
        ),
        _NextPhotoIntent: CallbackAction<_NextPhotoIntent>(
          onInvoke: (_) {
            _step(1);
            return null;
          },
        ),
      },
      child: Padding(
        padding: EdgeInsets.only(
          top: widget.compact ? 8 : 14,
          bottom: widget.compact ? 10 : 18,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_width != constraints.maxWidth) {
              _width = constraints.maxWidth;
              _photoWidgets.clear();
              _frameCache = null;
              _listCache = null;
              _scheduleMetrics();
            }
            _lockFrame();
            if (_frameRatios == null) _reservedFrameHeight ??= _frameCap;
            return AnimatedBuilder(
              animation: Listenable.merge([_position, _flip, _pop, _hint]),
              builder: (context, _) {
                _frameVisits += _window.length;
                final ordered = _window.toList()
                  ..sort((a, b) {
                    if (_expanded && _flip.value < 1) {
                      if (a == _index) return 1;
                      if (b == _index) return -1;
                    }
                    return b.compareTo(a);
                  });
                return Column(
                  children: [
                    Semantics(
                      container: true,
                      explicitChildNodes: true,
                      label: '连续图片，第 ${_index + 1} 张，共 ${_photos.length} 张',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: _expanded || _frameRatios == null
                            ? null
                            : _dragBegin,
                        onHorizontalDragUpdate:
                            _expanded || _frameRatios == null
                            ? null
                            : _dragUpdate,
                        onHorizontalDragEnd: _expanded || _frameRatios == null
                            ? null
                            : (d) => _dragEnd(d.velocity.pixelsPerSecond.dx),
                        onHorizontalDragCancel:
                            _expanded || _frameRatios == null
                            ? null
                            : () => _setIndex(_index),
                        child: SizedBox(
                          key: const ValueKey('image-stack-stage'),
                          width: _width,
                          height: _height,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              if (_frameRatios == null)
                                Positioned.fill(
                                  child: Semantics(
                                    label: '图片加载中',
                                    child: DecoratedBox(
                                      key: const ValueKey(
                                        'image-stack-loading',
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTokens.of(context).fill,
                                        borderRadius: BorderRadius.circular(
                                          widget.compact
                                              ? ImageStackTokens
                                                    .compactPaperRadius
                                              : ImageStackTokens.paperRadius,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              else ...[
                                if (!_expanded) ..._glows(),
                                if (!_expanded) ..._paperEdges(),
                                for (final i in ordered) _card(i),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!_expanded)
                      SizedBox(
                        width: _frame.width,
                        height: ImageStackTokens.captionHeight,
                        child: _frameRatios == null ? null : _caption(),
                      ),
                    if (_expanded)
                      const SizedBox(height: ImageStackTokens.captionHeight),
                    if (_reservation > 0) SizedBox(height: _reservation),
                  ],
                );
              },
            );
          },
        ),
      ),
    ),
  );

  Widget _collapsePill(BuildContext context) {
    final anchor = ReadingBarAnchor.maybeOf(context);
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return AnimatedBuilder(
      animation: Listenable.merge([_scrollSignal, anchor?.hiddenProgress]),
      builder: (context, _) {
        final origin = _galleryOrigin;
        final view = MediaQuery.sizeOf(context).height;
        final shown =
            _expanded &&
            origin != null &&
            origin < view &&
            origin + _height > MediaQuery.paddingOf(context).top;
        return Positioned(
          left: 0,
          right: 0,
          bottom:
              (anchor?.surfaceTopInset ?? safeBottom) +
              ImageStackTokens.collapseGap,
          child: Transform.translate(
            offset: Offset(
              0,
              (anchor?.height ?? 0) * (anchor?.hiddenProgress.value ?? 0),
            ),
            child: Center(
              child: SingleMotionBuilder(
                value: shown ? 1.0 : 0.0,
                from: _reduced ? null : 0,
                motion: AppMotion.select,
                active: !_reduced,
                builder: (context, value, _) {
                  final p = value.clamp(0.0, 1.0);
                  if (p == 0) return const SizedBox.shrink();
                  return IgnorePointer(
                    ignoring: !shown,
                    child: ExcludeSemantics(
                      excluding: !shown,
                      child: Opacity(
                        opacity: p,
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            ImageStackTokens.collapseGap * (1 - p),
                          ),
                          child: ImageStackModeToggle(
                            expanded: true,
                            onPressed: _toggle,
                            total: _photos.length,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _paperEdges() {
    final t = AppTokens.of(context);
    final f = _deckRect;
    return [
      for (final k in [1, 0])
        Positioned.fromRect(
          rect: f,
          child: IgnorePointer(
            child: Transform.translate(
              offset: Offset(0, ImageStackTokens.paperOffsets[k]),
              child: Transform.rotate(
                angle: ImageStackTokens.paperRotations[k] * math.pi / 180,
                child: Transform.scale(
                  scale: (f.width - ImageStackTokens.paperInsets[k]) / f.width,
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ImageStackTokens.paper(t).withValues(
                        alpha: (_photos.length - 1 - _livePosition - k).clamp(
                          0.0,
                          1.0,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(
                        widget.compact
                            ? ImageStackTokens.compactPaperRadius
                            : ImageStackTokens.paperRadius,
                      ),
                      boxShadow: ImageStackTokens.edgeShadow(
                        (_photos.length - 1 - _livePosition - k).clamp(
                          0.0,
                          1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _card(int i) {
    final finalRect = _expanded ? _list[i] : _deckRect;
    double x = 0, y = 0, sx = 1, sy = 1, angle = 0, dim = 0;
    bool hidden = false;
    if (!_expanded) {
      final d = i - _livePosition;
      if (d <= -1 || d >= 2) hidden = true;
      if (d < 0) {
        x = d * _travel;
        y = -x.abs() * .025;
        angle = x * ImageStackTokens.rotationPerPixel * math.pi / 180;
      } else {
        final p = (1 - d).clamp(0.0, 1.0);
        sx = sy =
            (ImageStackTokens.incomingScale +
                (1 - ImageStackTokens.incomingScale) * p) *
            _pop.value;
        dim = ImageStackTokens.incomingDim * (1 - p);
      }
      // Right overscroll moves the first paper with the pointer as well.
      if (i == 0 && _livePosition < 0) {
        x = -_livePosition * _travel;
        angle = x * ImageStackTokens.rotationPerPixel * math.pi / 180;
        sx = sy = 1;
        dim = 0;
      }
    } else if (_flip.value < 1 && _flipFrom.containsKey(i)) {
      final p = _flipIntervals[i]!.transform(_flip.value);
      final from = _flipFrom[i]!;
      x = (from.left - finalRect.left) * (1 - p);
      y = (from.top - finalRect.top) * (1 - p);
      sx = 1 + (from.width / finalRect.width - 1) * (1 - p);
      sy = 1 + (from.height / finalRect.height - 1) * (1 - p);
    }
    return Positioned.fromRect(
      key: ValueKey('image-stack-card-$i'),
      rect: finalRect,
      child: IgnorePointer(
        ignoring: hidden || (!_expanded && i != _index),
        child: Visibility(
          visible: !hidden,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: ClipRect(
            clipBehavior: _expanded ? Clip.none : Clip.hardEdge,
            clipper: _DeckLeadingClipper(
              -_travel * (1 + i - _livePosition).clamp(0.0, 1.0),
            ),
            child: Transform.translate(
              offset: Offset(x, y),
              child: Transform.rotate(
                angle: angle,
                child: Transform(
                  alignment: Alignment.topLeft,
                  transform: Matrix4.diagonal3Values(sx, sy, 1),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (!_expanded)
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                widget.compact
                                    ? ImageStackTokens.compactPaperRadius
                                    : ImageStackTokens.paperRadius,
                              ),
                              boxShadow: [
                                for (final shadow
                                    in ImageStackTokens.liftShadow)
                                  shadow.copyWith(
                                    color: shadow.color.withValues(
                                      alpha:
                                          shadow.color.a *
                                          ((_livePosition -
                                                          _livePosition.round())
                                                      .abs() *
                                                  8)
                                              .clamp(0.0, 1.0),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      _photoWidgets.putIfAbsent(i, () => _photoCard(i)),
                      if (dim > 0)
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: ImageStackTokens.ink.withValues(
                                alpha: dim,
                              ),
                              borderRadius: BorderRadius.circular(
                                widget.compact
                                    ? ImageStackTokens.compactPaperRadius
                                    : ImageStackTokens.paperRadius,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ImageProvider<Object> _provider(int i) {
    final decode = boundedImageDecodeWidth(
      _width,
      MediaQuery.devicePixelRatioOf(context),
    );
    return widget.imageProviderBuilder?.call(_photos[i].url, decode) ??
        boundedNetworkImageBox(_photos[i].url, decode, 2048);
  }

  Widget _photoCard(int i) {
    final t = AppTokens.of(context);
    final radius = _expanded
        ? ImageStackTokens.expandedRadius
        : widget.compact
        ? ImageStackTokens.compactPaperRadius
        : ImageStackTokens.paperRadius;
    final edge = _expanded
        ? 0.0
        : widget.compact
        ? ImageStackTokens.compactBorder
        : ImageStackTokens.border;
    final vm = _photos[i];
    return RepaintBoundary(
      child: Semantics(
        image: true,
        button: true,
        label: _expanded
            ? '查看连续图片第 ${i + 1} 张，共 ${_photos.length} 张'
            : '查看第 ${i + 1} 张图片',
        child: GestureDetector(
          onTap: () => _open(i),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ImageStackTokens.paper(t),
              borderRadius: BorderRadius.circular(radius),
              boxShadow: _expanded ? null : ImageStackTokens.frontShadow,
            ),
            child: Padding(
              padding: EdgeInsets.all(edge),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius - edge),
                child: ImageStackPhoto(
                  provider: _provider(i),
                  ratio: vm.ratio,
                  compact: widget.compact,
                  expanded: _expanded,
                  imageKey: ValueKey('image-stack-photo-$i'),
                  atmosphere: vm.atmosphere,
                  heroTag: (this, i),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _glows() {
    final p = _livePosition.clamp(0.0, (_photos.length - 1).toDouble());
    final a = p.floor(), b = math.min(a + 1, _photos.length - 1);
    final fraction = p - a;
    return [
      for (final entry in [(a, 1 - fraction), (b, fraction)])
        if (_photos[entry.$1].atmosphere case final sample?)
          Positioned.fromRect(
            rect: _deckRect.deflate(ImageStackTokens.glowInset),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    ImageStackTokens.paperRadius,
                  ),
                  boxShadow: ImageStackTokens.glowShadow(
                    sample.color,
                    sample.strength * entry.$2,
                  ),
                ),
              ),
            ),
          ),
    ];
  }

  Widget _caption() {
    final t = AppTokens.of(context);
    return Row(
      key: const ValueKey('image-stack-row'),
      children: [
        _StackPageNumber(index: _index),
        Text(
          ' / ${_photos.length}',
          style: AppType.footnote.copyWith(color: t.text3),
        ),
        const Spacer(),
        ImageStackModeToggle(
          expanded: false,
          onPressed: _toggle,
          total: _photos.length,
        ),
      ],
    );
  }
}

/// A rotated portrait can still protrude at d == -1. Reveal it continuously
/// through the leading edge before its offscreen slot is hidden, so a spring
/// crossing an integer cannot flash the corner of an unrelated earlier photo.
class _DeckLeadingClipper extends CustomClipper<Rect> {
  final double left;
  const _DeckLeadingClipper(this.left);

  @override
  Rect getClip(Size size) {
    final margin = size.longestSide + ImageStackTokens.travelExtra;
    return Rect.fromLTRB(
      left,
      -margin,
      size.width + margin,
      size.height + margin,
    );
  }

  @override
  bool shouldReclip(_DeckLeadingClipper oldClipper) => left != oldClipper.left;
}

class _PreviousPhotoIntent extends Intent {
  const _PreviousPhotoIntent();
}

class _NextPhotoIntent extends Intent {
  const _NextPhotoIntent();
}

class _StackPageNumber extends StatefulWidget {
  final int index;
  const _StackPageNumber({required this.index});
  @override
  State<_StackPageNumber> createState() => _StackPageNumberState();
}

class _StackPageNumberState extends State<_StackPageNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _roll = AnimationController.unbounded(
    vsync: this,
    value: widget.index.toDouble(),
  );
  @override
  void didUpdateWidget(_StackPageNumber old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      AppMotion.settle(
        _roll,
        target: widget.index.toDouble(),
        motion: AppMotion.select,
        reduced: MediaQuery.disableAnimationsOf(context),
      );
    }
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _roll,
    builder: (context, _) {
      final value = _roll.value;
      final base = value.floor();
      final style = AppType.footnote.copyWith(
        color: AppTokens.of(context).accent,
        fontWeight: FontWeight.w600,
      );
      final height =
          MediaQuery.textScalerOf(context).scale(AppType.sizeFootnote) * 1.5;
      return Semantics(
        label: '${widget.index + 1}',
        child: ExcludeSemantics(
          child: ClipRect(
            child: SizedBox(
              height: height,
              width: height * (widget.index + 1).toString().length * .65,
              child: Stack(
                children: [
                  for (final n in [base, base + 1])
                    Positioned(
                      top: (n - value) * height,
                      left: 0,
                      child: Text('${n + 1}', style: style),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
