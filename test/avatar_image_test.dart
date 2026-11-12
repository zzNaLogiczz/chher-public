import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chh_app/data/image_disk_cache.dart';
import 'package:chh_app/design/brand.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/user_page.dart';
import 'package:chh_app/widgets/avatar_image.dart';
import 'package:chh_app/widgets/cached_net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/space_fixtures.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _Client extends Fake implements HttpClient {
  int calls = 0;
  int status = 200;
  Completer<HttpClientResponse>? pending;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    calls++;
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
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

bool _networkFrame(WidgetTester tester) => tester
    .widgetList<RawImage>(find.byType(RawImage))
    .any((image) => image.image?.width == 1);

Finder get _logo => find.byWidgetPredicate((w) {
  if (w is! Image) return false;
  final provider = w.image is ResizeImage
      ? (w.image as ResizeImage).imageProvider
      : w.image;
  return provider is AssetImage && provider.assetName == appLogoAsset;
});

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

  testWidgets('missing avatar uses the chher logo without a network request', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const AvatarImage(size: 44)));
    await tester.pumpAndSettle();
    expect(_logo, findsOneWidget);
    expect(find.byIcon(AppIcons.image), findsNothing);
    expect(client.calls, 0);
  });

  testWidgets('failed avatar shows logo, manual retry succeeds and is cached', (
    tester,
  ) async {
    client.status = 404;
    await tester.pumpWidget(
      _app(const AvatarImage(url: url, size: 88, refreshable: true)),
    );
    await _pumpUntil(
      tester,
      () => client.calls == 1 && _logo.evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(_logo, findsOneWidget);
    expect(await tester.runAsync(() => imageDiskCache.read(url)), isNull);
    expect(find.byIcon(AppIcons.image), findsNothing);
    client.status = 200;
    await tester.tap(find.byTooltip('刷新头像'));
    await _pumpUntil(tester, () => client.calls == 2 && _networkFrame(tester));
    await tester.pumpAndSettle();
    expect(_logo, findsNothing);
    expect(await tester.runAsync(() => imageDiskCache.read(url)), isNotNull);
    await tester.pumpWidget(_app(const SizedBox()));
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.pumpWidget(_app(const AvatarImage(url: url, size: 44)));
    await _pumpUntil(tester, () => _networkFrame(tester));
    expect(client.calls, 2, reason: 'Re-entry uses successful disk cache');
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed manual refresh keeps logo and no disk entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const AvatarImage(url: url, size: 88, refreshable: true)),
    );
    await _pumpUntil(tester, () => _networkFrame(tester));
    client.status = 500;
    await tester.tap(find.byTooltip('刷新头像'));
    await _pumpUntil(
      tester,
      () => find.text('头像加载失败，请重试').evaluate().isNotEmpty,
    );
    expect(_logo, findsOneWidget);
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
    final refresh = find.descendant(of: card, matching: find.byTooltip('刷新头像'));
    expect(refresh, findsOneWidget);
    await tester.tap(refresh);
    await _pumpUntil(tester, () => client.calls == 2 && _networkFrame(tester));
    expect(profile.reads, 1);
    expect(find.text('头像测试用户'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual refresh bypasses successful cache and prevents repeat requests',
    (tester) async {
      await tester.pumpWidget(
        _app(const AvatarImage(url: url, size: 88, refreshable: true)),
      );
      await _pumpUntil(tester, () => _networkFrame(tester));
      client.pending = Completer<HttpClientResponse>();
      await tester.tap(find.byTooltip('刷新头像'));
      await _pumpUntil(tester, () => client.calls == 2);
      await tester.tap(find.byTooltip('刷新头像'));
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
