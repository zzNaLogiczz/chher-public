import 'dart:io';
import 'dart:typed_data';

import 'package:chh_app/data/image_disk_cache.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/space_fixtures.dart';

void main() {
  late Directory dir;
  late ImageDiskCache original;

  setUp(() {
    original = imageDiskCache;
    dir = Directory.systemTemp.createTempSync('settings_cache_test_');
  });
  tearDown(() {
    imageDiskCache = original;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  // 缓存走真实文件 IO,而页面在 fake 时钟里:交替放行真实 IO 与泵帧
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  // 用全新实例重新扫目录,得到磁盘上的真实字节数,且不卡在页面 fake 时钟里的队列上
  Future<int?> diskBytes(WidgetTester tester) =>
      tester.runAsync(() => ImageDiskCache(dir).totalBytes());

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: SettingsPage(repository: FixtureSpace()),
      ),
    );
    // totalBytes 走真实文件 IO,需放到真实异步里等它算完
    await settleIo(tester);
  }

  testWidgets('图片缓存行显示大小,确认后清除', (tester) async {
    final cache = ImageDiskCache(dir);
    imageDiskCache = cache;
    await tester.runAsync(
      () => cache.write('https://static.chiphell.com/a.jpg', Uint8List(1536)),
    );

    await pumpSettings(tester);
    final row = find.text('图片缓存');
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('1.5 KB'), findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('清除'));
    await settleIo(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(await diskBytes(tester), 0);
    expect(find.text('0 B'), findsOneWidget);
    expect(find.text('1.5 KB'), findsNothing);
  });

  testWidgets('取消不清除缓存', (tester) async {
    final cache = ImageDiskCache(dir);
    imageDiskCache = cache;
    await tester.runAsync(
      () => cache.write('https://static.chiphell.com/a.jpg', Uint8List(1536)),
    );

    await pumpSettings(tester);
    await tester.scrollUntilVisible(
      find.text('图片缓存'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('图片缓存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(await diskBytes(tester), 1536);
    expect(find.text('1.5 KB'), findsOneWidget);
  });

  testWidgets('大小算完之前页面照常出现,占位后再更新', (tester) async {
    final cache = ImageDiskCache(dir);
    imageDiskCache = cache;
    await tester.runAsync(
      () => cache.write('https://static.chiphell.com/a.jpg', Uint8List(2048)),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: SettingsPage(repository: FixtureSpace()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('图片缓存'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    // 真实 IO 尚未完成:页面与行已在,值还是占位
    expect(find.text('2.0 KB'), findsNothing);
    expect(find.text('计算中'), findsOneWidget);

    await settleIo(tester);
    expect(find.text('2.0 KB'), findsOneWidget);
  });
}
