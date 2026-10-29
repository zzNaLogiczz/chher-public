/// Explicit offline captures only: flutter test --dart-define=CHH_THREAD_REVIEW=true test/threaded_review_capture_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chh_app/data/thread_conversation_index.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/pages/thread_review_page.dart';
import 'package:chh_app/widgets/composer_sheet.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:chh_app/ui/picker.dart';
import 'package:chh_app/widgets/thread_comment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _enabled = bool.fromEnvironment('CHH_THREAD_REVIEW', defaultValue: false);
const _fontFamily = 'CHHThreadReviewCJK';
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

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 16));
  expect(tester.takeException(), isNull);
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String state,
) async {
  for (var frame = 0; frame < 420; frame++) {
    if (ready()) {
      expect(tester.takeException(), isNull);
      return;
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  }
  fail('Did not reach UI state: $state');
}

Finder _mainScroll() => find
    .descendant(
      of: find.byType(ThreadDetailPage).first,
      matching: find.byType(Scrollable),
    )
    .first;
Future<void> _reach(
  WidgetTester tester,
  Finder target,
  Finder scrollable,
) async {
  for (var turn = 0; turn < 45; turn++) {
    if (target.hitTestable().evaluate().isNotEmpty) return;
    if (target.evaluate().isNotEmpty) {
      await Scrollable.ensureVisible(
        tester.element(target.first),
        alignment: .35,
      );
      await _settle(tester);
      if (target.hitTestable().evaluate().isNotEmpty) return;
    }
    await tester.drag(scrollable, const Offset(0, -220));
    await _settle(tester);
  }
  fail('Could not reach $target');
}

void main() {
  test(
    'local pages preserve grouping and goto resolves only provided targets',
    () async {
      final data = ThreadReviewData();
      final first = await data.loadPage(1, null, false);
      final second = await data.loadPage(2, null, false);
      final index = ThreadConversationIndex.build(
        tid: ThreadReviewData.tid,
        posts: [...first.posts, ...second.posts],
        sourceComplete: true,
      );
      for (final pid in [99004, 99005, 99010, 99011]) {
        expect(index.rootPidFor(pid), 99003);
      }
      expect(index.rootPidFor(99006), 99006);
      expect(index.rootPidFor(99007), 99007);
      expect(index.rootPidFor(99013), 99012);
      final located = await data.loadGoto(ThreadReviewData.referenceUrl(99010));
      expect(located.page.current, 2);
      expect(located.posts.any((p) => p.pid == 99010), isTrue);
      await expectLater(
        data.loadGoto(
          ThreadReviewData.referenceUrl(ThreadReviewData.missingPid),
        ),
        throwsA(isA<PageMessage>()),
      );
    },
  );

  for (final variant in const [
    (name: '390-light', width: 390.0, dark: false, scale: 1.0),
    (name: '320-dark-large', width: 320.0, dark: true, scale: 1.6),
  ]) {
    testWidgets('inline review ${variant.name}', (tester) async {
      tester.view.physicalSize = Size(variant.width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(_loadFonts);
      final data = ThreadReviewData();
      final boundary = GlobalKey();
      Future<void> capture(String state, {bool settle = true}) async {
        if (settle) await _settle(tester);
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
            final file = File(
              'build/qa/comment-inline/${variant.name}-$state.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ThreadReviewApp(
            initialDark: variant.dark,
            textScale: variant.scale,
            fontFamilyOverride: _fontFamily,
            data: data,
          ),
        ),
      );
      await _until(
        tester,
        () => find.byType(ThreadDetailPage).evaluate().isNotEmpty,
        'reader',
      );
      await _settle(tester);
      final action = find.byKey(const ValueKey('thread-expand-replies-99003'));
      await _reach(tester, action, _mainScroll());
      await Scrollable.ensureVisible(tester.element(action), alignment: .35);
      await capture('01-collapsed');
      await tester.tap(action);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await capture('01b-expanding-80ms', settle: false);
      await _settle(tester);
      final child = find.byWidgetPredicate(
        (w) => w is PostCard && w.post.pid == 99004,
      );
      await _reach(tester, child.first, _mainScroll());
      await capture('02-expanded');
      final recipient = find.text('回复 示例用户B：如果把风扇曲线一并记录下来，之后调整会更容易比较。');
      await _reach(tester, recipient, _mainScroll());
      expect(recipient, findsOneWidget);
      expect(find.text('回复 示例用户A：赞同，也可以把低负载时的风扇转速一起考虑。'), findsNothing);
      await capture('02b-reply-recipient');
      final reply = find.byKey(const ValueKey('comment-reply-99004'));
      await _reach(tester, reply, _mainScroll());
      await tester.tap(reply);
      await _settle(tester);
      expect(find.byType(ComposerSheet), findsOneWidget);
      await capture('03-reply');
      // Close without publishing: this sample also injects a local submitter.
      Navigator.of(tester.element(find.byType(ComposerSheet))).pop();
      await _settle(tester);
      await capture('04-return-inline');
      // 视图切换在评论区标题右侧的分段里;窄屏大字号时降级为选择按钮。
      // 标题在当前视口上方,先回到顶部再往下找
      tester.state<ScrollableState>(_mainScroll()).position.jumpTo(0);
      await _settle(tester);
      // 标题行撑满整宽,中心点落在标题和分段之间的空白里,所以找标题里的文字
      await _reach(
        tester,
        find.descendant(
          of: find.byType(ThreadCommentHeading),
          matching: find.byType(Text),
        ),
        _mainScroll(),
      );
      if (find.text('原楼层').hitTestable().evaluate().isEmpty) {
        await tester.tap(find.byType(PickerButton<ThreadViewMode>));
        await _settle(tester);
      }
      await tester.tap(find.text('原楼层').hitTestable());
      await _settle(tester);
      final rawReply = find.byWidgetPredicate(
        (w) => w is PostCard && w.post.pid == 99004,
      );
      // 原楼层视图从头排列,先回到顶部再逐段找到目标楼层
      tester.state<ScrollableState>(_mainScroll()).position.jumpTo(0);
      await _settle(tester);
      await _reach(tester, rawReply, _mainScroll());
      await capture('05-raw-single-context');
      expect(tester.takeException(), isNull);
    });
  }
}
