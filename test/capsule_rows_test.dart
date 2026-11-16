import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/data/portal_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/feed_page.dart';
import 'package:chh_app/ui/grouped.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/ui/press.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Portal extends PortalRepository {
  final List<NewsItem> news;
  _Portal(this.news) : super(ChhClient(fetchers: []));
  @override
  Future<PortalHighlights> highlights({bool refresh = false}) async =>
      PortalHighlights(reviews: [], banners: [], news: news);
}

class _Forum extends ForumRepository {
  _Forum() : super(ChhClient(fetchers: []));
  @override
  Future<ThreadListPage> guide({
    String view = 'new',
    String? type,
    int page = 1,
    bool refresh = false,
  }) async => const ThreadListPage(
    threads: [],
    page: PageInfo(current: 1, hasNext: false),
  );
}

Finder surfaceOf(Finder content) => find
    .ancestor(
      of: content,
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            (w.decoration is ShapeDecoration ||
                w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).borderRadius != null &&
                    (w.decoration as BoxDecoration).color != null),
      ),
    )
    .first;

double radiusOf(WidgetTester tester, Finder surface) {
  final decoration = tester.widget<DecoratedBox>(surface).decoration;
  if (decoration is BoxDecoration) {
    return (decoration.borderRadius! as BorderRadius).topLeft.x;
  }
  final shape = (decoration as ShapeDecoration).shape;
  final radius = shape is RoundedSuperellipseBorder
      ? shape.borderRadius
      : (shape as RoundedRectangleBorder).borderRadius;
  // Flutter normalizes full radii to half the shorter side when painting.
  return radius
      .resolve(TextDirection.ltr)
      .topLeft
      .x
      .clamp(0, tester.getSize(surface).shortestSide / 2);
}

void main() {
  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      Widget app(
        Widget body, {
        double scale = 1,
        bool reduced = false,
        double spacing = 0,
      }) => MaterialApp(
        theme: buildAppTheme(brightness, style).copyWith(
          textTheme: buildAppTheme(brightness, style).textTheme.copyWith(
            bodyMedium: buildAppTheme(
              brightness,
              style,
            ).textTheme.bodyMedium!.copyWith(letterSpacing: spacing),
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: Scaffold(body: body),
      );
      testWidgets(
        'single grouped row is a capsule; multiple/subtitle rows stay cards $style $brightness',
        (tester) async {
          await tester.pumpWidget(
            app(
              ListView(
                children: const [
                  GroupedSection(
                    children: [GroupedRow(title: '好友', value: '1')],
                  ),
                  GroupedSection(
                    children: [
                      GroupedRow(title: '注册', value: '2026'),
                      GroupedRow(title: '访问', value: '今天'),
                    ],
                  ),
                  GroupedSection(
                    children: [GroupedRow(title: '两行', subtitle: '资料')],
                  ),
                ],
              ),
            ),
          );
          final single = surfaceOf(find.text('好友'));
          expect(tester.getSize(single).height, 44);
          expect(radiusOf(tester, single), 22);
          final multi = surfaceOf(find.text('注册'));
          expect(tester.getSize(multi).height, 96);
          expect(radiusOf(tester, multi), 18);
          expect(radiusOf(tester, surfaceOf(find.text('两行'))), 18);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'pinned outer inset toggles and keeps 22 radius through expansion $style $brightness',
        (tester) async {
          var expanded = false;
          await tester.pumpWidget(
            app(
              StatefulBuilder(
                builder: (context, setState) => Align(
                  alignment: Alignment.topCenter,
                  child: PinnedGroupRow(
                    count: 1,
                    firstTitle: '本地置顶',
                    expanded: expanded,
                    onToggle: () => setState(() => expanded = !expanded),
                    itemBuilder: (_, _) =>
                        const SizedBox(height: 80, child: Text('展开内容')),
                  ),
                ),
              ),
            ),
          );
          final surface = surfaceOf(find.text('置顶'));
          expect(tester.getSize(surface).height, 44);
          expect(radiusOf(tester, surface), 22);
          final press = tester.widget<PressHighlight>(
            find
                .descendant(
                  of: find.byType(PinnedGroupRow),
                  matching: find.byType(PressHighlight),
                )
                .first,
          );
          expect(press.borderRadius!.topLeft.x, 18);
          final gesture = await tester.startGesture(
            tester.getRect(surface).topCenter + const Offset(0, 1),
          );
          await tester.pump();
          expect(
            find.descendant(
              of: find.byType(PinnedGroupRow),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is ColoredBox &&
                    w.color == AppTokens.of(tester.element(surface)).pressed,
              ),
            ),
            findsOneWidget,
          );
          await gesture.up();
          await tester.pumpAndSettle();
          expect(expanded, isTrue);
          expect(tester.getSize(surface).height, greaterThan(44));
          expect(radiusOf(tester, surface), 22);
          expect(find.text('展开内容'), findsOneWidget);
          await tester.tap(find.text('置顶'));
          await tester.pumpAndSettle();
          expect(tester.getSize(surface).height, 44);
          expect(find.text('展开内容'), findsNothing);
          expect(tester.binding.transientCallbackCount, 0);
        },
      );

      for (final sample in [
        (title: '本地快讯', count: 1, capsule: true, scale: 1.0, spacing: 0.0),
        (
          title: '本地快讯标题需要占用两行来完整展示其新闻内容及更多说明',
          count: 1,
          capsule: false,
          scale: 1.0,
          spacing: 0.0,
        ),
        (title: '本地快讯', count: 2, capsule: false, scale: 1.0, spacing: 0.0),
        (
          title: '系统大字号下的本地新闻',
          count: 1,
          capsule: false,
          scale: 2.0,
          spacing: 0.0,
        ),
        (
          title: '宽度边界字距测试快讯文字',
          count: 1,
          capsule: true,
          scale: 1.0,
          spacing: 0.0,
        ),
        (
          title: '宽度边界字距测试快讯文字',
          count: 1,
          capsule: false,
          scale: 1.0,
          spacing: 5.0,
        ),
      ]) {
        testWidgets(
          'news uses measured width ${sample.count} ${sample.title} spacing=${sample.spacing} $style $brightness',
          (tester) async {
            tester.view.physicalSize = const Size(320, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              app(
                FeedPage(
                  portalRepository: _Portal(
                    List.generate(
                      sample.count,
                      (i) => NewsItem(tid: i + 1, title: sample.title),
                    ),
                  ),
                  forumRepository: _Forum(),
                ),
                scale: sample.scale,
                spacing: sample.spacing,
              ),
            );
            await tester.pumpAndSettle();
            final surface = surfaceOf(find.text(sample.title).first);
            expect(
              tester.getSize(surface).height,
              sample.capsule ? 44 : greaterThan(44),
            );
            expect(radiusOf(tester, surface), 22);
            final decoration = tester.widget<DecoratedBox>(surface).decoration;
            expect(decoration is ShapeDecoration, sample.capsule);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
