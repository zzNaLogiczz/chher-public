/// Explicit offline captures. Never requests source images or posts to CHH.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/icons.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';
import 'package:chh_app/widgets/image_stack_mode_toggle.dart';
import 'package:chh_app/widgets/net_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _enabled = bool.fromEnvironment('CHH_IMAGE_STACK_CAPTURE');
const _font = 'StackCaptureCJK';
const _output = String.fromEnvironment(
  'CHH_IMAGE_STACK_CAPTURE_OUTPUT',
  defaultValue: 'build/qa/image-stack-responsive/final-captures',
);
const _ids = [
  'g1_1',
  'g1_2',
  'g1_3',
  'g1_4',
  'g1_5',
  'single_airflow',
  'g2_1',
  'g2_2',
  'g2_3',
  'g2_4',
  'r1_1',
  'r1_2',
  'r1_3',
  'mixed_landscape',
  'mixed_portrait',
  'extreme_portrait',
];
String _url(String id) => 'https://fixture.invalid/$id.png';
final _images = <String, ui.Image>{};

class _LoadedImage extends ImageProvider<String> {
  final String id;
  final int width;
  const _LoadedImage(this.id, this.width);
  @override
  Future<String> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture('$id-$width');
  @override
  ImageStreamCompleter loadImage(String key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: _images[id]!.clone())),
      );
}

ImageProvider<Object> _provider(String url, int width) =>
    _LoadedImage(Uri.parse(url).pathSegments.last.split('.').first, width);

Future<void> _assets() async {
  final font = [
    if (Platform.environment['CHH_CAPTURE_CJK_FONT'] case final String path)
      path,
    '/System/Library/Fonts/STHeiti Medium.ttc',
    '/System/Library/Fonts/PingFang.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ].map(File.new).firstWhere((f) => f.existsSync());
  final bytes = await font.readAsBytes();
  for (final family in [_font, 'Ahem', 'Roboto']) {
    await (FontLoader(
      family,
    )..addFont(SynchronousFuture(ByteData.sublistView(bytes)))).load();
  }
  final packages =
      (jsonDecode(await File('.dart_tool/package_config.json').readAsString())
              as Map)['packages']
          as List;
  final p = packages.cast<Map>().firstWhere((p) => p['name'] == 'solar_icons');
  final root = File(
    '.dart_tool/package_config.json',
  ).absolute.uri.resolve(p['rootUri'] as String);
  final solar = await File.fromUri(
    Directory.fromUri(root).uri.resolve('fonts/SolarIcons.ttf'),
  ).readAsBytes();
  await (FontLoader(
    'packages/solar_icons/SolarIcons',
  )..addFont(SynchronousFuture(ByteData.sublistView(solar)))).load();
  for (final id in _ids) {
    final image = await decodeImageFromList(
      await File('/tmp/chher-stack-fixtures/$id.png').readAsBytes(),
    );
    _images[id] = image;
    // Populate the production network-provider keys for full-page fixtures.
    for (final width in [
      for (var width = 64; width <= 640; width += 64) width,
    ]) {
      final key = await boundedNetworkImage(
        _url(id),
        width,
      ).obtainKey(ImageConfiguration.empty);
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())),
        ),
      );
      for (final height in [2048]) {
        final boxKey = await boundedNetworkImageBox(
          _url(id),
          width,
          height,
        ).obtainKey(ImageConfiguration.empty);
        PaintingBinding.instance.imageCache.putIfAbsent(
          boxKey,
          () => OneFrameImageStreamCompleter(
            SynchronousFuture(ImageInfo(image: image.clone())),
          ),
        );
      }
    }
  }
}

InlineSpan _span(InlineSpan span) {
  if (span is! TextSpan) return span;
  final style = span.style ?? const TextStyle();
  return TextSpan(
    text: span.text,
    children: span.children?.map(_span).toList(),
    style: style.fontFamily?.contains('Icons') == true
        ? style
        : style.copyWith(fontFamily: _font),
    recognizer: span.recognizer,
    semanticsLabel: span.semanticsLabel,
  );
}

void _typography(RenderObject object) {
  if (object is RenderParagraph) object.text = _span(object.text);
  object.visitChildren(_typography);
}

Widget _screen(String scene) {
  if (scene == 'thread') {
    return ThreadDetailPage(
      tid: 123,
      title: '离线样例：连续图片与文字顺序',
      loadPage: (_, _, _) async => ThreadDetail(
        tid: 123,
        fid: 290,
        title: '离线样例：连续图片与文字顺序',
        posts: [
          Post(
            pid: 1,
            floor: 1,
            author: '示例作者',
            timeRaw: '2026-11-04',
            content: [
              const TextBlock('主楼样例：开箱全景与装机细节。'),
              for (var i = 1; i <= 5; i++) ImageBlock(_url('g1_$i')),
              const TextBlock('这段文字保留在两组图片之间。'),
              ImageBlock(_url('single_airflow')),
              const TextBlock('独立单图之后是第二组细节。'),
              for (var i = 1; i <= 4; i++) ImageBlock(_url('g2_$i')),
            ],
          ),
          Post(
            pid: 2,
            floor: 2,
            author: '回复作者',
            timeRaw: '2026-11-04',
            content: [
              const TextBlock('回复图片同样聚合。'),
              for (var i = 1; i <= 3; i++) ImageBlock(_url('r1_$i')),
            ],
          ),
        ],
        page: const PageInfo(current: 1, hasNext: false),
      ),
    );
  }
  final compact = scene == 'compact';
  final mixed = scene.startsWith('mixed');
  final urls = scene == 'large-group'
      ? [for (var i = 0; i < 1000; i++) _url('g1_${i % 5 + 1}')]
      : scene == 'extreme'
      ? [
          _url('extreme_portrait'),
          _url('mixed_landscape'),
          _url('mixed_portrait'),
        ]
      : mixed
      ? [_url('mixed_landscape'), _url('mixed_portrait'), _url('g1_1')]
      : [
          for (var i = 1; i <= (compact ? 3 : 5); i++)
            _url('${compact ? 'r1' : 'g1'}_$i'),
        ];
  return Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 41 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              ImageStackGallery(
                urls: urls,
                gallery: urls,
                galleryStartIndex: 0,
                compact: compact,
                expanded: scene == 'expanded' ? true : null,
                imageProviderBuilder: _provider,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// Native looping STACK can repeat an index in its five fixed slots. Measure
// the largest painted instance: the selected front card, not a smaller clone.
Finder _pixels(WidgetTester tester, int index) {
  final matches = find.descendant(
    of: find.byKey(ValueKey('image-stack-photo-$index')),
    matching: find.byType(RawImage),
  );
  final elements = matches.evaluate().toList();
  if (elements.length <= 1) return matches;
  final panel = tester.renderObject<RenderBox>(
    find.byKey(const ValueKey('image-stack-stage')),
  );
  var selected = elements.first;
  var area = -1.0;
  for (final element in elements) {
    final render = element.renderObject! as RenderBox;
    final bounds = MatrixUtils.transformRect(
      render.getTransformTo(panel),
      Offset.zero & render.size,
    );
    final candidate = bounds.width * bounds.height;
    if (candidate > area) {
      selected = element;
      area = candidate;
    }
  }
  return find.byElementPredicate((element) => identical(element, selected));
}

Rect _paintedBounds(WidgetTester tester, int index) {
  final image = tester.renderObject<RenderBox>(_pixels(tester, index));
  final panel = tester.renderObject<RenderBox>(
    find.byKey(const ValueKey('image-stack-stage')),
  );
  return MatrixUtils.transformRect(
    image.getTransformTo(panel),
    Offset.zero & image.size,
  );
}

Size _paintedSize(WidgetTester tester, int index) {
  final image = tester.renderObject<RenderBox>(_pixels(tester, index));
  final panel = tester.renderObject<RenderBox>(
    find.byKey(const ValueKey('image-stack-stage')),
  );
  final m = image.getTransformTo(panel).storage;
  return Size(
    image.size.width * math.sqrt(m[0] * m[0] + m[1] * m[1]),
    image.size.height * math.sqrt(m[4] * m[4] + m[5] * m[5]),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native STACK local-photo captures retain shape in light dark and 2x type',
    (tester) async {
      final originalCacheBytes =
          PaintingBinding.instance.imageCache.maximumSizeBytes;
      // Fixture variants share the same ui.Image allocation; cache accounting
      // counts each provider key separately. This is confined to opt-in captures.
      PaintingBinding.instance.imageCache.maximumSizeBytes = 2048 << 20;
      addTearDown(
        () => PaintingBinding.instance.imageCache.maximumSizeBytes =
            originalCacheBytes,
      );
      await tester.runAsync(_assets);
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        for (final image in _images.values) {
          image.dispose();
        }
        _images.clear();
      });
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final manifest = <Map<String, Object>>[];
      for (final config in [
        ('390-light', 390.0, Brightness.light, 1.0, 844.0),
        ('390-dark', 390.0, Brightness.dark, 1.0, 844.0),
        ('320-dark-2x', 320.0, Brightness.dark, 2.0, 844.0),
        ('320-small', 320.0, Brightness.light, 1.0, 568.0),
        ('568-landscape', 568.0, Brightness.dark, 1.0, 320.0),
      ]) {
        tester.view.physicalSize = Size(config.$2, config.$5);
        for (final scene in [
          'opening',
          'compact',
          'large-group',
          'expanded',
          'thread',
          'mixed-0',
          'mixed-1',
          'mixed-2',
          'extreme',
        ]) {
          final boundary = GlobalKey();
          final theme = buildAppTheme(config.$3);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.copyWith(
                  textTheme: theme.textTheme.apply(fontFamily: _font),
                ),
                home: _screen(scene),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(config.$4),
                    disableAnimations: false,
                  ),
                  child: child!,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (scene.startsWith('mixed-')) {
            final selected = int.parse(scene.split('-').last);
            for (var i = 0; i < selected; i++) {
              final stage = find.byKey(const ValueKey('image-stack-stage'));
              await tester.ensureVisible(stage);
              await tester.fling(stage, const Offset(-220, 0), 1000);
              await tester.pumpAndSettle();
            }
            final active = _pixels(tester, selected);
            expect(active, findsOneWidget);
            final size = _paintedSize(tester, selected);
            final source =
                _images[[
                  'mixed_landscape',
                  'mixed_portrait',
                  'g1_1',
                ][selected]]!;
            expect(
              size.width / size.height,
              closeTo(source.width / source.height, .025),
              reason: 'Natural image bounds, without white letterbox',
            );
            final stageFinder = find.byKey(const ValueKey('image-stack-stage'));
            final stageRender = tester.renderObject<RenderBox>(stageFinder);
            final photos = find.descendant(
              of: stageFinder,
              matching: find.byType(RawImage),
            );
            expect(photos.evaluate().length, lessThanOrEqualTo(5));
            for (final element in photos.evaluate()) {
              final raw = element.widget as RawImage;
              expect(raw.image, isNotNull);
              final render = element.renderObject! as RenderBox;
              final m = render.getTransformTo(stageRender).storage;
              final ownWidth =
                  render.size.width * math.sqrt(m[0] * m[0] + m[1] * m[1]);
              final ownHeight =
                  render.size.height * math.sqrt(m[4] * m[4] + m[5] * m[5]);
              expect(
                ownWidth / ownHeight,
                closeTo(raw.image!.width / raw.image!.height, .025),
                reason: 'Each native STACK slot preserves the photograph shape',
              );
            }
          }
          if (scene == 'extreme') {
            final stage = find.byKey(const ValueKey('image-stack-stage'));
            final current = _pixels(tester, 0);
            expect(current, findsOneWidget);
            final bounds = _paintedBounds(tester, 0);
            final size = bounds.size;
            expect(size.width / size.height, closeTo(1 / 20, .001));
            expect(
              tester.getSize(stage).height,
              lessThan(config.$5 - 40),
              reason: 'Even a 1:20 photo fits within one visible panel',
            );
            expect(
              size.height,
              lessThanOrEqualTo(tester.getSize(stage).height),
            );
            expect(bounds.top, greaterThanOrEqualTo(-.5));
            expect(bounds.left, greaterThanOrEqualTo(-.5));
            expect(
              bounds.bottom,
              lessThanOrEqualTo(tester.getSize(stage).height + .5),
            );
            expect(
              bounds.right,
              lessThanOrEqualTo(tester.getSize(stage).width + .5),
            );
          }
          expect(tester.takeException(), isNull, reason: '${config.$1}-$scene');
          expect(
            find.byType(ImageStackModeToggle).evaluate().length,
            find.byType(ImageStackGallery).evaluate().length,
          );
          expect(
            find.descendant(
              of: find.byType(ImageStackGallery),
              matching: find.byType(Text),
            ),
            findsNothing,
          );
          final failedImages = find.descendant(
            of: find.byKey(const ValueKey('image-stack-stage')),
            matching: find.byWidgetPredicate(
              (w) => w is Icon && w.icon == AppIcons.image,
            ),
          );
          expect(
            failedImages,
            findsNothing,
            reason: 'No placeholder/error image in ${config.$1}-$scene',
          );
          for (final stage
              in find.byKey(const ValueKey('image-stack-stage')).evaluate()) {
            final rawImages = tester.widgetList<RawImage>(
              find.descendant(
                of: find.byWidget(stage.widget),
                matching: find.byType(RawImage),
              ),
            );
            expect(
              rawImages,
              isNotEmpty,
              reason: 'Real decoded photos in ${config.$1}-$scene',
            );
            expect(
              rawImages.every((image) => image.image != null),
              isTrue,
              reason: 'No blank image frames in ${config.$1}-$scene',
            );
          }
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          _typography(render);
          await tester.pump();
          final path = '$_output/${config.$1}-$scene.png';
          await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(path);
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
          manifest.add({
            'scene': scene,
            'config': config.$1,
            'path': path,
            'source': 'offline fixture rendering',
          });
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
      await tester.runAsync(() async {
        await File(
          '$_output/manifest.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
      });
    },
    skip: !_enabled,
  );
}
