import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/forum_threads_page.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/widgets/password_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Forum extends ForumRepository {
  final bool accepted;
  final bool throws;
  bool unlocked = false;
  int loads = 0;
  final passwords = <String>[];

  _Forum({this.accepted = true, this.throws = false})
    : super(ChhClient(fetchers: []));

  @override
  Future<List<ThreadType>> threadTypes(int fid, {bool refresh = false}) async =>
      [];

  @override
  Future<ThreadListPage> threadList(
    int fid, {
    int page = 1,
    int? typeid,
    String? filter,
    String? orderby,
    bool refresh = false,
  }) async {
    loads++;
    if (!unlocked) {
      throw PageMessage(PageMessageKind.forumPassword, '站点密码提示', fid: fid);
    }
    expect(refresh, isTrue);
    return const ThreadListPage(
      threads: [
        ThreadSummary(
          tid: 123,
          title: '已解锁的帖子',
          author: '作者',
          replies: 0,
          views: 1,
        ),
      ],
      page: PageInfo(current: 1, hasNext: false),
    );
  }

  @override
  Future<bool> verifyForumPassword(int fid, String password) async {
    expect(fid, 316);
    passwords.add(password);
    if (throws) throw StateError('offline');
    unlocked = accepted;
    return accepted;
  }
}

Widget _app(Widget child) =>
    MaterialApp(theme: buildAppTheme(Brightness.light), home: child);

Future<void> _phone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Finder get _submit => find.widgetWithText(AppButton, '输入密码').last;

void main() {
  testWidgets(
    'password sheet requests IME, disables empty submit and returns exact input',
    (tester) async {
      await _phone(tester);
      String? submitted;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: AppButton(
                label: '打开',
                onPressed: () async {
                  submitted = await showPasswordSheet(context, title: '输入帖子密码');
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      expect(tester.widget<AppButton>(_submit).onPressed, isNull);
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(field, ' 中文密码 ');
      await tester.pump();
      expect(tester.widget<AppButton>(_submit).onPressed, isNotNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(submitted, ' 中文密码 ');
      expect(find.text('输入帖子密码'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('password sheet cancellation returns null', (tester) async {
    await _phone(tester);
    String? submitted = 'pending';
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: AppButton(
              label: '打开',
              onPressed: () async {
                submitted = await showPasswordSheet(context, title: '输入版块密码');
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(submitted, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final result in ['success', 'wrong', 'error']) {
    testWidgets('forum password $result preserves state or reloads the list', (
      tester,
    ) async {
      await _phone(tester);
      final repository = _Forum(
        accepted: result == 'success',
        throws: result == 'error',
      );
      await tester.pumpWidget(
        _app(ForumThreadsPage(fid: 316, title: '密码版块', repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text('本版块需要密码'), findsOneWidget);
      await tester.tap(find.text('输入密码'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '测试密码');
      await tester.pump();
      await tester.tap(_submit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.passwords, ['测试密码']);
      if (result == 'success') {
        await tester.pumpAndSettle();
        expect(repository.loads, 2);
        expect(find.text('已解锁的帖子'), findsOneWidget);
        expect(find.text('本版块需要密码'), findsNothing);
      } else {
        expect(repository.loads, 1);
        expect(find.text('本版块需要密码'), findsOneWidget);
        expect(
          find.text(result == 'wrong' ? '密码不正确' : '解锁未完成，请重试'),
          findsOneWidget,
        );
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
