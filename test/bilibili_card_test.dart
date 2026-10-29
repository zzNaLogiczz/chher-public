import 'package:chh_app/core/link_target.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/widgets/bilibili_card.dart';
import 'package:chh_app/widgets/link_opener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BilibiliBlock _video(String bvid) => BilibiliBlock(
  bilibiliFromEmbed(
    'https://player.bilibili.com/player.html?bvid=$bvid&autoplay=0',
  )!,
);

/// 替换真实 WebView:按加载顺序记录地址,保留每个播放器最新的就绪和出错回调
class _FakePlayers {
  final urls = <Uri>[];
  final _ready = <Uri, VoidCallback>{};
  final _error = <Uri, VoidCallback>{};

  List<VoidCallback> get ready => [for (final u in urls) _ready[u]!];
  List<VoidCallback> get error => [for (final u in urls) _error[u]!];

  Widget build(
    BuildContext context,
    Uri url,
    VoidCallback onReady,
    VoidCallback onError,
  ) {
    if (!urls.contains(url)) urls.add(url);
    _ready[url] = onReady;
    _error[url] = onError;
    return ColoredBox(
      key: ValueKey('fake-player-$url'),
      color: const Color(0xFF000000),
    );
  }
}

/// 卡片态里唯一的按压控件就是播放钮
final _playButton = find.byType(PressScale);

Widget _app(List<Widget> children) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  // 卡片按 16:9 撑满宽度;收窄列表,两张卡片都在 800×600 的测试窗口里
  home: Scaffold(
    body: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 200),
      children: children,
    ),
  ),
);

void main() {
  late _FakePlayers players;
  late List<Uri> launched;
  late ExternalLauncher previous;

  setUp(() {
    players = _FakePlayers();
    launched = [];
    previous = externalLauncher;
    externalLauncher = (uri) async {
      launched.add(uri);
      return true;
    };
  });
  tearDown(() => externalLauncher = previous);

  BilibiliCard card(String bvid) =>
      BilibiliCard(block: _video(bvid), playerBuilder: players.build);

  testWidgets('先显示卡片，不创建播放器', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app([card('1Tvpb6HEJe')]));
    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^播放视频')), findsOneWidget);
    expect(players.urls, isEmpty);
    semantics.dispose();
  });

  testWidgets('点击后在原位置加载播放器，就绪后去掉转圈', (tester) async {
    await tester.pumpWidget(_app([card('1Tvpb6HEJe')]));
    await tester.tap(_playButton);
    await tester.pump();
    expect(players.urls.single.queryParameters['bvid'], 'BV1Tvpb6HEJe');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    players.ready.single();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.byKey(ValueKey('fake-player-${players.urls.single}')),
      findsOneWidget,
    );
  });

  testWidgets('15 秒没加载完显示失败，可以在浏览器打开视频页', (tester) async {
    await tester.pumpWidget(_app([card('1Tvpb6HEJe')]));
    await tester.tap(_playButton);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法播放'), findsOneWidget);
    await tester.tap(find.text('在浏览器打开'));
    await tester.pump();
    expect(
      launched.single.toString(),
      'https://www.bilibili.com/video/BV1Tvpb6HEJe',
    );
  });

  testWidgets('播放器报错显示失败态', (tester) async {
    await tester.pumpWidget(_app([card('1Tvpb6HEJe')]));
    await tester.tap(_playButton);
    await tester.pump();
    players.error.single();
    await tester.pumpAndSettle();
    expect(find.text('暂时无法播放'), findsOneWidget);
    expect(
      find.byKey(ValueKey('fake-player-${players.urls.single}')),
      findsNothing,
    );
  });

  testWidgets('同一时间只有一个播放器：播放第二个时第一个恢复成卡片', (tester) async {
    await tester.pumpWidget(_app([card('1Tvpb6HEJe'), card('1qJph6gEg3')]));
    await tester.tap(_playButton.first);
    await tester.pump();
    players.ready.first();
    await tester.pumpAndSettle();

    await tester.tap(_playButton);
    await tester.pump();
    expect(
      find.byKey(ValueKey('fake-player-${players.urls.first}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('fake-player-${players.urls.last}')),
      findsOneWidget,
    );
    expect(_playButton, findsOneWidget);
  });

  testWidgets('卡片销毁后不再响应迟到的回调', (tester) async {
    await tester.pumpWidget(_app([card('1Tvpb6HEJe')]));
    await tester.tap(_playButton);
    await tester.pump();
    await tester.pumpWidget(_app(const []));
    players.ready.single();
    await tester.pump(const Duration(seconds: 20));
    expect(tester.takeException(), isNull);
  });

  test('播放器用纹理合成，不拖着整页走 Hybrid Composition', () {
    // Hybrid Composition 下每一帧都要和 Android 主线程同步合成；
    // 视频播放时弹出回复框、键盘，整页动画会明显掉帧
    final settings = bilibiliPlayerSettings();
    expect(settings.useHybridComposition, isFalse);
    expect(settings.mediaPlaybackRequiresUserGesture, isFalse);
    expect(settings.allowsInlineMediaPlayback, isTrue);
  });
}
