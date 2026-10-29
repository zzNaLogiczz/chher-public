/// Tap real fields instead of enterText, which would bypass focus/hit testing.
/// Native IME visibility is checked separately on the connected Android device.
library;

import 'package:chh_app/data/message_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/log_page.dart';
import 'package:chh_app/pages/new_thread_page.dart';
import 'package:chh_app/pages/pm_thread_page.dart';
import 'package:chh_app/pages/search_page.dart';
import 'package:chh_app/widgets/article_reply_sheet.dart';
import 'package:chh_app/widgets/browse_controls.dart';
import 'package:chh_app/widgets/composer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget page) =>
    MaterialApp(theme: buildAppTheme(Brightness.light), home: page);

Future<void> _check(WidgetTester tester, Finder field) async {
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  expect(tester.testTextInput.hasAnyClients, isTrue);
  expect(tester.testTextInput.isVisible, isTrue);
  // Simulate dismissing the IME without removing focus, then tap again.
  tester.testTextInput.hide();
  await tester.pump();
  expect(tester.testTextInput.isVisible, isFalse);
  await tester.tap(field);
  await tester.pumpAndSettle();
  expect(tester.testTextInput.isVisible, isTrue);
  expect(tester.takeException(), isNull);
}

class _Messages extends MessageRepository {
  _Messages() : super(ChhClient(fetchers: []));
  @override
  Future<List<PmMessage>> conversation(
    String viewUrl, {
    bool refresh = true,
  }) async => [];
  @override
  Future<PostResult> reply({
    required String viewUrl,
    required String message,
  }) => throw StateError('Keyboard verification must never submit');
}

void main() {
  for (final name in [
    'search',
    'browse',
    'log',
    'topic title',
    'topic body',
    'private reply',
  ]) {
    testWidgets('$name requests IME on tap and reopens it while focused', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final Widget page;
      switch (name) {
        case 'search':
          page = const SearchPage();
        case 'browse':
          page = Scaffold(
            body: BrowseSearchField(
              controller: controller,
              hint: '搜索版块',
              onClear: controller.clear,
            ),
          );
        case 'log':
          page = const LogPage();
        case 'topic title' || 'topic body':
          page = NewThreadPage(
            fid: 987654,
            forumName: '离线版块',
            loadForm: () async =>
                const PostForm(action: 'unused', formhash: 'fake'),
            onSubmit: (_, _, _) => throw StateError('Must never publish'),
          );
        default:
          page = PmThreadPage(
            repository: _Messages(),
            conversation: const PmConversation(
              id: 'ime-contract',
              peer: '示例用户',
              preview: '',
              timeRaw: '',
              viewUrl:
                  'https://www.chiphell.com/home.php?mod=space&do=pm&subop=view&plid=1',
            ),
          );
      }
      await tester.pumpWidget(_app(page));
      await tester.pumpAndSettle();
      await _check(
        tester,
        find.byType(EditableText).at(name == 'topic body' ? 1 : 0),
      );
    });
  }
  for (final article in [false, true]) {
    testWidgets(
      '${article ? 'article' : 'forum'} modal reply requests IME and reopens it',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => article
                      ? ArticleReplySheet.show(
                          context,
                          onSubmit: (_) => throw StateError('Must never post'),
                        )
                      : ComposerSheet.show(
                          context,
                          onSubmit: (_) => throw StateError('Must never post'),
                        ),
                  child: const Text('编辑'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('编辑'));
        await tester.pumpAndSettle();
        await _check(tester, find.byType(EditableText));
      },
    );
  }
}
