import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../design/level_glyphs.dart';
import '../design/level_tokens.dart';
import '../design/tokens.dart';
import '../ui/feedback.dart';
import 'level_shimmer.dart';
import 'level_glow.dart';

/// Only the authoritative thread-sidebar gid selects a badge.
class LevelBadge extends StatelessWidget {
  const LevelBadge({
    super.key,
    required this.gid,
    this.onTap,
    this.onLacquer = false,
  });
  final int? gid;
  final VoidCallback? onTap;
  final bool onLacquer;

  @override
  Widget build(BuildContext context) {
    final level = LevelDefinition.lookup(gid);
    if (level == null) return const SizedBox.shrink();
    final whiteBacking =
        onLacquer &&
        AppTokens.of(context).style == AppearanceStyle.cinnabar &&
        LevelTokens.coldTiers.contains(level.tier);
    return Semantics(
      container: true,
      label: '等级 ${level.displayName}',
      button: onTap != null,
      onTap: onTap,
      onLongPress: () => AppToast.show(context, level.longPress),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: () => AppToast.show(context, level.longPress),
          child: level.animated
              ? _AnimatedBadge(key: ValueKey(level.gid), level: level)
              : _Badge(level: level, whiteBacking: whiteBacking),
        ),
      ),
    );
  }
}

class _AnimatedBadge extends StatefulWidget {
  const _AnimatedBadge({super.key, required this.level});
  final LevelDefinition level;
  @override
  State<_AnimatedBadge> createState() => _AnimatedBadgeState();
}

class _AnimatedBadgeState extends State<_AnimatedBadge>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  AnimationController? _animation;
  Timer? _next;
  ScrollPosition? _scroll;
  bool _enabled = false;
  bool _foreground = true;
  bool _checkPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll != _scroll) {
      _scroll?.removeListener(_checkSoon);
      _scroll = scroll;
      scroll?.addListener(_checkSoon);
    }
    _enabled =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.of(context)?.isCurrent != false;
    if (!_enabled) _stop();
    _checkSoon();
  }

  @override
  void didUpdateWidget(_AnimatedBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) {
      _stop();
      _checkSoon();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _stop();
    _checkSoon();
  }

  void _checkSoon() {
    if (_checkPending) return;
    _checkPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPending = false;
      if (mounted) _check();
    });
  }

  bool get _visible {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    var bounds = MatrixUtils.transformRect(
      box.getTransformTo(null),
      box.paintBounds,
    );
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    if (!bounds.overlaps(screen)) return false;
    RenderObject? ancestor = box.parent;
    while (ancestor != null) {
      if (ancestor is RenderAbstractViewport) {
        final clip = MatrixUtils.transformRect(
          ancestor.getTransformTo(null),
          ancestor.paintBounds,
        );
        bounds = bounds.intersect(clip);
        if (bounds.isEmpty) return false;
      }
      ancestor = ancestor.parent;
    }
    return true;
  }

  void _check() {
    if (!widget.level.animated || !_enabled || !_foreground || !_visible) {
      _stop();
      return;
    }
    if (_next != null || _animation?.isAnimating == true) return;
    _play();
  }

  Duration get _sweep =>
      widget.level.tier == 'champ' ? LevelTokens.slowSweep : LevelTokens.sweep;

  void _play() {
    _animation ??= AnimationController(vsync: this)
      ..addListener(() {
        if (_animation?.isAnimating == true && !_visible) _stop();
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        final pause = widget.level.tier == 'champ'
            ? LevelTokens.slowPause
            : LevelTokens.pause;
        _next = Timer(pause, () {
          _next = null;
          if (mounted) _check();
        });
      });
    _animation!.duration = widget.level.tier == 'champ'
        ? _sweep
        : LevelTokens.burst;
    setState(() {});
    _animation!.forward(from: 0);
  }

  void _stop() {
    _next?.cancel();
    _next = null;
    _animation?.stop();
    _animation?.value = 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll?.removeListener(_checkSoon);
    _next?.cancel();
    _animation?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _BadgeVisibility(
    onPaint: _checkSoon,
    child: _Badge(level: widget.level, animation: _animation),
  );
}

/// Shared appearance; static levels never create animation or visibility state.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.level,
    this.animation,
    this.whiteBacking = false,
  });

  final LevelDefinition level;
  final AnimationController? animation;
  final bool whiteBacking;

  Duration get _sweep =>
      level.tier == 'champ' ? LevelTokens.slowSweep : LevelTokens.sweep;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final palette = LevelPalette.forStyle(t.style, level.tier);
    final scale =
        MediaQuery.textScalerOf(context).scale(LevelTokens.fontSize) /
        LevelTokens.fontSize;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final royal = level.darkTile;
    final colors = royal
        ? LevelTokens.tileColors(level.tier)
        : [palette.a, palette.b];
    final label = _LevelLabel(
      name: level.displayName,
      palette: palette,
      royal: royal,
      spaced: level.tier == 'gold' || level.tier == 'champ',
      dark: dark && !whiteBacking,
      scale: scale,
      animation: animation,
      sweep: _sweep,
    );
    final tile = Container(
      width: LevelTokens.tileSize * scale,
      height: LevelTokens.tileSize * scale,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LevelTokens.tileRadius * scale),
        gradient: LevelTokens.diagonal(colors),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LevelTokens.tileRadius * scale),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              LevelTokens.white.withValues(
                alpha: royal
                    ? LevelTokens.royalGlazeAlpha
                    : LevelTokens.glazeAlpha,
              ),
              LevelTokens.white.withValues(alpha: 0),
            ],
            stops: [
              0,
              royal ? LevelTokens.royalGlazeStop : LevelTokens.glazeStop,
            ],
          ),
        ),
        child: Center(
          child: CustomPaint(
            size: Size.square(LevelTokens.iconSize * scale),
            painter: LevelGlyphPainter(
              glyph: level.glyph,
              palette: royal ? palette : null,
              glow: false,
            ),
          ),
        ),
      ),
    );
    return Container(
      key: const ValueKey('level-plate'),
      height: LevelTokens.height * scale,
      decoration: BoxDecoration(
        color: whiteBacking
            ? LevelTokens.white
            : royal
            ? null
            : Color.alphaBlend(
                (dark ? palette.b : palette.a).withValues(
                  alpha: dark
                      ? LevelTokens.darkPlateAlpha
                      : LevelTokens.lightPlateAlpha,
                ),
                t.surface,
              ),
        gradient: royal ? LevelTokens.diagonal(palette.tile!) : null,
        borderRadius: BorderRadius.circular(LevelTokens.radius * scale),
        boxShadow: LevelTokens.shadows(
          palette,
          tier: level.tier,
          royal: royal,
          scale: scale,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (LevelTokens.innerGlow(level.tier, dark, scale) != null)
            Positioned.fill(
              child: CustomPaint(
                key: const ValueKey('level-inner-glow'),
                painter: LevelInnerGlowPainter(
                  tier: level.tier,
                  dark: dark,
                  scale: scale,
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              LevelTokens.inset * scale,
              LevelTokens.inset * scale,
              LevelTokens.rightInset * scale,
              LevelTokens.inset * scale,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    tile,
                    if (level.sparkle && animation != null)
                      Positioned(
                        left: LevelTokens.sparkleLeft * scale,
                        top: LevelTokens.sparkleTop * scale,
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: animation!,
                            builder: (_, _) {
                              final elapsed =
                                  animation!.value *
                                  animation!.duration!.inMicroseconds;
                              final p =
                                  ((elapsed -
                                              LevelTokens
                                                  .sparkleDelay
                                                  .inMicroseconds) /
                                          LevelTokens.sparkle.inMicroseconds)
                                      .clamp(0.0, 1.0);
                              return Transform.rotate(
                                angle: p * math.pi / 4,
                                child: Transform.scale(
                                  scale: math.sin(p * math.pi),
                                  child: CustomPaint(
                                    size: Size.square(
                                      LevelTokens.sparkleSize * scale,
                                    ),
                                    painter: _SparkPainter(),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(width: LevelTokens.gap * scale),
                label,
              ],
            ),
          ),
          if (level.tier == 'gold' && animation != null)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  key: const ValueKey('level-burst'),
                  child: CustomPaint(
                    painter: LevelBurstPainter(
                      animation: animation!,
                      scale: scale,
                      sparkCount: level.sparkle ? 12 : 8,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A retained badge can re-enter the viewport after layout changes without a
/// scroll notification. Its first paint schedules a visibility check.
class _BadgeVisibility extends SingleChildRenderObjectWidget {
  const _BadgeVisibility({required this.onPaint, required super.child});
  final VoidCallback onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _BadgeVisibilityRender(onPaint);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _BadgeVisibilityRender renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

class _BadgeVisibilityRender extends RenderProxyBox {
  _BadgeVisibilityRender(this.onPaint);
  VoidCallback onPaint;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}

class LevelGlyphPainter extends CustomPainter {
  LevelGlyphPainter({required this.glyph, this.palette, this.glow = false});
  final String glyph;
  final LevelPalette? palette;
  final bool glow;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / LevelTokens.glyphGrid,
      size.height / LevelTokens.glyphGrid,
    );
    final paths = LevelGlyphs.get(glyph);
    final p = palette;
    Paint ink(bool fill, {bool translucent = false}) => Paint()
      ..color = LevelTokens.white.withValues(
        alpha: p == null && translucent ? LevelTokens.glyphFillAlpha : 1,
      )
      ..shader = p == null
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: const Alignment(-.3, 1),
              colors: [
                p.a.withValues(
                  alpha: translucent ? LevelTokens.glyphFillAlpha : 1,
                ),
                p.b.withValues(
                  alpha: translucent ? LevelTokens.glyphFillAlpha : 1,
                ),
              ],
            ).createShader(
              const Rect.fromLTWH(
                0,
                0,
                LevelTokens.glyphGrid,
                LevelTokens.glyphGrid,
              ),
            )
      ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = LevelTokens.glyphStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (paths.f case final path?) {
      canvas.drawPath(path, ink(true, translucent: true));
    }
    if (paths.s case final path?) {
      canvas.drawPath(path, ink(false));
    }
    if (paths.d case final path?) {
      canvas.drawPath(path, ink(true));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LevelGlyphPainter old) =>
      glyph != old.glyph || palette != old.palette || glow != old.glow;
}

class _SparkPainter extends CustomPainter {
  static final _path = parseLevelPath(
    levelStar4(
      LevelTokens.glyphGrid / 2,
      LevelTokens.glyphGrid / 2,
      LevelTokens.glyphGrid / 2,
    ),
  );
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / LevelTokens.glyphGrid,
      size.height / LevelTokens.glyphGrid,
    );
    canvas.drawPath(_path, Paint()..color = LevelTokens.highlight);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SparkPainter old) => false;
}

class _LevelLabel extends StatelessWidget {
  const _LevelLabel({
    required this.name,
    required this.palette,
    required this.royal,
    required this.spaced,
    required this.dark,
    required this.scale,
    required this.animation,
    required this.sweep,
  });
  final String name;
  final LevelPalette palette;
  final bool royal, spaced, dark;
  final double scale;
  final AnimationController? animation;
  final Duration sweep;
  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.copyWith(
      fontSize: LevelTokens.fontSize * scale,
      height: 1,
      fontWeight: LevelTokens.fontWeight,
      letterSpacing: spaced ? LevelTokens.letterSpacing * scale : 0,
      color: royal ? null : (dark ? palette.j : palette.i),
    );
    final measure = TextPainter(
      text: TextSpan(text: name, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final size = measure.size;
    measure.dispose();
    final rect = Offset.zero & size;
    Widget text(Paint? ink) => Text(
      name,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
      softWrap: false,
      style: ink == null ? style : style.copyWith(foreground: ink),
    );
    final base = text(
      royal
          ? (Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: palette.tgD!,
              ).createShader(rect))
          : null,
    );
    if (animation == null || !royal) return base;
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          base,
          LevelShimmer(
            text: name,
            style: style,
            size: size,
            animation: animation!,
            sweep: sweep,
          ),
        ],
      ),
    );
  }
}
