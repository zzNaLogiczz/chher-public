/// Explicit visual run only:
/// flutter test --dart-define=CHH_INTERACTION_REVIEW=true test/interaction_review_capture_test.dart
/// Optional portable CJK font: CHH_CAPTURE_CJK_FONT=/path/to/font.ttf
library;

import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:chh_app/pages/interaction_review_page.dart';
import 'package:chh_app/pages/article_discussion_page.dart';
import 'package:chh_app/pages/search_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/widgets/search_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _enabled = bool.fromEnvironment(
  'CHH_INTERACTION_REVIEW',
  defaultValue: false,
);
const _fontFamily = 'CHHReviewCJK';
bool _fontsLoaded = false;

Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final candidates = <String>[
    if (Platform.environment['CHH_CAPTURE_CJK_FONT'] case final String path)
      path,
    '/System/Library/Fonts/STHeiti Medium.ttc',
    '/System/Library/Fonts/PingFang.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansSC-Regular.ttf',
  ];
  final cjk = candidates
      .map(File.new)
      .where((file) => file.existsSync())
      .firstOrNull;
  if (cjk == null) {
    // 默认测试只跑流程不出图,没有中文字体也照常运行
    if (!_enabled) return;
    throw StateError(
      'Set CHH_CAPTURE_CJK_FONT to a Chinese font before capturing.',
    );
  }
  await (FontLoader(
    _fontFamily,
  )..addFont(cjk.readAsBytes().then(ByteData.sublistView))).load();
  // Controls with an explicit TextStyle but no family use Flutter's default
  // test family. Override that family too, so those labels remain readable.
  await (FontLoader(
    'Ahem',
  )..addFont(cjk.readAsBytes().then(ByteData.sublistView))).load();
  await (FontLoader(
    'Roboto',
  )..addFont(cjk.readAsBytes().then(ByteData.sublistView))).load();

  final configFile = File('.dart_tool/package_config.json');
  final packages =
      (jsonDecode(await configFile.readAsString()) as Map)['packages'] as List;
  Uri packageRoot(String name) {
    final package = packages.cast<Map>().firstWhere((p) => p['name'] == name);
    return Directory.fromUri(
      configFile.absolute.uri.resolve(package['rootUri'] as String),
    ).uri;
  }

  final solar = File.fromUri(
    packageRoot('solar_icons').resolve('fonts/SolarIcons.ttf'),
  );
  await (FontLoader(
    'packages/solar_icons/SolarIcons',
  )..addFont(solar.readAsBytes().then(ByteData.sublistView))).load();

  final material = File.fromUri(
    packageRoot('flutter').resolve(
      '../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ),
  );
  await (FontLoader(
    'MaterialIcons',
  )..addFont(material.readAsBytes().then(ByteData.sublistView))).load();
  {
    final font = File.fromUri(
      packageRoot('cupertino_icons').resolve('assets/CupertinoIcons.ttf'),
    );
    if (font.existsSync()) {
      await (FontLoader(
        'packages/cupertino_icons/CupertinoIcons',
      )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
    }
  }
  _fontsLoaded = true;
}

Future<void> _settle(WidgetTester tester, {int milliseconds = 0}) async {
  if (milliseconds > 0) await tester.pump(Duration(milliseconds: milliseconds));
  await tester.pumpAndSettle(const Duration(milliseconds: 32));
  expect(tester.takeException(), isNull);
}

Future<void> _searchKeyword(WidgetTester tester, String keyword) async {
  final input = find.descendant(
    of: find.byType(SearchPage),
    matching: find.byType(EditableText),
  );
  await tester.enterText(input, keyword);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
}

void main() {
  for (final variant in const [
    (name: '390-light', width: 390.0, dark: false, scale: 1.0),
    (name: '320-dark-large', width: 320.0, dark: true, scale: 1.6),
  ]) {
    testWidgets('offline interaction captures ${variant.name}', (tester) async {
      tester.view.physicalSize = Size(variant.width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      searchSessionHistory.clear();
      addTearDown(searchSessionHistory.clear);
      await tester.runAsync(_loadFonts);
      if (_enabled) expect(_fontsLoaded, isTrue);
      final boundary = GlobalKey();
      final files = <String>[];
      var networkAttempts = 0;
      Future<void> capture(String label) async {
        final path = '/tmp/chh-ui-v7/${variant.name}-$label.png';
        // 默认测试只走流程、核对状态,显式开启时才写图片
        if (_enabled) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final output = File(path);
            await output.parent.create(recursive: true);
            await output.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        files.add(path);
        expect(find.text('交互样板，示例数据'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: InteractionReviewApp(
                initialDark: variant.dark,
                textScale: variant.scale,
                fontFamilyOverride: _fontFamily,
              ),
            ),
          );
          await _settle(tester);
          await capture('00-home');

          await tester.tap(find.byKey(const ValueKey('review-search')));
          await _settle(tester);
          await capture('01-search-ready');
          await _searchKeyword(tester, '装机');
          await _settle(tester, milliseconds: 700);
          await capture('02-search-results');
          await tester.tap(find.textContaining('示例：装机的安静桌面方案').first);
          await _settle(tester);
          expect(find.byType(ThreadDetailPage), findsNothing);
          expect(find.text('结果预览'), findsOneWidget);
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await _settle(tester);
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await _settle(tester);

          await tester.tap(find.byKey(const ValueKey('review-discussion')));
          await _settle(tester, milliseconds: 600);
          await capture('03-discussion');
          await tester.drag(
            find.byKey(const ValueKey('discussion-sheet-grip')),
            const Offset(0, -440),
          );
          await _settle(tester);
          await capture('03b-discussion-full');
          final discussionScrollable = find
              .descendant(
                of: find
                    .descendant(
                      of: find.byType(ArticleDiscussionPage),
                      matching: find.byType(CustomScrollView),
                    )
                    .first,
                matching: find.byType(Scrollable),
              )
              .first;
          final expand = find.text('展开引用');
          await tester.scrollUntilVisible(
            expand,
            180,
            scrollable: discussionScrollable,
          );
          for (
            var n = 0;
            n < 8 && expand.hitTestable().evaluate().isEmpty;
            n++
          ) {
            await tester.drag(discussionScrollable, const Offset(0, -180));
            await _settle(tester);
          }
          await tester.tap(expand.hitTestable());
          await _settle(tester);
          await capture('04-discussion-quote');

          tester
              .state<ScrollableState>(discussionScrollable)
              .position
              .jumpTo(0);
          await _settle(tester);
          // 回复在评论正文之后(与帖子评论同版式),大字号下需先滚到可见
          await tester.scrollUntilVisible(
            find.text('回复').first,
            120,
            scrollable: discussionScrollable,
          );
          await _settle(tester);
          await tester.tap(find.text('回复').hitTestable().first);
          await _settle(tester);
          await tester.enterText(
            find.byType(TextField).last,
            '示例回复：感谢分享，我会先确认进风与走线空间。',
          );
          await _settle(tester);
          await capture('05-article-reply');
          await tester.ensureVisible(find.text('发送').last);
          await tester.tap(find.text('发送').last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('发送中'), findsOneWidget);
          await capture('06-article-sending');
          await tester.pump(const Duration(milliseconds: 1050));
          await tester.pump(const Duration(milliseconds: 235));
          expect(find.text('已发送'), findsOneWidget);
          await capture('06b-article-success');
          await _settle(tester, milliseconds: 600);
          await capture('07-discussion-sent');
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await _settle(tester);

          ScaffoldMessenger.of(
            tester.element(find.byKey(const ValueKey('review-reply'))),
          ).clearSnackBars();
          await _settle(tester);
          await tester.ensureVisible(
            find.byKey(const ValueKey('review-reply')),
          );
          await tester.tap(find.byKey(const ValueKey('review-reply')));
          await _settle(tester);
          await tester.tap(find.byKey(const ValueKey('review-failure')));
          await _settle(tester);
          await tester.tap(
            find.byKey(const ValueKey('review-open-post-reply')),
          );
          await _settle(tester);
          await capture('08-post-reply');
          await tester.ensureVisible(find.text('发送').last);
          await tester.tap(find.text('发送').last);
          await _settle(tester, milliseconds: 1500);
          expect(find.text('示例发送失败，输入内容已保留'), findsOneWidget);
          expect(
            tester
                .widget<TextField>(find.byType(TextField).last)
                .controller!
                .text,
            isNotEmpty,
          );
          await capture('09-post-failure');
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await _settle(tester);
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await _settle(tester);
          await tester.ensureVisible(
            find.byKey(const ValueKey('review-long-list')),
          );
          await tester.tap(find.byKey(const ValueKey('review-long-list')));
          await _settle(tester);
          await tester.ensureVisible(
            find.byKey(const ValueKey('review-search')),
          );
          await tester.tap(find.byKey(const ValueKey('review-search')));
          await _settle(tester);
          await _searchKeyword(tester, '装机');
          await _settle(tester, milliseconds: 700);
          const lastTitle = '示例：装机记录：从想法到完成 20';
          expect(find.textContaining(lastTitle), findsNothing);
          final results = find
              .descendant(
                of: find.byType(SearchPage),
                matching: find.byType(ListView),
              )
              .first;
          for (
            var n = 0;
            n < 12 && find.text('已加载 20 条').evaluate().isEmpty;
            n++
          ) {
            await tester.drag(results, const Offset(0, -600));
            await _settle(tester, milliseconds: 700);
          }
          expect(find.text('已加载 20 条'), findsOneWidget);
          await tester.drag(results, const Offset(0, -3000));
          await _settle(tester);
          await capture('10-search-long-list');
          expect(networkAttempts, 0);
        },
        createHttpClient: (SecurityContext? _) {
          networkAttempts++;
          throw StateError('Interaction review must not access the network');
        },
      );
      // 清单只列出图片路径,未出图时不写,也就不依赖输出目录存在
      if (_enabled) {
        await tester.runAsync(() async {
          await File(
            '/tmp/chh-ui-v7/${variant.name}-manifest.txt',
          ).writeAsString('${files.join('\n')}\n');
        });
      }
    });
  }
}
