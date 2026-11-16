import 'dart:io';

import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/data/image_disk_cache.dart';
import 'package:chh_app/data/thread_read_index.dart';
import 'package:chh_app/design/forum_tokens.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/widgets/avatar_image.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _Images extends Fake implements HttpClient {
  final requested = <Uri>[];
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    throw const SocketException('offline fixture');
  }
}

ThreadSummary _thread(int tid, {String? uid}) => ThreadSummary(
  tid: tid,
  title: '帖子标题 $tid',
  author: '作者 $tid',
  authorUid: uid,
  typeName: 'CPU',
  replies: 17,
  views: 200,
  hasImages: true,
);

Widget _app(
  Widget body, [
  AppearanceStyle style = AppearanceStyle.cinnabar,
  Brightness brightness = Brightness.light,
]) => MaterialApp(
  theme: buildAppTheme(brightness, style),
  themeAnimationDuration: Duration.zero,
  home: Scaffold(body: body),
);

void main() {
  late _Images client;
  setUp(() {
    client = _Images();
    imageDiskCache = ImageDiskCache(null);
    imageHttpClientFactory = () => client;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('forum row colors and read transition $style $brightness', (
        tester,
      ) async {
        Widget row(ThreadReadState state) => _app(
          ThreadRow(
            thread: _thread(1),
            forumStyle: true,
            readState: state,
            timeLabel: '12:34',
          ),
          style,
          brightness,
        );
        await tester.pumpWidget(row(const ThreadReadNewReplies(3)));
        await tester.pumpAndSettle();
        final t = AppTokens.of(tester.element(find.byType(ThreadRow)));
        final title = tester.widget<Text>(find.text('帖子标题 1'));
        expect(title.style!.fontSize, ForumTokens.title.fontSize);
        expect(title.style!.height, 1.42);
        expect(title.maxLines, 2);
        expect(title.style!.color, t.text);
        expect(find.text('+3'), findsOneWidget);
        expect(tester.widget<AvatarImage>(find.byType(AvatarImage)).size, 18);
        expect(client.requested, isEmpty);
        expect(find.textContaining('·', findRichText: true), findsNothing);
        await tester.pumpWidget(row(const ThreadReadSeen()));
        await tester.pump(const Duration(milliseconds: 90));
        expect(
          tester.widget<Text>(find.text('帖子标题 1')).style!.color,
          isNot(t.text2),
        );
        expect(find.text('+3'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(find.text('帖子标题 1')).style!.color, t.text2);
        expect(find.text('+3'), findsNothing);
        expect(find.text('回复'), findsOneWidget);
        expect(find.text('17'), findsOneWidget);
        final faded = tester.widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byType(AvatarImage),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(faded.opacity, ForumTokens.seenAvatarOpacity);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'only painted avatars request detail URLs, failures show app logo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          ListView.builder(
            controller: controller,
            scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
            itemExtent: 100,
            itemCount: 30,
            itemBuilder: (_, i) => ThreadRow(
              thread: _thread(i, uid: '${68733 + i}'),
              forumStyle: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(AvatarImage, skipOffstage: false).evaluate().length,
        greaterThan(4),
      );
      expect(client.requested.length, greaterThan(0));
      expect(client.requested.length, lessThanOrEqualTo(4));
      expect(client.requested.first.toString(), ChhUrls.avatar('68733'));
      expect(
        client.requested.every((url) => !url.path.contains('avatar.php')),
        isTrue,
      );
      expect(
        client.requested.any(
          (url) => url.toString() == ChhUrls.avatar('68743'),
        ),
        isFalse,
      );
      expect(find.byKey(const ValueKey('avatar-logo')), findsWidgets);
      final calls = client.requested.length;
      await tester.pump(const Duration(seconds: 1));
      expect(client.requested.length, calls);
      controller.jumpTo(1000);
      await tester.pumpAndSettle();
      expect(
        client.requested.any(
          (url) => url.toString() == ChhUrls.avatar('68743'),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('forum row supports large text and preserves access to login', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var logins = 0;
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Column(
            children: [
              ThreadRow(
                thread: _thread(1),
                forumStyle: true,
                readState: const ThreadReadNewReplies(123456),
              ),
              ThreadRow(
                thread: _thread(2),
                forumStyle: true,
                locked: true,
                onLogin: () => logins++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('登录'));
    expect(logins, 1);
  });
}
