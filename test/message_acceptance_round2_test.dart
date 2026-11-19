import 'dart:async';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/widgets/lacquer_tab_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'messages_ui_test.dart' show FakeMessages;

class _DelayedMessages extends FakeMessages {
  final arrival = Completer<Paged<Notice>>();
  @override
  Future<Paged<Notice>> notices({
    NoticeView view = NoticeView.all,
    String? type,
    int page = 1,
    bool refresh = false,
  }) => arrival.future;
  void complete() => arrival.complete(
    Paged(
      items: [
        for (var i = 0; i < 50; i++)
          Notice(
            id: '$i',
            category: 'post',
            actor: '读者$i',
            occurredAtText:
                '${DateTime(2026, 11, 15).subtract(Duration(days: i ~/ 4))}',
            summary: '回复了您的帖子',
            title: '本地标题$i',
          ),
      ],
      page: const PageInfo(current: 1, hasNext: false),
    ),
  );
}

void main() {
  testWidgets('first delayed notice list stays at top on each arrival frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _DelayedMessages();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: MessagesTabPage(repository: repo),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    expect(scroll.offset, 0);
    repo.complete();
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.offset, 0, reason: 'arrival frame $frame');
    }
    expect(find.text('《本地标题0》').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'first notice and PM labels use approved header gap $style $brightness',
        (tester) async {
          final repo = _DelayedMessages()..complete();
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness, style),
              home: MessagesTabPage(repository: repo),
            ),
          );
          await tester.pumpAndSettle();
          for (var section = 0; section < 2; section++) {
            if (section == 1) {
              await tester.tap(find.text('私信').hitTestable().first);
              await tester.pumpAndSettle();
            }
            final scaffold = tester.widget<LacquerTabScaffold>(
              find.byType(LacquerTabScaffold).hitTestable(),
            );
            final header = find.byKey(const ValueKey('tab-shared-header'));
            final headerBottom = tester.getBottomLeft(header).dy;
            final label = find.descendant(
              of: find.byType(LacquerTabScaffold).hitTestable(),
              matching: find.byKey(const ValueKey('message-filter-row')),
            );
            if (style == AppearanceStyle.misty) {
              final text = find
                  .descendant(of: label, matching: find.byType(Text))
                  .first;
              expect(tester.getTopLeft(text).dy - headerBottom, closeTo(20, 1));
            } else {
              final row = find
                  .descendant(of: label, matching: find.byType(Row))
                  .first;
              expect(
                tester.getTopLeft(row).dy - headerBottom - scaffold.seamOverlap,
                greaterThanOrEqualTo(22),
              );
            }
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}
