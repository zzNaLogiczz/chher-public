import 'package:chh_app/widgets/link_opener.dart';
import 'package:chh_app/core/link_target.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/widgets/rich_content_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildAppTheme(brightness),
      home: Scaffold(body: child),
    );

TextBlock _block(String url) {
  final target = classifyLink(url)!;
  return TextBlock(
    '详见 $url 原文',
    nodes: [
      const InlineText('详见 '),
      InlineLink(url, target),
      const InlineText(' 原文'),
    ],
  );
}

TextSpan? _linkSpan(WidgetTester tester, String text) {
  TextSpan? found;
  final rich = tester.widget<Text>(find.byType(Text).first).textSpan!;
  rich.visitChildren((span) {
    if (span is TextSpan && span.text == text) found = span;
    return found == null;
  });
  return found;
}

void main() {
  late List<Uri> launched;
  late ExternalLauncher previous;

  setUp(() {
    launched = [];
    previous = externalLauncher;
    externalLauncher = (uri) async {
      launched.add(uri);
      return true;
    };
  });
  tearDown(() => externalLauncher = previous);

  testWidgets('站外链接用强调色，点击交给系统浏览器', (tester) async {
    const url = 'https://www.ithome.com/0/1.htm';
    await tester.pumpWidget(_app(RichContentText(block: _block(url))));
    final span = _linkSpan(tester, url)!;
    expect(span.style!.color, AppTokens.light.accent);
    (span.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    expect(launched, [Uri.parse(url)]);
    expect(find.byIcon(AppIcons.externalLink), findsOneWidget);
  });

  testWidgets('浏览器打不开时提示', (tester) async {
    externalLauncher = (_) async => false;
    const url = 'https://www.ithome.com/0/1.htm';
    await tester.pumpWidget(_app(RichContentText(block: _block(url))));
    (_linkSpan(tester, url)!.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    expect(find.text('无法打开链接'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('深色主题下链接用深色的强调色', (tester) async {
    const url = 'https://www.ithome.com/0/1.htm';
    await tester.pumpWidget(
      _app(RichContentText(block: _block(url)), brightness: Brightness.dark),
    );
    expect(_linkSpan(tester, url)!.style!.color, AppTokens.dark.accent);
  });

  testWidgets('重建时释放旧的点击识别器，不报错', (tester) async {
    const url = 'https://www.ithome.com/0/1.htm';
    await tester.pumpWidget(_app(RichContentText(block: _block(url))));
    await tester.pumpWidget(_app(RichContentText(block: _block(url))));
    await tester.pumpWidget(_app(const SizedBox()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有链接和表情的段落仍可选中复制', (tester) async {
    await tester.pumpWidget(
      _app(const RichContentText(block: TextBlock('纯文字'))),
    );
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
