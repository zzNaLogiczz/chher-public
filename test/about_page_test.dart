import 'package:chh_app/core/app_info.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/pages/about_page.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chh_app/ui/chrome_button.dart';
import 'package:chh_app/ui/grouped.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/widgets/link_opener.dart';

void main() {
  testWidgets('设置里点关于进入关于页:图标在上,版本号其次,介绍在下', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-about'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
    final logo = find.bySemanticsLabel('Chher 图标');
    final version = find.byKey(const ValueKey('about-version'));
    final intro = find.textContaining('第三方 Android 客户端');
    expect(logo, findsOneWidget);
    expect(tester.widget<Text>(version).data, '版本 ${AppInfo.version}');
    expect(intro, findsOneWidget);
    expect(tester.getTopLeft(logo).dy, lessThan(tester.getTopLeft(version).dy));
    expect(
      tester.getTopLeft(version).dy,
      lessThan(tester.getTopLeft(intro).dy),
    );

    // 检查更新就在版本号右边,同一行
    final link = find.byKey(const ValueKey('update-check-link'));
    expect(
      find.descendant(of: link, matching: find.text('检查更新')),
      findsOneWidget,
    );
    expect(tester.getCenter(link).dy, closeTo(tester.getCenter(version).dy, 2));
    expect(
      tester.getTopLeft(link).dx,
      greaterThan(tester.getTopRight(version).dx),
    );
    expect(find.textContaining('公益项目'), findsOneWidget);
    expect(find.text(feedbackEmail), findsOneWidget);
    expect(find.textContaining('随机生成的安装标识'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsNothing);
  });

  testWidgets('反馈邮件带上版本号;没有邮件应用时复制地址', (tester) async {
    final opened = <Uri>[];
    final original = externalLauncher;
    externalLauncher = (uri) async {
      opened.add(uri);
      return false;
    };
    addTearDown(() => externalLauncher = original);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const AboutPage(),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('about-feedback'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    // 复制剪贴板是异步的,提示在之后几帧出现
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(opened.single.scheme, 'mailto');
    expect(opened.single.path, feedbackEmail);
    expect(
      Uri.decodeComponent(opened.single.query),
      contains('Chher 反馈（${AppInfo.version}）'),
    );
    expect(copied, feedbackEmail);
    expect(find.text('已复制邮箱地址'), findsOneWidget);
  });

  testWidgets('有新版本时底部“我的”和设置行显示红点', (tester) async {
    Future<void> pump(bool dot) => tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: GroupedSection(
            children: [GroupedRow(title: '设置', dot: dot, onTap: () {})],
          ),
          bottomNavigationBar: AppBottomNavigation(
            current: AppDestination.feed,
            onNavigate: (_) {},
            meDot: dot,
          ),
        ),
      ),
    );
    await pump(false);
    await tester.pumpAndSettle();
    expect(find.byKey(DotBadge.surfaceKey), findsNothing);
    await pump(true);
    await tester.pumpAndSettle();
    expect(find.byKey(DotBadge.surfaceKey), findsNWidgets(2));
  });
}
