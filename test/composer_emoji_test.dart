import 'dart:io';

import 'package:chh_app/data/message_repository.dart';
import 'package:chh_app/data/smiley_store.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/pm_thread_page.dart';
import 'package:chh_app/ui/chat.dart';
import 'package:chh_app/ui/press.dart';
import 'package:chh_app/widgets/composer/composer_tool_strip.dart';
import 'package:chh_app/widgets/composer/emoji_panel.dart';
import 'package:chh_app/widgets/composer/smiley_editing_controller.dart';
import 'package:chh_app/widgets/expressive_composer.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _canvas = ValueKey('composer-canvas');
const _pmInput = ValueKey('pm-input');
const _pmUrl =
    'https://www.chiphell.com/home.php?mod=space&do=pm&subop=view&plid=1';
final _tool = find.byType(ComposerEmojiTool);
final _strip = find.byType(ComposerToolStrip);
final _panel = find.byType(EmojiPanel);
final _smile = find.byWidgetPredicate(
  (widget) => widget is PressHighlight && widget.semanticLabel == ':)',
);

final _catalog = SmileyCatalog.parse(
  File('test/fixtures/common_smilies_var.js').readAsStringSync(),
);

class _MemoryStore extends SmileyStore {
  _MemoryStore({this.failFirst = false, this.cached = false})
    : super(ChhClient(fetchers: []));

  final bool failFirst;
  final bool cached;
  int loads = 0;

  @override
  Future<SmileyCatalog?> readCache() async => cached ? _catalog : null;

  @override
  Future<SmileyCatalog> load() async {
    loads++;
    if (failFirst && loads == 1) throw const FormatException();
    return _catalog;
  }
}

class _PmRepository extends MessageRepository {
  _PmRepository() : super(ChhClient(fetchers: []));
  String? sent;

  @override
  Future<List<PmMessage>> conversation(
    String viewUrl, {
    bool refresh = false,
  }) async => [
    if (sent != null)
      PmMessage(
        author: '您',
        fromSelf: true,
        text: '',
        timeRaw: '',
        pmid: 'new',
        nodes: [InlineSmiley(_catalog.byCode[':)']!.url)],
      ),
  ];

  @override
  Future<PostResult> reply({
    required String viewUrl,
    required String message,
  }) async {
    sent = message;
    return const PostResult(PostResultKind.success, '已发送');
  }
}

Future<void> _open(
  WidgetTester tester,
  _MemoryStore store, {
  String initialText = '',
  ValueChanged<String>? onDraft,
  _PmRepository? pm,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.padding = const FakeViewPadding(bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: pm != null
          ? PmThreadPage(
              smilies: store,
              repository: pm,
              conversation: const PmConversation(
                id: '1',
                peer: '读者甲',
                viewUrl: _pmUrl,
                preview: '',
                timeRaw: '',
              ),
            )
          : Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showExpressiveComposerRoute(
                    context,
                    docked: true,
                    builder: (_) => ExpressiveComposer(
                      title: '写回复',
                      hintText: '回复内容',
                      initialText: initialText,
                      onDraftChanged: onDraft,
                      smilies: store,
                      onSubmit: (_) async =>
                          const PostResult(PostResultKind.success, '已发送'),
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
    ),
  );
  if (pm == null) await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

Future<void> _keyboard(WidgetTester tester, double height) async {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
  tester.view.padding = FakeViewPadding(bottom: height == 0 ? 24 : 0);
  await tester.pump();
}

void main() {
  testWidgets(
    'first open without keyboard metrics reserves 300 dp and loads once',
    (tester) async {
      final store = _MemoryStore();
      await _open(tester, store);
      expect(store.loads, 0);
      await tester.tap(_tool);
      await tester.pumpAndSettle();
      expect(store.loads, 1);
      expect(tester.getSize(_panel).height, 300);
      expect(tester.getRect(_strip).bottom, 844 - 300);
    },
  );

  for (final isPm in [false, true]) {
    testWidgets(
      '${isPm ? 'PM' : 'reply'} keeps the tool strip docked throughout IME handoff',
      (tester) async {
        final store = _MemoryStore();
        await _open(tester, store, pm: isPm ? _PmRepository() : null);
        final canvas = find.byKey(isPm ? _pmInput : _canvas);
        await tester.showKeyboard(canvas);
        await _keyboard(tester, 270);
        await tester.pumpAndSettle();
        final docked = tester.getRect(_strip);
        expect(docked.bottom, 844 - 270);
        expect(tester.getSize(_tool), const Size(44, 44));
        final toolIcon = find.descendant(
          of: _tool,
          matching: find.byIcon(AppIcons.smile),
        );
        final colors = AppTokens.of(tester.element(_tool));
        expect(tester.widget<Icon>(toolIcon).color, colors.text2);

        await tester.tap(_tool);
        await tester.pump();
        expect(tester.widget<ComposerEmojiTool>(_tool).selected, isTrue);
        expect(tester.widget<Icon>(toolIcon).color, colors.accent);
        for (final height in [220.0, 150.0, 40.0, 0.0]) {
          await _keyboard(tester, height);
          expect(tester.getRect(_strip), docked);
        }
        expect(tester.getSize(_panel).height, 270);
        final grid =
            tester
                    .widget<SliverGrid>(find.byType(SliverGrid).first)
                    .gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount;
        expect(grid.crossAxisCount, 8);

        // Tapping the editor and toggling the tool both reopen the keyboard.
        await tester.tap(canvas);
        await tester.pump();
        expect(_panel, findsNothing);
        expect(tester.widget<ComposerEmojiTool>(_tool).selected, isFalse);
        expect(tester.getRect(_strip), docked);
        for (final height in [50.0, 140.0, 270.0]) {
          await _keyboard(tester, height);
          expect(tester.getRect(_strip), docked);
        }
        await tester.tap(_tool);
        await _keyboard(tester, 0);
        await tester.tap(_tool);
        await tester.pump();
        expect(_panel, findsNothing);
        expect(tester.testTextInput.isVisible, isTrue);
        await _keyboard(tester, 270);
        await tester.pumpAndSettle();
        expect(store.loads, 1);
      },
    );
  }

  testWidgets(
    'panel edits the raw draft and backspace removes one smiley or grapheme',
    (tester) async {
      String? draft;
      await _open(
        tester,
        _MemoryStore(),
        initialText: '甲👩‍🚀乙',
        onDraft: (value) => draft = value,
      );
      final canvas = find.byKey(_canvas);
      final controller =
          tester.widget<TextField>(canvas).controller!
              as SmileyEditingController;
      controller.selection = const TextSelection.collapsed(offset: 1);
      await tester.tap(_tool);
      await tester.pumpAndSettle();
      expect(find.text('默认'), findsOneWidget);
      await tester.tap(_smile);
      await tester.pumpAndSettle();
      expect(controller.text, '甲:)👩‍🚀乙');
      expect(draft, controller.text);
      expect(controller.selection.extentOffset, 3);
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final span = editable.buildTextSpan();
      final picture =
          span.children!.whereType<WidgetSpan>().single.child as NetImage;
      expect(picture.url, _catalog.byCode[':)']!.url);
      expect(picture.width, tester.widget<TextField>(canvas).style!.fontSize);
      expect(span.toPlainText().length, controller.text.length);
      final delete = find.byIcon(AppIcons.backspace);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(controller.text, '甲👩‍🚀乙');
      expect(controller.selection.extentOffset, 1);
      controller.selection = TextSelection.collapsed(offset: '甲👩‍🚀'.length);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(controller.text, '甲乙');
      expect(draft, '甲乙');
    },
  );

  testWidgets(
    'cached draft renders without fetching and IME backspace is atomic',
    (tester) async {
      final store = _MemoryStore(cached: true);
      await _open(tester, store, initialText: '甲:loveliness:乙');
      final field = tester.widget<TextField>(find.byKey(_canvas));
      final controller = field.controller!;
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      expect(controller.text, '甲:loveliness:乙');
      expect(
        editable.buildTextSpan().children!.whereType<WidgetSpan>(),
        hasLength(1),
      );
      expect(store.loads, 0);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '甲:loveliness乙',
          selection: TextSelection.collapsed(offset: 12),
        ),
      );
      await tester.pump();
      expect(controller.text, '甲乙');
      expect(controller.selection.extentOffset, 1);
    },
  );

  testWidgets('load failure leaves panel retryable', (tester) async {
    final store = _MemoryStore(failFirst: true);
    tester.view.viewInsets = const FakeViewPadding(bottom: 270);
    await _open(tester, store);
    await tester.tap(_tool);
    await _keyboard(tester, 0);
    await tester.pumpAndSettle();
    final retry = find.text('表情加载失败，轻点重试');
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(store.loads, 2);
    expect(_smile, findsOneWidget);
  });

  testWidgets(
    'PM replaces its local smiley echo with the server image-only message',
    (tester) async {
      final pm = _PmRepository();
      await _open(tester, _MemoryStore(), pm: pm);
      await tester.tap(_tool);
      await tester.pumpAndSettle();
      await tester.tap(_smile);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pm-send')));
      await tester.pumpAndSettle();
      expect(pm.sent, ':)');
      final bubble = find.byType(ChatBubble);
      expect(bubble, findsOneWidget);
      expect(tester.widget<ChatBubble>(bubble).text, ':)');
      expect(
        find.descendant(of: bubble, matching: find.byType(NetImage)),
        findsOneWidget,
      );
    },
  );
}
