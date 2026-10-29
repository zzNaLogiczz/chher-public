import 'package:chh_app/design/theme.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/credit_log_page.dart';
import 'package:chh_app/pages/favorites_page.dart';
import 'package:chh_app/pages/medals_page.dart';
import 'package:chh_app/pages/my_threads_page.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/pages/user_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/space_fixtures.dart';

Widget accountApp(Widget page) => MaterialApp(
  theme: buildAppTheme(Brightness.dark),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(2)),
    child: child!,
  ),
  home: page,
);

void main() {
  testWidgets('all account read surfaces fit 320dp and double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FixtureSpace();
    for (final page in [
      FavoritesPage(repository: repo),
      MyThreadsPage(repository: repo),
      UserPage(uid: '42', repository: repo),
      SettingsPage(repository: repo),
      CreditLogPage(repository: repo),
      MedalsPage(repository: repo),
    ]) {
      await tester.pumpWidget(accountApp(page));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets('changing favorites requests the real selected kind once', (
    tester,
  ) async {
    final repo = FixtureSpace();
    await tester.pumpWidget(accountApp(FavoritesPage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文章'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文章'));
    await tester.pumpAndSettle();
    expect(repo.favoriteRequests, [FavoriteType.all, FavoriteType.article]);
  });
  testWidgets('medal details remain readable and dismissible with large text', (
    tester,
  ) async {
    final repo = FixtureSpace();
    await tester.pumpWidget(accountApp(MedalsPage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('社区分享纪念勋章'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
  });
}
