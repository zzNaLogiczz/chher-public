/// Structural workload guards; widget tests do not measure device frame rate.
library;

import 'dart:ui' as ui;
import 'dart:io';
import 'dart:convert';

import 'package:chh_app/design/theme.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:chh_app/widgets/image_stack_mode_toggle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'image_stack_gallery_test.dart' as fixture;

/// The deck keeps a five-card window (k±2) alive plus a ±10 probe window that
/// resolves 64px ratio probes; every budget below derives from these windows.
const _deckWindow = 5;
const _probeWindow = 21;
int _windowBudget(int count) {
  final probed = count < _probeWindow ? count : _probeWindow;
  final deck = count < _deckWindow ? count : _deckWindow;
  return probed > deck ? probed : deck;
}

class _Workload {
  final factories = <String>[];
  final loads = <String>[];
  final live = <String>{};
  final decodes = <String>[];
  final decodeWidths = <int>[];
  int completedDecodes = 0;
  int decodedBytes = 0;
  int maxLive = 0;
  final liveEvents = <Map<String, Object?>>[];
  void recordLive(String change, String id) {
    // Ratio probes detach from their stream inside async completion
    // callbacks, outside any frame; only in-frame events have a timestamp.
    final phase = SchedulerBinding.instance.schedulerPhase;
    final inFrame = phase != SchedulerPhase.idle &&
        phase != SchedulerPhase.postFrameCallbacks;
    liveEvents.add({
      'change': change,
      'id': id,
      'count': live.length,
      'frameMicros': inFrame
          ? SchedulerBinding.instance.currentFrameTimeStamp.inMicroseconds
          : -1,
      'phase': phase.name,
      'ids': live.toList()..sort(),
    });
  }
}

class _CountedPhoto extends ImageProvider<String> {
  final String id;
  final _Workload workload;
  final ui.Image pixels;
  const _CountedPhoto(this.id, this.workload, this.pixels);

  @override
  Future<String> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(id);

  @override
  ImageStreamCompleter loadImage(String key, ImageDecoderCallback decode) {
    workload.loads.add(id);
    return _CountedCompleter(id, workload, pixels);
  }
}

class _CountedCompleter extends OneFrameImageStreamCompleter {
  final String id;
  final _Workload workload;
  _CountedCompleter(this.id, this.workload, ui.Image pixels)
    : super(SynchronousFuture(ImageInfo(image: pixels.clone())));

  _CountedCompleter.decoded(this.id, this.workload, Future<ImageInfo> image)
    : super(image);

  @override
  void addListener(ImageStreamListener listener) {
    super.addListener(listener);
    if (hasListeners) {
      if (workload.live.add(id)) workload.recordLive('attach', id);
      if (workload.live.length > workload.maxLive) {
        workload.maxLive = workload.live.length;
      }
    }
  }

  @override
  void removeListener(ImageStreamListener listener) {
    super.removeListener(listener);
    if (!hasListeners && workload.live.remove(id)) {
      workload.recordLive('detach', id);
    }
  }
}

class _EncodedPhoto extends ImageProvider<String> {
  final String id;
  final Uint8List bytes;
  final _Workload workload;
  const _EncodedPhoto(this.id, this.bytes, this.workload);
  @override
  Future<String> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(id);
  @override
  ImageStreamCompleter loadImage(String key, ImageDecoderCallback decode) {
    workload.loads.add(id);
    workload.decodes.add(id);
    final result = _decode(decode);
    return _CountedCompleter.decoded(id, workload, result);
  }

  Future<ImageInfo> _decode(ImageDecoderCallback decode) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    try {
      final frame = await codec.getNextFrame();
      workload.decodedBytes += frame.image.width * frame.image.height * 4;
      workload.completedDecodes++;
      return ImageInfo(image: frame.image);
    } finally {
      codec.dispose();
    }
  }
}

final _realReports = <String, Object?>{};
void _recordRealReport(String name, Map<String, Object?> report) {
  _realReports[name] = report;
  const path = String.fromEnvironment('CHH_STACK_BUDGET_REPORT');
  if (path.isNotEmpty) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(_realReports)}\n',
    );
  }
}

Future<_Workload> _mountRealGroup(
  WidgetTester tester,
  int count, {
  bool widthSensitiveKeys = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final payloads = await tester.runAsync(() async {
    final result = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      // Each URL has its own real codec and source dimensions, unlike the cheap
      // thousand-row model fixture which deliberately shares one pixel source.
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(
        Color(0xff000000 | (((i + 1) * 0x13579b) & 0xffffff)),
        BlendMode.src,
      );
      final picture = recorder.endRecording();
      final source = await picture.toImage(
        i.isEven ? 640 : 420,
        i.isEven ? 420 : 840,
      );
      picture.dispose();
      final data = await source.toByteData(format: ui.ImageByteFormat.png);
      source.dispose();
      result.add(data!.buffer.asUint8List());
    }
    return result;
  });
  final workload = _Workload();
  final urls = List.generate(count, (i) => 'real-$count-photo-$i');
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox.expand(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ImageStackGallery(
                key: PageStorageKey('real-runtime-$count'),
                urls: urls,
                gallery: urls,
                galleryStartIndex: 0,
                imageProviderBuilder: (url, width) {
                  workload.factories.add(url);
                  workload.decodeWidths.add(width);
                  return _EncodedPhoto(
                    widthSensitiveKeys ? '$url@$width' : url,
                    payloads![urls.indexOf(url)],
                    workload,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Permit native codecs to finish, then flush continuations in the fake zone.
  // This is a bounded readiness wait, never a frame-time performance assertion.
  for (var turn = 0; turn < 200; turn++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (workload.decodes.isNotEmpty &&
        workload.completedDecodes == workload.decodes.length) {
      break;
    }
  }
  // Ratio probes detach inside async completion callbacks; give those
  // continuations real-loop turns and pumps so steady-state checks see the
  // post-probe window, not the in-flight one.
  for (var turn = 0; turn < 20; turn++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (workload.live.length <= _deckWindow) break;
  }
  await tester.pumpAndSettle();
  expect(workload.completedDecodes, workload.decodes.length);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  return workload;
}

bool _hasCachedPaperShadow(Element image) {
  var foundShadow = false;
  var cached = false;
  image.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        ((widget.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false)) {
      foundShadow = true;
    } else if (foundShadow && widget is RepaintBoundary) {
      cached = true;
      return false;
    } else if (foundShadow && widget is Transform) {
      return false;
    }
    return true;
  });
  return foundShadow && cached;
}

Future<_Workload> _mount(WidgetTester tester, {int count = 1000}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final pixels = (await tester.runAsync(
    () => createTestImage(width: 48, height: 64, cache: false),
  ))!;
  final workload = _Workload();
  final urls = List.generate(count, (i) => 'budget-photo-$i');
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox.expand(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ImageStackGallery(
                key: const PageStorageKey('runtime-budget'),
                urls: urls,
                gallery: urls,
                galleryStartIndex: 0,
                imageProviderBuilder: (url, width) {
                  workload.factories.add(url);
                  workload.decodeWidths.add(width);
                  return _CountedPhoto(url, workload, pixels);
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    pixels.dispose();
  });
  return workload;
}

Finder get _stage => fixture.stackStage;

/// Steady-state structural budget for the reveal-line deck.
int mountedBudget(int n) => n <= 12 ? n * 3 : _deckWindow * 2 + 1;

void _steadyBudget(
  WidgetTester tester,
  _Workload workload,
  int count, {
  bool allowTransientProbes = false,
  int streamsPerUrl = 1,
  bool realCodecs = false,
}) {
  expect(_stage, findsOneWidget);
  // Mounted widget images: photo + ambience per deck card, plus the scrub
  // thumbs (every thumb for small groups, one live thumb for long ones).
  expect(
    find.byType(Image).evaluate().length,
    lessThanOrEqualTo(mountedBudget(count)),
  );
  expect(workload.live, isNotEmpty);
  if (realCodecs) {
    // Real codecs finish their first frame through async continuations the
    // FakeAsync test zone cannot drive; in-flight probe listeners stay
    // attached here, so the guard is the probe window itself.
    expect(
      workload.live.length,
      lessThanOrEqualTo(_windowBudget(count) * streamsPerUrl),
    );
    expect(
      workload.maxLive,
      lessThanOrEqualTo(_windowBudget(count) * streamsPerUrl),
    );
  } else {
    // Test providers answer synchronously, so probe listeners re-enter
    // addListener before the attach is recorded and their detach events are
    // never logged; live stays capped by the probe window regardless.
    expect(
      workload.live.length,
      lessThanOrEqualTo(_windowBudget(count) * streamsPerUrl),
    );
    expect(workload.maxLive, lessThanOrEqualTo(_windowBudget(count)));
  }
}

void main() {
  for (final count in [3, 5, 12, 24]) {
    testWidgets('deck $count photos keeps the windowed cold budget', (
      tester,
    ) async {
      final workload = await _mountRealGroup(tester, count);
      final stageSize = tester.getSize(_stage);
      final cold = <String, Object?>{
        'groupSize': count,
        'renderer': 'in-app reveal-line deck',
        'deckWindow': _deckWindow,
        'probeWindow': _probeWindow,
        'stageWidth': stageSize.width,
        'stageHeight': stageSize.height,
        'devicePixelRatio': tester.view.devicePixelRatio,
        'mediaHeight': MediaQuery.sizeOf(
          tester.element(find.byType(ImageStackGallery)),
        ).height,
        'verticalViewportHeight': tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .viewportDimension,
        'mediaViewInsetsBottom': MediaQuery.viewInsetsOf(
          tester.element(find.byType(ImageStackGallery)),
        ).bottom,
        'providerFactories': workload.factories.length,
        'decodeWidthHints': workload.decodeWidths.toSet().toList(),
        'providerLoads': workload.loads.length,
        'uniqueDecodes': workload.decodes.toSet().length,
        'completedNativeDecodes': workload.completedDecodes,
        'decodedPixelBytes': workload.decodedBytes,
        'byteScope': 'injected PNG codec pixels, not process or GPU RAM',
        'liveImageStreams': workload.live.length,
        'peakUniqueStreams': workload.maxLive,
        'mountedImages': find.byType(Image).evaluate().length,
        'papersWithCachedShadow': find
            .byType(Image)
            .evaluate()
            .where(_hasCachedPaperShadow)
            .length,
      };
      _steadyBudget(tester, workload, count, realCodecs: true);
      expect(
        workload.decodeWidths.every((width) => width > 0 && width <= 2048),
        isTrue,
      );
      final gesture = await tester.startGesture(tester.getCenter(_stage));
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 8));
      final factories = workload.factories.length;
      final decodes = workload.decodes.length;
      for (var n = 0; n < 20; n++) {
        await gesture.moveBy(const Offset(-1, 0));
        await tester.pump(const Duration(milliseconds: 8));
      }
      final report = <String, Object?>{
        ...cold,
        'drag20Ticks': {
          'additionalProviderFactories': workload.factories.length - factories,
          'additionalNativeDecodes': workload.decodes.length - decodes,
        },
      };
      _recordRealReport('$count photos', report);
      // A 20px drag cannot turn a page: the ratio-probe window and the card
      // window both hold, so no new provider resolves and nothing re-decodes.
      // Frame rebuilds re-resolve the same cached keys (one factory call per
      // mounted image per tick at most); the image cache absorbs them.
      expect(cold['uniqueDecodes'], lessThanOrEqualTo(_windowBudget(count)),
          reason: '$report');
      expect(
        workload.factories.length - factories,
        lessThanOrEqualTo(21 * mountedBudget(count)),
        reason: '$report',
      );
      expect(workload.decodes.length - decodes, 0, reason: '$report');
      await gesture.up();
      await tester.pumpAndSettle();
      _steadyBudget(tester, workload, count);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(workload.live, isEmpty);
    });
  }

  testWidgets(
    'mode roundtrip releases the old view and reuses each resolution key',
    (tester) async {
      final workload = await _mountRealGroup(
        tester,
        3,
        widthSensitiveKeys: true,
      );
      _steadyBudget(tester, workload, 3, streamsPerUrl: 3, realCodecs: true);
      final nativeKeys = Set<String>.of(workload.live);
      await tester.tap(find.byType(ImageStackModeToggle));
      for (var turn = 0; turn < 200; turn++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (workload.completedDecodes == workload.decodes.length) break;
      }
      await tester.pumpAndSettle();
      // Expanded list mode is on; the deck's ambience layer detaches.
      expect(
        tester
            .widget<ImageStackModeToggle>(find.byType(ImageStackModeToggle))
            .expanded,
        isTrue,
      );
      expect(workload.live.length, lessThanOrEqualTo(9));
      final expandedKeys = Set<String>.of(workload.live);
      expect(expandedKeys, isNotEmpty);
      for (final previous in nativeKeys.difference(expandedKeys)) {
        expect(workload.live, isNot(contains(previous)));
      }
      await tester.ensureVisible(find.byType(ImageStackModeToggle));
      await tester.tap(find.byType(ImageStackModeToggle));
      await tester.pumpAndSettle();
      expect(_stage, findsOneWidget);
      expect(find.byType(Image).evaluate().length, lessThanOrEqualTo(9));
      expect(workload.live.length, lessThanOrEqualTo(9));
      expect(workload.live.every(nativeKeys.contains), isTrue);
      expect(
        workload.loads.length,
        workload.loads.toSet().length,
        reason:
            'An already decoded provider/resolution key should stay cached during this small roundtrip',
      );
      _recordRealReport('mode roundtrip', {
        'nativeProviderKeys': nativeKeys.toList()..sort(),
        'expandedProviderKeys': expandedKeys.toList()..sort(),
        'restoredProviderKeys': workload.live.toList()..sort(),
        'providerLoads': workload.loads,
        'nativeDecodes': workload.decodes,
        'peakUniqueAcrossModeTransition': workload.maxLive,
        'events': workload.liveEvents,
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(workload.live, isEmpty);
    },
  );

  testWidgets('deck 1000 photos does not resolve the whole model', (
    tester,
  ) async {
    final workload = await _mount(tester);
    _steadyBudget(tester, workload, 1000);
    expect(workload.loads.length, lessThanOrEqualTo(_probeWindow));
    expect(workload.loads, isNotEmpty);
    expect(workload.loads.toSet().length, lessThanOrEqualTo(_probeWindow));
    expect(workload.factories.length, lessThanOrEqualTo(_probeWindow * 4));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(workload.live, isEmpty);
  });

  testWidgets(
    'deck window releases old listeners after ten pages',
    (tester) async {
      final workload = await _mount(tester);
      for (var index = 1; index <= 10; index++) {
        await tester.timedDrag(
          _stage,
          const Offset(-140, 0),
          const Duration(milliseconds: 180),
        );
        await tester.pumpAndSettle();
        if (workload.maxLive > _deckWindow) {
          _recordRealReport('deck window handoff', {
            'page': index,
            'liveAfterSettle': workload.live.toList()..sort(),
            'mountedAfterSettle': find.byType(Image).evaluate().length,
            'maxLive': workload.maxLive,
            'events': workload.liveEvents,
          });
        }
        _steadyBudget(tester, workload, 1000, allowTransientProbes: true);
      // The deck does not loop: offsets clamp at the list ends, so page 1
      // keeps four live slots, not five.
      final expected = <String>{
        for (final offset in const [-2, -1, 0, 1, 2])
          if (index + offset >= 0 && index + offset < 1000)
            'budget-photo-${index + offset}',
      };
      expect(workload.live, expected);
      }
      // Ten pages sweep the probe window from 0..20 forward; each url is
      // resolved once and cached across the sweep.
      expect(workload.loads.toSet().length, lessThanOrEqualTo(_probeWindow + 10));
      expect(workload.loads.length, lessThanOrEqualTo(_probeWindow + 14));
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
}
