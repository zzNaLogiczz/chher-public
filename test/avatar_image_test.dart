import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chh_app/core/chh_urls.dart';
import 'package:chh_app/data/image_disk_cache.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/user_page.dart';
import 'package:chh_app/ui/plain_rows.dart';
import 'package:chh_app/widgets/avatar_image.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

import 'support/space_fixtures.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);
final _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8'
  'AAAAASUVORK5CYII=',
);

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _Client extends Fake implements HttpClient {
  int calls = 0;
  final requested = <Uri>[];
  int status = 200;
  Completer<HttpClientResponse>? pending;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    calls++;
    requested.add(url);
    return _Request(this, url);
  }
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.client, this.uri);
  final _Client client;
  @override
  final Uri uri;
  @override
  final headers = _Headers();
  @override
  Future<HttpClientResponse> close() async =>
      client.pending?.future ?? Future.value(_Response(client.status));
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode);
  @override
  final int statusCode;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_png).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child) => MaterialApp(
  themeAnimationDuration: Duration.zero,
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

bool _networkFrame(WidgetTester tester) => tester
    .widgetList<RawImage>(find.byType(RawImage))
    .any((image) => image.image?.width == 1);

Finder get _logo => find.byKey(const ValueKey('avatar-logo'));

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('Avatar did not reach expected state');
}

void main() {
  const url = 'https://example.test/avatar.jpg';
  late Directory dir;
  late _Client client;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('avatar_widget_test');
    imageDiskCache = ImageDiskCache(dir);
    client = _Client();
    imageHttpClientFactory = () => client;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    imageDiskCache = ImageDiskCache(null);
    dir.deleteSync(recursive: true);
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('fallback avatar uses app logo in $style $brightness', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness, style),
            home: const Scaffold(
              body: Center(child: AvatarImage(name: '千河', size: 32)),
            ),
          ),
        );
        expect(find.text('千'), findsNothing);
        expect(tester.getSize(_logo), const Size(32, 32));
        expect(
          (tester.widget<Image>(_logo).image as ResizeImage).imageProvider,
          const AssetImage('assets/brand/chhers-logo.png'),
        );
        expect(tester.binding.transientCallbackCount, 0);
        expect(client.calls, 0);
      });
    }
  }

  for (final (style, brightness, expected) in [
    (AppearanceStyle.misty, Brightness.light, 0xEEF0F3FF),
    (AppearanceStyle.misty, Brightness.dark, 0x26282CFF),
    (AppearanceStyle.cinnabar, Brightness.light, 0xF1EBE9FF),
    (AppearanceStyle.cinnabar, Brightness.dark, 0x272221FF),
  ]) {
    testWidgets('transparent avatar has a round frame in $style $brightness', (
      tester,
    ) async {
      await tester.runAsync(() => imageDiskCache.write(url, _transparentPng));
      const boundaryKey = ValueKey('avatar-boundary');
      const size = 32;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness, style),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: AvatarImage(url: url, size: size.toDouble()),
              ),
            ),
          ),
        ),
      );
      await _pumpUntil(tester, () => _networkFrame(tester));
      await tester.pumpAndSettle();
      expect(_logo, findsNothing);
      expect(client.calls, 0);
      expect(tester.binding.transientCallbackCount, 0);

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final bytes = (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        } finally {
          image.dispose();
        }
      }))!;
      const center = (size * (size ~/ 2) + size ~/ 2) * 4;
      expect(bytes.getUint32(center), expected);
      expect(bytes.getUint8(3), 0);
    });
  }

  testWidgets(
    'async avatar crossfades in place; a memory cache hit displays directly',
    (tester) async {
      await tester.pumpWidget(
        _app(const AvatarImage(name: '千河', url: url, size: 44)),
      );
      final avatar = find.byType(AvatarImage);
      final size = tester.getSize(avatar);
      expect(size, const Size.square(44));
      expect(_logo, findsOneWidget);
      await _pumpUntil(tester, () => _networkFrame(tester));
      final fade = find.descendant(of: avatar, matching: find.byType(Opacity));
      expect(fade, findsNWidgets(2));
      expect(tester.widget<Opacity>(fade.first).opacity, 1);
      expect(tester.widget<Opacity>(fade.last).opacity, 0);
      final midpoint = AppMotion.mediaFade ~/ 2;
      await tester.pump(midpoint);
      final logoAlpha = tester.widget<Opacity>(fade.first).opacity;
      final avatarAlpha = tester.widget<Opacity>(fade.last).opacity;
      expect(avatarAlpha, allOf(greaterThan(0), lessThan(1)));
      expect(logoAlpha, closeTo(1 - avatarAlpha, .001));
      expect(tester.getSize(avatar), size);
      await tester.pump(midpoint);
      expect(tester.widget<Opacity>(fade).opacity, 1);
      expect(_logo, findsNothing);
      expect(tester.getSize(avatar), size);
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pumpWidget(
        _app(const AvatarImage(name: '千河', url: url, size: 44)),
      );
      expect(_networkFrame(tester), isTrue);
      expect(fade, findsNothing);
      expect(client.calls, 1);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('missing avatar shows app logo without a network request', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const AvatarImage(name: '  @chher', size: 44)),
    );
    await tester.pumpAndSettle();
    expect(_logo, findsOneWidget);
    expect(find.byIcon(AppIcons.image), findsNothing);
    expect(client.calls, 0);
    expect(find.text('C'), findsNothing);
  });

  testWidgets('list and detail reuse the same avatar disk entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const ThreadRow(
          thread: ThreadSummary(
            tid: 1,
            title: '示例帖子',
            author: '千河',
            authorUid: '1001',
            replies: 0,
            views: 0,
          ),
          forumStyle: true,
        ),
      ),
    );
    await _pumpUntil(tester, () => _networkFrame(tester));
    expect(client.requested.single.toString(), ChhUrls.avatar('1001'));
    await tester.pumpWidget(_app(const SizedBox()));
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.pumpWidget(
      _app(AvatarImage(name: '千河', url: ChhUrls.avatar('1001'), size: 88)),
    );
    await _pumpUntil(tester, () => _networkFrame(tester));
    expect(client.calls, 1);
  });

  testWidgets(
    'cached parent layer starts a lazy avatar when scrolled into view',
    (tester) async {
      final controller = ScrollController();
      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 240,
            child: SingleChildScrollView(
              controller: controller,
              child: const RepaintBoundary(
                child: Column(
                  children: [
                    SizedBox(height: 500),
                    AvatarImage(name: '屏外作者', url: url, size: 44, lazy: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
      );
      await tester.pumpAndSettle();
      expect(
        client.calls,
        0,
        reason: 'Offscreen layout must not request the avatar',
      );
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await _pumpUntil(tester, () => _networkFrame(tester));
      expect(client.requested.single.toString(), url);
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        client.calls,
        1,
        reason: 'An already visible avatar must not request again',
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('returning to a failed avatar recovers only from filled cache', (
    tester,
  ) async {
    client.status = 404;
    await tester.pumpWidget(
      _app(const AvatarImage(name: '千河', url: url, size: 18, lazy: true)),
    );
    await _pumpUntil(tester, () => client.calls == 1);
    await tester.pumpAndSettle();
    final listState = tester.state(find.byType(AvatarImage));
    final navigator = Navigator.of(tester.element(find.byType(AvatarImage)));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(_logo, findsOneWidget);
    expect(client.calls, 1, reason: 'A cache miss must not retry the server');

    client.status = 200;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: AvatarImage(name: '千河', url: url, size: 88),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () => _networkFrame(tester));
    navigator.pop();
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () => _networkFrame(tester));
    expect(tester.state(find.byType(AvatarImage)), same(listState));
    expect(client.calls, 2, reason: 'Returning reuses the detail download');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed avatar shows app logo, manual retry succeeds and is cached',
    (tester) async {
      client.status = 404;
      await tester.pumpWidget(
        _app(
          const AvatarImage(name: '千河', url: url, size: 88, refreshable: true),
        ),
      );
      await _pumpUntil(
        tester,
        () => client.calls == 1 && _logo.evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(_logo, findsOneWidget);
      expect(find.text('千'), findsNothing);
      expect(await tester.runAsync(() => imageDiskCache.read(url)), isNull);
      expect(find.byIcon(AppIcons.image), findsNothing);
      client.status = 200;
      await _refreshAvatar(tester, find.byType(AvatarImage));
      await _pumpUntil(
        tester,
        () => client.calls == 2 && _networkFrame(tester),
      );
      await tester.pumpAndSettle();
      expect(_logo, findsNothing);
      expect(await tester.runAsync(() => imageDiskCache.read(url)), isNotNull);
      await tester.pumpWidget(_app(const SizedBox()));
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.pumpWidget(
        _app(const AvatarImage(name: '千河', url: url, size: 44)),
      );
      await _pumpUntil(tester, () => _networkFrame(tester));
      expect(client.calls, 2, reason: 'Re-entry uses successful disk cache');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed manual refresh keeps app logo and no disk entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const AvatarImage(name: '千河', url: url, size: 88, refreshable: true),
      ),
    );
    await _pumpUntil(tester, () => _networkFrame(tester));
    client.status = 500;
    await _refreshAvatar(tester, find.byType(AvatarImage));
    await _pumpUntil(
      tester,
      () => find.text('头像加载失败，请重试').evaluate().isNotEmpty,
    );
    expect(_logo, findsOneWidget);
    expect(find.text('千'), findsNothing);
    expect(await tester.runAsync(() => imageDiskCache.read(url)), isNull);
    expect(client.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile avatar refreshes in place without reloading profile', (
    tester,
  ) async {
    final profile = _AvatarProfile(url);
    await tester.pumpWidget(_app(UserPage(uid: '42', repository: profile)));
    await _pumpUntil(tester, () => _networkFrame(tester));
    final card = find.byKey(UserPage.identityKey);
    final avatar = find.descendant(
      of: card,
      matching: find.byType(AvatarImage),
    );
    expect(avatar, findsOneWidget);
    expect(find.byIcon(AppIcons.refresh), findsNothing);
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    expect(find.text('刷新头像'), findsNothing);
    expect(client.calls, 1);
    await _refreshAvatar(tester, avatar);
    await _pumpUntil(tester, () => client.calls == 2 && _networkFrame(tester));
    expect(profile.reads, 1);
    expect(find.text('头像测试用户'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual refresh bypasses successful cache and prevents repeat requests',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const AvatarImage(name: '千河', url: url, size: 88, refreshable: true),
        ),
      );
      await _pumpUntil(tester, () => _networkFrame(tester));
      client.pending = Completer<HttpClientResponse>();
      await _refreshAvatar(tester, find.byType(AvatarImage));
      await _pumpUntil(tester, () => client.calls == 2);
      await tester.longPress(find.byType(AvatarImage));
      expect(find.text('刷新头像'), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(client.calls, 2);
      client.pending!.complete(_Response(200));
      await _pumpUntil(tester, () => _networkFrame(tester));
      await tester.pumpAndSettle();
      expect(client.calls, 2);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _refreshAvatar(WidgetTester tester, Finder avatar) async {
  await tester.longPress(avatar);
  await tester.pumpAndSettle();
  await tester.tap(find.text('刷新头像'));
  await tester.pumpAndSettle();
}

class _AvatarProfile extends FixtureSpace {
  _AvatarProfile(this.avatarUrl);
  final String avatarUrl;
  int reads = 0;
  @override
  Future<UserProfile> profile(String uid, {bool refresh = false}) async {
    reads++;
    return UserProfile(uid: uid, name: '头像测试用户', avatarUrl: avatarUrl);
  }
}
