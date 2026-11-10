import 'package:chh_app/design/theme.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/pages/home_page.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'notification tap leaves the covered route and opens fresh messages',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      var messageBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: buildAppTheme(Brightness.light),
          home: HomePage(
            initialiseSession: () async {},
            screenBuilders: {
              AppDestination.feed: (_) => const Scaffold(body: Text('精选内容')),
              AppDestination.messages: (_) {
                messageBuilds++;
                return Scaffold(body: Text('消息内容$messageBuilds'));
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('帖子详情')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('帖子详情'), findsOneWidget);
      messageNotifications.openRequests.value++;
      await tester.pumpAndSettle();
      expect(find.text('帖子详情'), findsNothing);
      expect(find.text('消息内容1'), findsOneWidget);
      final busy = ValueNotifier<bool>(true);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ValueListenableBuilder<bool>(
            valueListenable: busy,
            builder: (_, submitting, _) => PopScope(
              canPop: !submitting,
              child: const Scaffold(body: Text('正在提交')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      messageNotifications.openRequests.value++;
      await tester.pumpAndSettle();
      expect(find.text('正在提交'), findsOneWidget);
      expect(messageBuilds, 1);
      busy.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('正在提交'), findsNothing);
      expect(find.text('消息内容2'), findsOneWidget);
      busy.dispose();
      await tester.pumpWidget(const SizedBox());
      messageNotifications.openRequests.value = 0;
    },
  );
}
