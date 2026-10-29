import 'dart:async';

import 'package:chh_app/core/app_log.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/search_page.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/ui/editor_touch.dart';
import 'package:chh_app/ui/search_field.dart';
import 'package:chh_app/widgets/expressive_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('chh/editor_touch');
const _fieldKey = ValueKey('guarded-editor');

Widget _field({
  FocusNode? focusNode,
  TextEditingController? controller,
  bool autofocus = false,
  bool userEntry = false,
  bool enabled = true,
}) => EditorTouchGuard(
  focusNode: focusNode,
  notifyOnUserEntry: userEntry,
  enabled: enabled,
  builder: (context, node, onTap) => TextField(
    key: _fieldKey,
    focusNode: node,
    controller: controller,
    autofocus: autofocus,
    readOnly: !enabled,
    onTapAlwaysCalled: true,
    onTap: onTap,
  ),
);

Widget _app(Widget child, {GlobalKey<NavigatorState>? navigatorKey}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(body: child),
    );

void _platformTest(
  String description,
  WidgetTesterCallback body, {
  TargetPlatform platform = TargetPlatform.android,
}) => testWidgets(
  description,
  body,
  variant: TargetPlatformVariant.only(platform),
);

void main() {
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  _platformTest('focused retap still sends one editor touch notification', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_field()));
    await tester.tap(find.byKey(_fieldKey));
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), ['editorTapped']);
    expect(
      tester.widget<TextField>(find.byKey(_fieldKey)).focusNode!.hasFocus,
      isTrue,
    );
    await tester.tap(find.byKey(_fieldKey));
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), ['editorTapped', 'editorTapped']);
    expect(calls.every((call) => call.arguments == null), isTrue);
  });

  _platformTest('notification does not change the draft or selection', (
    tester,
  ) async {
    final node = FocusNode();
    final input = TextEditingController.fromValue(
      const TextEditingValue(
        text: '正在编辑的草稿',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    addTearDown(node.dispose);
    addTearDown(input.dispose);
    await tester.pumpWidget(_app(_field(focusNode: node, controller: input)));
    node.requestFocus();
    await tester.pump();
    final before = input.value;
    tester.widget<TextField>(find.byKey(_fieldKey)).onTap!();
    await tester.pump();
    expect(calls, hasLength(1));
    expect(input.value, before);
  });

  _platformTest(
    'focused callback schedules a frame and coalesces pending taps',
    (tester) async {
      await tester.pumpWidget(_app(_field(autofocus: true)));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      final tap = tester.widget<TextField>(find.byKey(_fieldKey)).onTap!;
      tap();
      tap();
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      expect(calls, hasLength(1));
    },
  );

  _platformTest('focus loss cancels a pending notification', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(_app(_field(focusNode: node, autofocus: true)));
    await tester.pumpAndSettle();
    tester.widget<TextField>(find.byKey(_fieldKey)).onTap!();
    node.unfocus();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  _platformTest(
    'background transition cancels intent without showing on resume',
    (tester) async {
      await tester.pumpWidget(_app(_field(autofocus: true)));
      await tester.pumpAndSettle();
      tester.widget<TextField>(find.byKey(_fieldKey)).onTap!();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    },
  );

  _platformTest('covered route cancels a pending touch notification', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(_field(autofocus: true), navigatorKey: navigator),
    );
    await tester.pumpAndSettle();
    tester.widget<TextField>(find.byKey(_fieldKey)).onTap!();
    navigator.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('其他页面'))),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  _platformTest(
    'dispose cancels a pending notification and preserves external node',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(_app(_field(focusNode: node, autofocus: true)));
      await tester.pumpAndSettle();
      tester.widget<TextField>(find.byKey(_fieldKey)).onTap!();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(calls, isEmpty);
      void listener() {}
      expect(() => node.addListener(listener), returnsNormally);
      node.removeListener(listener);
    },
  );

  _platformTest(
    'focus node replacement cancels old touch and respects ownership',
    (tester) async {
      final external = FocusNode();
      addTearDown(external.dispose);
      final selection = ValueNotifier<FocusNode?>(null);
      addTearDown(selection.dispose);
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<FocusNode?>(
            valueListenable: selection,
            builder: (_, node, _) => _field(focusNode: node, autofocus: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final owned = tester.widget<TextField>(find.byKey(_fieldKey)).focusNode!;
      tester.widget<TextField>(find.byKey(_fieldKey)).onTap!();
      selection.value = external;
      await tester.pump();
      expect(calls, isEmpty);
      expect(() => owned.addListener(() {}), throwsFlutterError);
      selection.value = null;
      await tester.pump();
      final replacement = tester
          .widget<TextField>(find.byKey(_fieldKey))
          .focusNode!;
      void listener() {}
      expect(() => external.addListener(listener), returnsNormally);
      external.removeListener(listener);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => replacement.addListener(() {}), throwsFlutterError);
    },
  );

  _platformTest(
    'non Android tap keeps the standard input path without channel',
    (tester) async {
      await tester.pumpWidget(_app(_field()));
      await tester.tap(find.byKey(_fieldKey));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(calls, isEmpty);
    },
    platform: TargetPlatform.iOS,
  );

  _platformTest('native failure only logs and preserves editable state', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _channel,
          (_) async => throw PlatformException(code: 'probe'),
        );
    final input = TextEditingController(text: '不应记录的草稿正文');
    addTearDown(input.dispose);
    await tester.pumpWidget(_app(_field(controller: input, autofocus: true)));
    await tester.pumpAndSettle();
    final before = input.value;
    tester.widget<TextField>(find.byKey(_fieldKey)).onTap!();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(input.value, before);
    expect(AppLog.instance.entries.last.tag, 'IME');
    expect(AppLog.instance.entries.last.message, isNot(contains(input.text)));
  });

  _platformTest('zero duration user entry notifies after autofocus settles', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_field(autofocus: true, userEntry: true)));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
  });

  _platformTest('search user entry notifies without requiring a second tap', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const SearchPage(autofocus: true)));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
  });

  _platformTest('standalone search autofocus notifies once on entry', (
    tester,
  ) async {
    final input = TextEditingController();
    addTearDown(input.dispose);
    await tester.pumpWidget(
      _app(
        SearchCapsule(
          controller: input,
          hint: '本地搜索',
          onClear: input.clear,
          autofocus: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
  });

  _platformTest('disabled guard consumes entry without replaying on editable', (
    tester,
  ) async {
    final enabled = ValueNotifier(false);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (_, value, _) =>
              _field(autofocus: true, userEntry: true, enabled: value),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.widget<TextField>(find.byKey(_fieldKey)).onTap!();
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    enabled.value = true;
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.byKey(_fieldKey));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
  });

  _platformTest(
    'composer sending cancels old touch and ignores readonly taps',
    (tester) async {
      final response = Completer<PostResult>();
      await tester.pumpWidget(
        _app(
          ExpressiveComposer(
            title: '本地回复',
            modeLabel: '样例',
            hintText: '本地草稿',
            initialText: '草稿内容',
            onSubmit: (_) => response.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      calls.clear();
      final field = find.byKey(const ValueKey('composer-canvas'));
      tester.widget<TextField>(field).onTap!();
      tester
          .widget<AppButton>(find.byKey(const ValueKey('composer-send')))
          .onPressed!();
      await tester.pump();
      expect(tester.widget<TextField>(field).readOnly, isTrue);
      tester.widget<TextField>(field).onTap!();
      await tester.pump();
      expect(calls, isEmpty);
      response.complete(const PostResult(PostResultKind.failed, '本地失败'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).readOnly, isFalse);
      expect(tester.widget<TextField>(field).controller!.text, '草稿内容');
      expect(calls, isEmpty);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
    },
  );

  _platformTest('search clear is an explicit continuation of editing', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const SearchPage(autofocus: true)));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    await tester.enterText(find.byType(TextField), '本地关键词');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  for (final reduced in [false, true]) {
    _platformTest(
      'entry waits for current route or cancels on pop, reduced=$reduced',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          _app(const SizedBox.shrink(), navigatorKey: navigator),
        );
        navigator.currentState!.push<void>(
          PageRouteBuilder(
            transitionDuration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 300),
            pageBuilder: (context, animation, secondaryAnimation) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: Scaffold(body: _field(autofocus: true, userEntry: true)),
            ),
          ),
        );
        await tester.pump();
        if (!reduced) {
          await tester.pump(const Duration(milliseconds: 80));
          expect(calls, isEmpty);
        }
        await tester.pumpAndSettle();
        expect(calls, hasLength(1));
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        calls.clear();
        navigator.currentState!.push<void>(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (_, _, _) =>
                Scaffold(body: _field(autofocus: true, userEntry: true)),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
