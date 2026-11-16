import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all portrait frames are centered narrow papers with a 480 cap', () {
    final frame = imageStackFrame([.5, .8], 420);
    expect(frame.width, closeTo(386.4, .001));
    expect(frame.height, 480);
    final narrow = imageStackFrame([.5, .8], 320);
    expect(narrow.width, 320);
    expect(narrow.height, 397);
  });
  test('mixed frames use the median with 200 and 480 limits', () {
    expect(imageStackFrame([.5, 1, 2], 350), const Size(350, 350));
    expect(imageStackFrame([1, 3], 350), const Size(350, 200));
    expect(imageStackFrame([.5, .7, 2], 350), const Size(350, 480));
  });
  test('long screenshots contribute .5 without stretching the frame', () {
    expect(imageStackFrame([.05, .1], 350), const Size(246, 480));
    expect(imageStackFrame([.05, 1], 350), const Size(350, 350 / .75));
  });
  test('reply frames use 300 and 150 caps and a 5 paper edge', () {
    expect(imageStackFrame([.5, .8], 350, compact: true), const Size(242, 300));
    expect(
      imageStackFrame([1, 2], 350, compact: true),
      const Size(350, 350 / 1.5),
    );
    expect(imageStackFrame([3, 4], 350, compact: true), const Size(350, 150));
  });
  test('release distance and velocity thresholds are strict and bounded', () {
    expect(imageStackReleaseTarget(2, 2.3, 0, 5), 2);
    expect(imageStackReleaseTarget(2, 2.301, 0, 5), 3);
    expect(imageStackReleaseTarget(2, 1.699, 0, 5), 1);
    expect(imageStackReleaseTarget(2, 2.01, -450, 5), 2);
    expect(imageStackReleaseTarget(2, 2.01, -451, 5), 3);
    expect(imageStackReleaseTarget(2, 2.01, 451, 5), 1);
    expect(imageStackReleaseTarget(0, -.8, 900, 5), 0);
    expect(imageStackReleaseTarget(4, 4.8, -900, 5), 4);
  });
}
