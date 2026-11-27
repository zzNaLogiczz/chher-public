import 'package:flutter/widgets.dart';

Future<void> waitForStartupIdle() async {
  final binding = WidgetsBinding.instance;
  do {
    await binding.endOfFrame;
  } while (binding.hasScheduledFrame);
}
