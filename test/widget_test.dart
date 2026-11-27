import 'package:chh_app/update/update_controller.dart';
import 'package:chh_app/widgets/update_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'iOS does not expose the APK updater',
    (tester) async {
      expect(defaultTargetPlatform, TargetPlatform.iOS);
      expect(await appUpdater.checkOnLaunch(), isFalse);
      expect(appUpdater.available, isFalse);
      expect(appUpdater.hasUpdate, isFalse);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: UpdateCheckLink())),
      );
      expect(find.byKey(const ValueKey('update-check-link')), findsNothing);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
