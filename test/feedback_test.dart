import 'dart:io';

import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/ui/feedback.dart';
import 'package:chh_app/widgets/state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('toast pops in near the top and leaves after 1.6s', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    AppToast.show(ctx, '已发送');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('已发送'), findsOneWidget);
    expect(tester.getTopLeft(find.text('已发送')).dy, lessThan(120));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('已发送'), findsNothing);
  });

  testWidgets('a new toast replaces the previous one', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    AppToast.show(ctx, '第一条');
    await tester.pump(const Duration(milliseconds: 300));
    AppToast.show(ctx, '第二条');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('state view shows an outline icon, message and tinted action', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        StateView(
          icon: AppIcons.warning,
          message: '加载失败',
          actionLabel: '重试',
          onAction: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.warning));
    expect(icon.size, 52);
    expect(icon.color, AppTokens.light.text3);
    final action = tester.widget<AppButton>(find.byType(AppButton));
    expect(action.variant, AppButtonVariant.tinted);
    expect(find.text('加载失败'), findsOneWidget);
  });

  testWidgets('skeleton schedules no frames', (tester) async {
    await tester.pumpWidget(app(const SkeletonList()));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  test('no SnackBar remains in lib', () {
    final offenders = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.dart') &&
          f.readAsStringSync().contains('showSnackBar(')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
