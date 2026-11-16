import 'package:chh_app/core/link_target.dart';
import 'package:chh_app/models/image_stack_group.dart';
import 'package:chh_app/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty content and isolated images remain untouched', () {
    expect(groupPostImages(const []), isEmpty);
    const image = ImageBlock('one');
    final result = groupPostImages(const [image]);
    expect(result.single.block, same(image));
    expect(result.single.imageStack, isNull);
    expect(result.single.blockIndex, 0);
    expect(result.single.galleryIndex, 0);
  });

  test('two adjacent images become one immutable stack', () {
    final result = groupPostImages(const [ImageBlock('a'), ImageBlock('b')]);
    final group = result.single.imageStack!;
    expect(result.single.block, isNull);
    expect(group.urls, ['a', 'b']);
    expect(group.galleryStartIndex, 0);
    expect(group.blockIndex, 0);
    expect(() => group.urls.add('c'), throwsUnsupportedError);
    expect(() => result.clear(), throwsUnsupportedError);
  });

  final boundaries = <ContentBlock>[
    const TextBlock('一段文字'),
    const TextBlock(''),
    const QuoteBlock([]),
    const QuoteBlock([ImageBlock('quote-a'), ImageBlock('quote-b')]),
    SiteLinkBlock(
      ThreadLink(
        Uri.parse('https://www.chiphell.com/thread-1-1-1.html'),
        tid: 1,
      ),
    ),
    BilibiliBlock(
      BilibiliVideo(
        Uri.parse('https://www.bilibili.com/video/BV1234567890'),
        bvid: 'BV1234567890',
      ),
    ),
  ];
  for (final (index, boundary) in boundaries.indexed) {
    test('non-image boundary $index never joins images across it', () {
      final result = groupPostImages([
        const ImageBlock('a'),
        boundary,
        const ImageBlock('b'),
      ]);
      expect(result, hasLength(3));
      expect(result.every((segment) => segment.imageStack == null), isTrue);
      expect(result[1].block, same(boundary));
      expect(result.map((segment) => segment.galleryIndex), [0, 1, 1]);
    });
  }

  test(
    'multiple stacks and isolated images keep narrative and gallery indices',
    () {
      final result = groupPostImages(const [
        TextBlock('开始'),
        ImageBlock('a'),
        ImageBlock('b'),
        ImageBlock('c'),
        TextBlock('说明'),
        ImageBlock('d'),
        TextBlock('测试'),
        ImageBlock('e'),
        ImageBlock('f'),
        TextBlock('结束'),
      ]);
      expect(result.map((segment) => segment.blockIndex), [
        0,
        1,
        4,
        5,
        6,
        7,
        9,
      ]);
      expect(result.map((segment) => segment.galleryIndex), [
        0,
        0,
        3,
        3,
        4,
        4,
        6,
      ]);
      final groups = result
          .map((s) => s.imageStack)
          .whereType<ImageStackGroup>()
          .toList();
      expect(groups.map((g) => g.urls), [
        ['a', 'b', 'c'],
        ['e', 'f'],
      ]);
      expect(groups.map((g) => g.galleryStartIndex), [0, 4]);
      expect((result[3].block! as ImageBlock).url, 'd');
      expect((result.last.block! as TextBlock).text, '结束');
    },
  );

  test(
    'duplicate URLs are retained by position and quoted images are excluded',
    () {
      const quote = QuoteBlock([ImageBlock('quoted'), ImageBlock('quoted')]);
      final result = groupPostImages(const [
        ImageBlock('same'),
        ImageBlock('same'),
        quote,
        ImageBlock('same'),
        ImageBlock('same'),
      ]);
      expect(result[0].imageStack!.urls, ['same', 'same']);
      expect(result[2].imageStack!.urls, ['same', 'same']);
      expect(result[2].imageStack!.galleryStartIndex, 2);
      expect(result[1].block, same(quote));
    },
  );

  test(
    'a thousand adjacent images yield one segment without touching source',
    () {
      final source = List<ContentBlock>.generate(1000, (i) => ImageBlock('$i'));
      final result = groupPostImages(source);
      expect(source, hasLength(1000));
      expect(result, hasLength(1));
      expect(result.single.imageStack!.urls, hasLength(1000));
      source[0] = const ImageBlock('changed');
      expect(result.single.imageStack!.urls.first, '0');
    },
  );

  test('a thousand text blocks remain separate renderable segments', () {
    final source = List<ContentBlock>.generate(1000, (i) => TextBlock('$i'));
    final result = groupPostImages(source);
    expect(result, hasLength(1000));
    expect(result.every((segment) => segment.imageStack == null), isTrue);
    expect(result.last.blockIndex, 999);
    expect(result.last.galleryIndex, 0);
  });

  List<SiteLinkBlock> links(int count) => List.generate(
    count,
    (i) => SiteLinkBlock(classifyLink('thread-${97000 + i}-1-1.html')!),
  );

  test(
    'up to twelve links stay together, longer groups keep row boundaries',
    () {
      final short = groupPostImages(links(12));
      expect(short, hasLength(1));
      expect(short.single.siteLinks, hasLength(12));
      expect(short.single.linksGrouped, isFalse);

      final source = links(13);
      final long = groupPostImages(source);
      expect(long, hasLength(13));
      expect(long.every((segment) => segment.linksGrouped), isTrue);
      expect(long.map((segment) => segment.siteLinks!.single), source);
      expect(long.where((segment) => segment.linkGroupStart), [long.first]);
      expect(long.where((segment) => segment.linkGroupEnd), [long.last]);
      expect(
        long.map((segment) => segment.blockIndex),
        List.generate(13, (i) => i),
      );
      expect(() => long.first.siteLinks!.clear(), throwsUnsupportedError);
    },
  );

  for (final groupImages in [false, true]) {
    test(
      'long link runs retain quote boundaries and gallery indices with groupImages=$groupImages',
      () {
        final first = links(1000);
        final second = links(13);
        const quote = QuoteBlock([ImageBlock('quoted-image')]);
        final source = <ContentBlock>[
          const ImageBlock('before-a'),
          const ImageBlock('before-b'),
          ...first,
          quote,
          ...second,
          const ImageBlock('after-a'),
          const ImageBlock('after-b'),
        ];
        final segments = groupPostImages(source, groupImages: groupImages);
        final rows = segments
            .where((segment) => segment.siteLinks != null)
            .toList();
        expect(rows, hasLength(1013));
        expect(rows.every((segment) => segment.galleryIndex == 2), isTrue);
        expect(
          rows
              .where((segment) => segment.linkGroupStart)
              .map((segment) => segment.blockIndex),
          [2, 1003],
        );
        expect(
          rows
              .where((segment) => segment.linkGroupEnd)
              .map((segment) => segment.blockIndex),
          [1001, 1015],
        );
        expect(
          segments.singleWhere((segment) => segment.block == quote).blockIndex,
          1002,
        );
        expect(segments.last.galleryIndex, groupImages ? 2 : 3);
        expect(segments.last.blockIndex, groupImages ? 1016 : 1017);
        expect(source, hasLength(1018));
      },
    );
  }
}
