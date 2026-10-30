import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(
  Widget child, {
  double textScale = 1,
  double width = 390,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: buildAppTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 800),
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(body: Center(child: child)),
  ),
);

Color fillOf(WidgetTester tester) =>
    (tester.widget<DecoratedBox>(find.byKey(AppButton.surfaceKey)).decoration
            as BoxDecoration)
        .color!;

void main() {
  testWidgets('primary uses accent fill and onAccent text', (tester) async {
    await tester.pumpWidget(app(AppButton(label: '发布', onPressed: () {})));
    expect(fillOf(tester), AppTokens.light.accent);
    expect(
      tester.widget<Text>(find.text('发布')).style!.color,
      AppTokens.light.onAccent,
    );
    expect(tester.getSize(find.byKey(AppButton.surfaceKey)).height, 50);
  });

  testWidgets('small primary is 34dp tall', (tester) async {
    await tester.pumpWidget(
      app(AppButton(label: '发送', small: true, onPressed: () {})),
    );
    expect(tester.getSize(find.byKey(AppButton.surfaceKey)).height, 34);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'tinted, plain and destructive variants use readable tokens in $brightness',
      (tester) async {
        final tokens = brightness == Brightness.dark
            ? AppTokens.dark
            : AppTokens.light;
        await tester.pumpWidget(
          app(
            Material(
              color: tokens.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    label: '重试',
                    variant: AppButtonVariant.tinted,
                    onPressed: () {},
                  ),
                  AppButton(
                    label: '全部',
                    variant: AppButtonVariant.plain,
                    trailingChevron: true,
                    onPressed: () {},
                  ),
                  AppButton(
                    label: '退出登录',
                    variant: AppButtonVariant.destructive,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            brightness: brightness,
          ),
        );
        expect(
          tester.widget<Text>(find.text('重试')).style!.color,
          tokens.accent,
        );
        expect(
          tester.widget<Text>(find.text('全部')).style!.color,
          tokens.accent,
        );
        expect(find.byIcon(AppIcons.forward), findsOneWidget);
        final label = find.text('退出登录');
        final foreground = tester.widget<Text>(label).style!.color!;
        expect(
          foreground,
          brightness == Brightness.dark ? Radix.red11Dark : Radix.red11Light,
        );
        final material = tester.widget<Material>(
          find.ancestor(of: label, matching: find.byType(Material)).first,
        );
        expect(material.color, tokens.surface);
        final luminances = [
          foreground.computeLuminance(),
          material.color!.computeLuminance(),
        ]..sort();
        expect(
          (luminances.last + .05) / (luminances.first + .05),
          greaterThanOrEqualTo(4.5),
          reason:
              'Destructive text must remain readable on its confirmation surface',
        );
      },
    );
  }

  testWidgets('quiet is unfilled secondary text for cancel and reply', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        AppButton(
          label: '取消',
          variant: AppButtonVariant.quiet,
          onPressed: () {},
        ),
      ),
    );
    final surface =
        tester.widget<DecoratedBox>(find.byKey(AppButton.surfaceKey)).decoration
            as BoxDecoration;
    expect(surface.color, isNull);
    expect(
      tester.widget<Text>(find.text('取消')).style!.color,
      AppTokens.light.text2,
    );
  });

  testWidgets('busy shows a spinner and ignores taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        AppButton(
          label: '发送',
          onPressed: () => taps++,
          state: AppButtonState.busy,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(AppButton), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('success turns green with a check', (tester) async {
    await tester.pumpWidget(
      app(
        AppButton(label: '发送', onPressed: () {}, state: AppButtonState.success),
      ),
    );
    await tester.pumpAndSettle();
    expect(fillOf(tester), AppTokens.light.green);
    expect(find.byIcon(AppIcons.success), findsOneWidget);
  });

  testWidgets('disabled uses fill and tertiary text', (tester) async {
    await tester.pumpWidget(app(const AppButton(label: '发布')));
    expect(fillOf(tester), AppTokens.light.fill);
    expect(
      tester.widget<Text>(find.text('发布')).style!.color,
      AppTokens.light.text3,
    );
  });

  testWidgets('width does not shrink when switching to busy', (tester) async {
    Widget button(AppButtonState state) =>
        app(AppButton(label: '发布主题', onPressed: () {}, state: state));
    await tester.pumpWidget(button(AppButtonState.idle));
    final idleWidth = tester.getSize(find.byKey(AppButton.surfaceKey)).width;
    await tester.pumpWidget(button(AppButtonState.busy));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      tester.getSize(find.byKey(AppButton.surfaceKey)).width,
      greaterThanOrEqualTo(idleWidth),
    );
  });

  testWidgets('long labels at 2x text on 320dp do not overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        AppButton(label: '这是一个很长很长的按钮文字用来测试溢出', onPressed: () {}),
        textScale: 2,
        width: 320,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
