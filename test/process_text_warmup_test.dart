import 'dart:async';

import 'package:chh_app/core/process_text_warmup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'warms Android text actions once after the first frame and active transition',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final calls = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.processText, (
        call,
      ) async {
        calls.add(call.method);
        return {'share': 'Share'};
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.processText,
          null,
        ),
      );

      final warmup = warmPlatformTextActions();
      expect(calls, isEmpty);

      tester.binding.addPostFrameCallback((_) {
        unawaited(
          navigator.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Next')),
            ),
          ),
        );
      });
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Scaffold()),
      );
      expect(calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, isEmpty);

      await tester.pumpAndSettle();
      await warmup;
      expect(calls, ['ProcessText.queryTextActions']);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(calls, ['ProcessText.queryTextActions']);
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}
