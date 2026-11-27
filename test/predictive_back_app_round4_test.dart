import 'package:chh_app/app.dart';
import 'package:chh_app/core/appearance.dart';
import 'package:chh_app/design/motion.dart';
import 'package:chh_app/design/scroll_behavior.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:flutter/physics.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/inline_forum_parser.dart';

class _Cookies extends PlatformCookieManager {
  _Cookies()
    : super.implementation(const PlatformCookieManagerCreationParams());
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async => [];
}

class _Platform extends InAppWebViewPlatform {
  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => _Cookies();
}

class _LocalForum implements ChhFetcher {
  @override
  String get name => 'local-back-test';
  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async =>
      const ChhResponse(200, '<html><div id="wp">本地空列表</div></html>');
  @override
  Future<ChhResponse> postForm(Uri url, Map<String, String> form) =>
      throw StateError('No writes in back tests');
  @override
  Future<ChhResponse> postMultipart(
    Uri url,
    Map<String, String> fields,
    UploadFile file,
  ) => throw StateError('No writes in back tests');
  @override
  Future<void> dispose() async {}
}

Future<Object?> _back(
  WidgetTester tester,
  String method, [
  double progress = 0,
]) async {
  Object? result;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        method == 'startBackGesture' || method == 'updateBackGestureProgress'
            ? {
                'touchOffset': <double>[progress * 390, 400],
                'progress': progress,
                'swipeEdge': 0,
              }
            : null,
      ),
    ),
    (reply) {
      result = const StandardMethodCodec().decodeEnvelope(reply!);
    },
  );
  return result;
}

void main() {
  testWidgets('complete ChhApp follows real platform back messages', (
    tester,
  ) async {
    final platform = InAppWebViewPlatform.instance;
    useInlineForumParser(chhClient);
    final fetchers = List<ChhFetcher>.of(chhClient.fetchers);
    InAppWebViewPlatform.instance = _Platform();
    chhClient.fetchers
      ..clear()
      ..add(_LocalForum());
    addTearDown(() {
      if (platform != null) InAppWebViewPlatform.instance = platform;
      chhClient.fetchers
        ..clear()
        ..addAll(fetchers);
      messageNotifications.dispose();
    });
    setupDependencies();
    appearance.markStyleDotSeen();
    await tester.pumpWidget(const ChhApp());
    await tester.pumpAndSettle();
    expect(
      ScrollConfiguration.of(tester.element(find.byType(HomePage))),
      isA<AppScrollBehavior>(),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    // Includes MaterialApp/WidgetsApp, ThemeReveal, the real root PopScope,
    // LifecycleFlusher and MessageNotifications from setupDependencies. Only
    // cookies and transport are faked; no isolated Navigator/observer harness.
    for (final style in AppearanceStyle.values) {
      for (final mode in [AppearanceMode.light, AppearanceMode.dark]) {
        appearance.setStyle(style);
        appearance.set(mode);
        await tester.pumpAndSettle();
        for (final localPhase in [
          'possible',
          'accepted-before',
          'accepted-after',
        ]) {
          for (final commit in [false, true]) {
            nav.pushNamed('/settings');
            await tester.pumpAndSettle();
            final settings = find.byType(SettingsPage);
            final route = ModalRoute.of(tester.element(settings))!;
            final touch = await tester.startGesture(const Offset(1, 400));
            if (localPhase == 'accepted-before') {
              await touch.moveBy(const Offset(30, 0));
              await touch.moveBy(const Offset(40, 0));
              await tester.pump();
              expect(route.animation!.value, lessThan(1));
            }
            final start = route.animation!.value;
            expect(await _back(tester, 'startBackGesture'), isTrue);
            if (localPhase == 'accepted-after') {
              await touch.moveBy(const Offset(30, 0));
              await touch.moveBy(const Offset(40, 0));
              await tester.pump();
              expect(
                route.animation!.value,
                start,
                reason: 'late local start/update must not move system back',
              );
            }
            // Android sends CANCEL to the Flutter pointer stream when the
            // system takes over. Possible recognizers call onCancel; accepted
            // recognizers call onEnd. Both used to terminate system tracking.
            await touch.cancel();
            for (final p in [.1, .2, .4, .55177593]) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 5)),
              );
              await _back(tester, 'updateBackGestureProgress', p);
              await tester.pump(const Duration(milliseconds: 8));
              expect(route.animation!.value, closeTo(start - p, .00001));
              expect(
                tester.getTopLeft(settings).dx,
                closeTo(800 * (1 - start + p), .01),
              );
              expect(
                tester.getTopLeft(find.byType(HomePage)).dx,
                closeTo(-800 / 3 * (start - p), .01),
              );
              // Moving system gestures keep the next display frame booked.
              expect(tester.binding.transientCallbackCount, 1);
            }
            final released = route.animation!.value;
            await _back(
              tester,
              commit ? 'commitBackGesture' : 'cancelBackGesture',
            );
            await tester.pump();
            expect(route.animation!.value, closeTo(released, .00001));
            if (commit) {
              await tester.pump(const Duration(milliseconds: 10));
              final fromRest = SpringSimulation(
                AppMotion.reveal.description,
                released,
                0,
                0,
              ).x(.01);
              expect(
                route.animation!.value,
                lessThan(fromRest),
                reason: 'release keeps the negative progress velocity',
              );
            }
            await tester.pumpAndSettle();
            expect(settings, commit ? findsNothing : findsOneWidget);
            expect(nav.userGestureInProgress, isFalse);
            expect(tester.binding.transientCallbackCount, 0);
            if (!commit) {
              expect(route.animation!.value, 1);
              // A subsequent commit with no start/progress is ordinary back.
              await _back(tester, 'commitBackGesture');
              await tester.pumpAndSettle();
              expect(settings, findsNothing);
            }
          }
        }
      }
    }
    // An in-route panel may appear after the system has already started.
    nav.pushNamed('/settings');
    await tester.pumpAndSettle();
    final settings = find.byType(SettingsPage);
    final route = ModalRoute.of(tester.element(settings))!;
    expect(await _back(tester, 'startBackGesture'), isTrue);
    await _back(tester, 'updateBackGestureProgress', .4);
    var panelClosed = 0;
    route.addLocalHistoryEntry(
      LocalHistoryEntry(onRemove: () => panelClosed++),
    );
    await tester.pump();
    await _back(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(panelClosed, 1);
    expect(settings, findsOneWidget);
    expect(route.animation!.value, 1);
    expect(nav.userGestureInProgress, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
