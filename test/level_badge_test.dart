import 'dart:ui' as ui;
import 'package:chh_app/design/level_tokens.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/level_badge.dart';
import 'package:chh_app/widgets/level_glow.dart';
import 'package:chh_app/widgets/level_shimmer.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  AppearanceStyle style = AppearanceStyle.cinnabar,
  bool reduced = true,
  bool ticker = true,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness, style),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: TickerMode(
              enabled: ticker,
              child: Align(alignment: Alignment.topLeft, child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Container plate(WidgetTester tester) =>
    tester.widget<Container>(find.byKey(const ValueKey('level-plate')));

// Count the actual position subscriptions, including framework subscriptions,
// so the empty-list baseline detects any listeners added by badges.
class _CountingScrollPosition extends ScrollPositionWithSingleContext {
  _CountingScrollPosition({required super.physics, required super.context});

  int listenerCount = 0;

  @override
  void addListener(VoidCallback listener) {
    listenerCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount--;
    super.removeListener(listener);
  }
}

class _CountingScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _CountingScrollPosition(physics: physics, context: context);

  int get listenerCount => (position as _CountingScrollPosition).listenerCount;
}

void main() {
  test(
    'white and gradient glyph faces retain exactly 30 percent alpha',
    () async {
      for (final palette in [
        null,
        LevelPalette.forStyle(AppearanceStyle.misty, 'gold'),
      ]) {
        final recorder = ui.PictureRecorder();
        LevelGlyphPainter(
          glyph: 'shield',
          palette: palette,
        ).paint(Canvas(recorder), const Size(240, 240));
        final picture = recorder.endRecording();
        final image = picture.toImageSync(240, 240);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(
          bytes!.getUint8((170 * 240 + 120) * 4 + 3),
          closeTo(255 * .30, 1),
        );
        image.dispose();
        picture.dispose();
      }
    },
  );

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$style $brightness renders ordinary, imp, fiend and king', (
        tester,
      ) async {
        for (final gid in [41, 48, 55, 64, 1, 2, 3, 56]) {
          await mount(
            tester,
            LevelBadge(key: ValueKey(gid), gid: gid),
            style: style,
            brightness: brightness,
          );
          final level = LevelDefinition.lookup(gid)!;
          final palette = LevelPalette.forStyle(style, level.tier);
          final decoration = plate(tester).decoration! as BoxDecoration;
          final text = tester.widgetList<Text>(find.text(level.displayName));
          expect(text, isNotEmpty);
          if (level.darkTile) {
            expect(decoration.gradient!.colors, palette.tile);
            expect(text.first.style!.foreground!.shader, isNotNull);
            expect(text.first.style!.fontVariations!.single.value, 650);
          } else {
            final dark = brightness == Brightness.dark;
            final tokens = tokensFor(brightness, style);
            expect(
              decoration.color,
              Color.alphaBlend(
                (dark ? palette.b : palette.a).withValues(
                  alpha: dark ? .26 : .22,
                ),
                tokens.surface,
              ),
            );
            expect(text.first.style!.color, dark ? palette.j : palette.i);
          }
          expect(decoration.boxShadow ?? [], hasLength(level.darkTile ? 1 : 0));
          if (level.darkTile) {
            final shadow = decoration.boxShadow!.single;
            expect(shadow.color, const Color.fromRGBO(0, 0, 0, .45));
            expect(shadow.offset, const Offset(0, 1));
            expect(shadow.blurRadius, 2);
            expect(shadow.spreadRadius, -1);
          }
          final glow = find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter is LevelInnerGlowPainter,
          );
          expect(glow, gid == 41 ? findsNothing : findsOneWidget);
          for (final glyph in tester.widgetList<CustomPaint>(
            find.byType(CustomPaint),
          )) {
            if (glyph.painter case final LevelGlyphPainter painter) {
              expect(painter.glow, isFalse);
            }
          }
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.binding.transientCallbackCount, 0);
        }
      });
    }
  }

  testWidgets('every static level has no repaint boundaries or shimmer', (
    tester,
  ) async {
    for (final gid in [
      59,
      49,
      38,
      39,
      40,
      41,
      42,
      43,
      44,
      45,
      46,
      48,
      55,
      64,
    ]) {
      await mount(tester, LevelBadge(gid: gid), reduced: false);
      expect(
        find.descendant(
          of: find.byType(LevelBadge),
          matching: find.byType(RepaintBoundary),
        ),
        findsNothing,
        reason: 'static gid $gid must not introduce layers',
      );
      expect(find.byType(LevelShimmer), findsNothing);
      // Allow framework text/theme transitions between level variants to settle.
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.transientCallbackCount, 0);
    }
  });

  testWidgets('static badge count does not increase scroll subscriptions', (
    tester,
  ) async {
    final scroll = _CountingScrollController();
    final groups = ValueNotifier<List<int>>([]);
    await mount(
      tester,
      SizedBox(
        height: 120,
        child: SingleChildScrollView(
          controller: scroll,
          child: ValueListenableBuilder<List<int>>(
            valueListenable: groups,
            builder: (_, gids, _) => Column(
              children: [
                for (var i = 0; i < gids.length; i++)
                  LevelBadge(key: ValueKey(i), gid: gids[i]),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
      reduced: false,
    );
    final baseline = scroll.listenerCount;
    for (final count in [1, 30]) {
      groups.value = List.generate(count, (i) => [41, 48, 55, 64][i % 4]);
      await tester.pump();
      expect(scroll.listenerCount, baseline);
      scroll.jumpTo(100);
      await tester.pump();
      expect(scroll.listenerCount, baseline);
      expect(tester.binding.transientCallbackCount, 0);
      scroll.jumpTo(0);
      await tester.pump();
    }
    // This also checks that replacing a retained static badge with an animated
    // one adds exactly one subscription, and switching back removes it.
    groups.value = [1];
    await tester.pump();
    await tester.pump();
    expect(scroll.listenerCount, baseline + 1);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    groups.value = [55];
    await tester.pump();
    expect(scroll.listenerCount, baseline);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    groups.dispose();
  });

  testWidgets(
    'animated badges isolate only burst, shimmer and optional sparkle',
    (tester) async {
      for (final gid in [1, 2, 3, 56]) {
        await mount(tester, LevelBadge(gid: gid), reduced: false);
        final boundaries = find.descendant(
          of: find.byType(LevelBadge),
          matching: find.byType(RepaintBoundary),
        );
        expect(boundaries, findsNWidgets(gid == 1 ? 3 : (gid == 56 ? 1 : 2)));
        expect(
          find.descendant(
            of: find.byType(LevelShimmer),
            matching: find.byType(RepaintBoundary),
          ),
          findsOneWidget,
        );
        for (final boundary in boundaries.evaluate()) {
          expect(
            find.descendant(
              of: find.byWidget(boundary.widget),
              matching: find.byType(Text),
            ),
            findsNothing,
            reason: 'base text must remain outside animated boundaries',
          );
          expect(
            find.descendant(
              of: find.byWidget(boundary.widget),
              matching: find.byKey(const ValueKey('level-plate')),
            ),
            findsNothing,
          );
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'gold burst has the specified particles and shares the shimmer clock',
    (tester) async {
      for (final entry in {1: 12, 2: 8, 3: 8, 56: 0}.entries) {
        await mount(
          tester,
          LevelBadge(key: ValueKey(entry.key), gid: entry.key),
          reduced: false,
        );
        final bursts = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<LevelBurstPainter>();
        if (entry.value == 0) {
          expect(bursts, isEmpty);
        } else {
          expect(bursts.single.sparkCount, entry.value);
          expect(bursts.single.particles.length, entry.value);
          expect(
            bursts.single.particles.toList(),
            entry.value == 12
                ? LevelTokens.sparks
                : [
                    for (var i = 0; i < LevelTokens.sparks.length; i++)
                      if (i % 3 != 2) LevelTokens.sparks[i],
                  ],
          );
          expect(
            bursts.single.animation,
            same(
              tester.widget<LevelShimmer>(find.byType(LevelShimmer)).animation,
            ),
          );
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'enabling reduced motion during burst leaves static inner light and gold text',
    (tester) async {
      await mount(tester, const LevelBadge(gid: 1), reduced: false);
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await mount(tester, const LevelBadge(gid: 1));
      await tester.pump(const Duration(seconds: 10));
      expect(tester.binding.transientCallbackCount, 0);
      final text = tester.widget<Text>(find.text('圣魔王').first);
      expect(text.style!.foreground!.shader, isNotNull);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is LevelInnerGlowPainter,
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unknown groups have no plate', (tester) async {
    for (final gid in [null, 4, 54, 63, 65, 7]) {
      await mount(tester, LevelBadge(gid: gid));
      expect(find.byKey(const ValueKey('level-plate')), findsNothing);
    }
  });

  testWidgets('badge has one accessible label and tap opens its callback', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await mount(tester, LevelBadge(gid: 41, onTap: () => taps++));
    expect(find.bySemanticsLabel('等级 能天使'), findsOneWidget);
    await tester.tap(find.byType(LevelBadge));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets(
    'long press shows authoritative threshold without activating tap',
    (tester) async {
      var taps = 0;
      await mount(tester, LevelBadge(gid: 41, onTap: () => taps++));
      await tester.longPress(find.byType(LevelBadge));
      await tester.pump();
      expect(find.text('积分 2,500 起'), findsOneWidget);
      expect(taps, 0);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
    },
  );

  testWidgets(
    'system text scaling expands plate, tile, icon and text together',
    (tester) async {
      await mount(tester, const LevelBadge(gid: 41));
      final width = tester
          .getSize(find.byKey(const ValueKey('level-plate')))
          .width;
      await mount(tester, const LevelBadge(gid: 41), scale: 2);
      final size = tester.getSize(find.byKey(const ValueKey('level-plate')));
      expect(size.height, 40);
      expect(size.width, closeTo(width * 2, .1));
      expect(tester.widget<Text>(find.text('能天使')).style!.fontSize, 23);
      final icon = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is LevelGlyphPainter,
      );
      expect(tester.getSize(icon), const Size(23, 23));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('king respects reduced motion and inactive TickerMode', (
    tester,
  ) async {
    await mount(tester, const LevelBadge(gid: 1));
    await tester.pump(const Duration(seconds: 10));
    expect(tester.binding.transientCallbackCount, 0);
    await mount(
      tester,
      const LevelBadge(gid: 1),
      reduced: false,
      ticker: false,
    );
    await tester.pump(const Duration(seconds: 10));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'king stops after one sweep and star, then restarts after timer',
    (tester) async {
      await mount(tester, const LevelBadge(gid: 1), reduced: false);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 2901));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(milliseconds: 1699));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(milliseconds: 2));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      // Disposal while active, and disposal during the next waiting period.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      expect(tester.binding.transientCallbackCount, 0);
      await mount(tester, const LevelBadge(gid: 1), reduced: false);
      await tester.pump(const Duration(milliseconds: 2901));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'apprentice uses slow sweep and timer, static levels never tick',
    (tester) async {
      for (final gid in [41, 48, 55, 64]) {
        await mount(
          tester,
          LevelBadge(key: ValueKey(gid), gid: gid),
          reduced: false,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.binding.transientCallbackCount, 0);
      }
      await mount(
        tester,
        const LevelBadge(key: ValueKey(56), gid: 56),
        reduced: false,
      );
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 1601));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(milliseconds: 4799));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(milliseconds: 2));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('scrolling king out of viewport suspends animation and timers', (
    tester,
  ) async {
    final scroll = ScrollController();
    await mount(
      tester,
      SizedBox(
        height: 120,
        child: SingleChildScrollView(
          controller: scroll,
          child: const Column(
            children: [LevelBadge(gid: 1), SizedBox(height: 1000)],
          ),
        ),
      ),
      reduced: false,
    );
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    scroll.jumpTo(300);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 10));
    expect(tester.binding.transientCallbackCount, 0);
    scroll.jumpTo(0);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets('app background suspends king and resumes visible badge', (
    tester,
  ) async {
    await mount(tester, const LevelBadge(gid: 1), reduced: false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 10));
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'layout changes without scrolling resume and suspend retained badge',
    (tester) async {
      final top = ValueNotifier<double>(300);
      await mount(
        tester,
        SizedBox(
          height: 120,
          child: SingleChildScrollView(
            child: ValueListenableBuilder<double>(
              valueListenable: top,
              builder: (_, height, child) => Column(
                children: [
                  SizedBox(height: height),
                  child!,
                  const SizedBox(height: 1000),
                ],
              ),
              child: const LevelBadge(gid: 1),
            ),
          ),
        ),
        reduced: false,
      );
      expect(tester.binding.transientCallbackCount, 0);
      top.value = 0;
      await tester.pump();
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      top.value = 300;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      top.dispose();
    },
  );

  for (final opening in [false, true]) {
    testWidgets(
      'long ${opening ? 'opening' : 'reply'} name truncates before badge and owner',
      (tester) async {
        const name = '这是一个非常长的作者名字用于验证徽章和楼主不会被截断';
        await mount(
          tester,
          SizedBox(
            width: 320,
            child: PostCard.header(
              post: const Post(
                pid: 100,
                floor: 1,
                author: name,
                authorGroupId: 41,
                timeRaw: '',
                content: [],
              ),
              isOpening: opening,
              isAuthor: true,
            ),
          ),
        );
        expect(find.text('能天使'), findsOneWidget);
        expect(find.text('楼主'), findsOneWidget);
        final author = tester.renderObject<RenderParagraph>(find.text(name));
        expect(author.didExceedMaxLines, isTrue);
        expect(author.overflow, TextOverflow.ellipsis);
        final badge = tester.getRect(find.byType(LevelBadge));
        final owner = tester.getRect(find.text('楼主'));
        expect(
          badge.left,
          greaterThanOrEqualTo(tester.getRect(find.text(name)).right),
        );
        expect(owner.left, greaterThan(badge.right));
        expect(owner.right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('320dp double text preserves apprentice badge and owner', (
    tester,
  ) async {
    await mount(
      tester,
      const SizedBox(
        width: 320,
        child: PostCard.header(
          post: Post(
            pid: 100,
            floor: 2,
            author: '很长很长的作者名字',
            authorGroupId: 56,
            timeRaw: '',
            content: [],
          ),
          isOpening: false,
          isAuthor: true,
        ),
      ),
      scale: 2,
    );
    expect(find.text('见习迪亚波罗'), findsOneWidget);
    expect(find.text('楼主'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(LevelBadge)).right,
      lessThanOrEqualTo(320),
    );
    expect(tester.getRect(find.text('楼主')).right, lessThanOrEqualTo(320));
  });

  testWidgets('suppressed post never exposes a badge', (tester) async {
    for (final opening in [false, true]) {
      await mount(
        tester,
        PostCard.header(
          post: const Post(
            pid: 100,
            floor: 1,
            author: '受屏蔽作者',
            authorGroupId: 41,
            timeRaw: '',
            content: [],
            lock: PostLock(text: '作者被禁止或删除，内容已自动屏蔽', needsPassword: false),
          ),
          isOpening: opening,
        ),
      );
      expect(find.byType(LevelBadge), findsNothing);
    }
  });
}
