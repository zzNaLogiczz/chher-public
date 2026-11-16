import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/data/portal_repository.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/feed_page.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/me_page.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/parser/header_parser.dart';
import 'package:chh_app/ui/segmented.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'messages_ui_test.dart' show FakeMessages;

class _Portal extends PortalRepository {
  _Portal() : super(ChhClient(fetchers: []));
  @override
  Future<PortalHighlights> highlights({bool refresh = false}) async =>
      const PortalHighlights(banners: [], reviews: [], news: []);
}

class _Forums extends ForumRepository {
  _Forums() : super(ChhClient(fetchers: []));
  @override
  Future<ThreadListPage> guide({
    String view = 'new',
    String? type,
    int page = 1,
    bool refresh = false,
  }) async => ThreadListPage(
    threads: [
      for (var i = 0; i < 20; i++)
        ThreadSummary(
          tid: i,
          title: '本地讨论 $i',
          author: '样例作者',
          replies: 0,
          views: 0,
        ),
    ],
    page: const PageInfo(current: 1, hasNext: false),
  );
}

void main() {
  setUp(() {
    final logged = chhSession.loggedIn;
    final badges = chhSession.badges;
    chhSession.loggedIn = false;
    chhSession.badges = const HeaderBadges(notices: 0, messages: 0);
    addTearDown(() {
      chhSession.loggedIn = logged;
      chhSession.badges = badges;
    });
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'collapsed tabs use surface foreground and status icons: $style $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final theme = buildAppTheme(brightness, style);
          final t = theme.extension<AppTokens>()!;
          final onLac = style == AppearanceStyle.cinnabar;
          final foreground = onLac ? t.onLac : t.text;
          final icons = onLac || brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark;

          Future<void> collapse(Widget page) async {
            await tester.pumpWidget(
              MaterialApp(
                key: UniqueKey(),
                theme: theme,
                home: page,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(padding: const EdgeInsets.only(top: 24)),
                  child: child!,
                ),
              ),
            );
            await tester.pumpAndSettle();
            final scroll = tester
                .widget<CustomScrollView>(find.byType(CustomScrollView).first)
                .controller!;
            scroll.jumpTo(scroll.position.maxScrollExtent.clamp(0, 400));
            await tester.pumpAndSettle();
            final overlay = tester
                .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
                  find
                      .descendant(
                        of: find.byType(LacquerTabScaffold),
                        matching: find.byType(
                          AnnotatedRegion<SystemUiOverlayStyle>,
                        ),
                      )
                      .first,
                )
                .value;
            expect(overlay.statusBarIconBrightness, icons);
            expect(
              overlay.statusBarBrightness,
              icons == Brightness.light ? Brightness.dark : Brightness.light,
            );
            expect(tester.takeException(), isNull);
          }

          void expectTitle(String title, Finder scope) {
            final label = find.descendant(
              of: scope,
              matching: find.text(title),
            );
            expect(label, findsOneWidget);
            expect(tester.widget<Text>(label).style!.color, foreground);
          }

          await collapse(const MePage());
          final guestTitle = onLac ? '登录 CHH' : '未登录';
          expectTitle(guestTitle, find.byType(SlidingCompactTitle));
          expect(
            find
                .descendant(
                  of: find.byType(SlidingCompactTitle),
                  matching: find.text(guestTitle),
                )
                .hitTestable(),
            findsOneWidget,
          );

          await collapse(
            FeedPage(portalRepository: _Portal(), forumRepository: _Forums()),
          );
          expectTitle('精选', find.byType(SlidingCompactTitle));
          expectTitle('社区讨论', find.byType(SlidingCompactTitle));
          expect(
            tester.widget<Icon>(find.byIcon(AppIcons.search)).color,
            foreground,
          );
          final feed = tester.widget<LacquerTabScaffold>(
            find.byType(LacquerTabScaffold),
          );
          expect((feed.compactAccessory! as AppSegmented<String>).onLac, onLac);

          await collapse(
            ForumIndexView(
              loadForums: (_) async => [
                ForumCategory(
                  name: '互动区',
                  forums: [
                    for (var i = 0; i < 20; i++) Forum(fid: i, name: '样例版块 $i'),
                  ],
                ),
              ],
            ),
          );
          final directory = find.byKey(const ValueKey('forum-directory-jump'));
          expectTitle('互动区', directory);
          expect(
            tester
                .widget<Icon>(
                  find.descendant(
                    of: directory,
                    matching: find.byIcon(AppIcons.down),
                  ),
                )
                .color,
            foreground,
          );

          await collapse(MessagesPage(repository: FakeMessages()));
          expect(
            tester.widget<Icon>(find.byIcon(AppIcons.back)).color,
            foreground,
          );
          final segments = tester.widgetList<AppSegmented<int>>(
            find.byType(AppSegmented<int>),
          );
          expect(segments.where((segment) => segment.compact), isNotEmpty);
          for (final segment in segments) {
            expect(segment.onLac, onLac);
          }
          expect(tester.binding.transientCallbackCount, 0);
        },
      );
    }
  }
}
