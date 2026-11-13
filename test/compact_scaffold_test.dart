import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/nav_bar.dart';
import 'package:chh_app/widgets/compact_scaffold.dart';
import 'package:chh_app/widgets/expressive_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _bodyKey = ValueKey('compact-body');
const _bottomKey = ValueKey('compact-bottom');
const _footerKey = ValueKey('compact-footer');

Widget _app(Widget home, {double scale = 1}) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: home,
);

void main() {
  testWidgets('body stays below status, toolbar and bottom with keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        const CompactScaffold(
          title: '会话',
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(30),
            child: SizedBox.expand(key: _bottomKey),
          ),
          body: SizedBox.expand(key: _bodyKey),
          bottomNavigationBar: SizedBox(height: 44, key: _footerKey),
        ),
      ),
    );
    final headerBottom = 24 + NavOverlay.barHeight;
    expect(tester.getRect(find.byKey(_bottomKey)).top, headerBottom);
    expect(tester.getRect(find.byKey(_bodyKey)).top, headerBottom + 30);
    expect(tester.getRect(find.byKey(_bodyKey)).bottom, 756);
    expect(MediaQuery.paddingOf(tester.element(find.byKey(_bodyKey))).top, 0);
    expect(
      MediaQuery.paddingOf(tester.element(find.byKey(_bodyKey))).bottom,
      0,
    );
    expect(find.byType(AppBar), findsNothing);

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    expect(tester.getRect(find.byKey(_bodyKey)).top, headerBottom + 30);
    expect(tester.getRect(find.byKey(_bodyKey)).bottom, 520);
    expect(
      MediaQuery.viewInsetsOf(tester.element(find.byKey(_bodyKey))).bottom,
      0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resize opt out preserves body extent when keyboard opens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        const CompactScaffold(
          title: '正文',
          resizeToAvoidBottomInset: false,
          body: SizedBox.expand(key: _bodyKey),
        ),
      ),
    );
    final before = tester.getRect(find.byKey(_bodyKey));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    expect(tester.getRect(find.byKey(_bodyKey)), before);
    expect(tester.takeException(), isNull);
  });

  for (final centered in [false, true]) {
    testWidgets('long title avoids controls at 2x, centerTitle=$centered', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const title = '这是一条很长的私信会话标题';
      await tester.pumpWidget(
        _app(
          CompactScaffold(
            title: title,
            centerTitle: centered,
            actions: [
              ChromeButton(
                icon: AppIcons.more,
                tooltip: '更多',
                onPressed: () {},
              ),
            ],
            body: const SizedBox.expand(),
          ),
          scale: 2,
        ),
      );
      final titleRect = tester.getRect(find.text(title));
      expect(titleRect.width, greaterThan(0));
      expect(titleRect.overlaps(tester.getRect(find.byTooltip('返回'))), isFalse);
      expect(titleRect.overlaps(tester.getRect(find.byTooltip('更多'))), isFalse);
      expect(tester.widget<Text>(find.text(title)).maxLines, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('back returns to prior route and root can hide it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => CompactScaffold(
            title: '根页面',
            showBack: false,
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CompactScaffold(
                    title: '二级页面',
                    body: SizedBox.expand(),
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('返回'), findsNothing);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('根页面'), findsOneWidget);
    expect(find.text('二级页面'), findsNothing);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      scaffold.backgroundColor,
      AppTokens.of(tester.element(find.byType(CompactScaffold))).bg,
    );
  });
}
