import 'dart:convert';
import 'dart:io';

import 'package:chh_app/data/history_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chh-history-');
    file = File('${directory.path}/history-v1.json');
  });

  tearDown(() => directory.delete(recursive: true));

  HistoryIndex open(File? storage) {
    final index = HistoryIndex(storage);
    addTearDown(index.dispose);
    return index;
  }

  void recordThread(HistoryIndex index, int id, {DateTime? at}) {
    index.record(
      type: HistoryType.thread,
      id: id,
      title: '主题 $id',
      fid: 22,
      forumName: '电脑讨论',
      author: '楼主',
      at: at,
    );
  }

  test(
    'same type and ID deduplicate and a revisit updates the top entry',
    () async {
      final index = open(null);
      final latest = DateTime(2026, 11, 25, 9);
      recordThread(index, 42, at: DateTime(2026, 11, 24));
      index.record(
        type: HistoryType.article,
        id: 42,
        title: '文章',
        author: '作者',
        column: '评测',
        at: latest,
      );
      expect(index.all.map((e) => e.key), ['article:42', 'thread:42']);
      recordThread(index, 42, at: latest);
      expect(index.all.map((e) => e.key), ['thread:42', 'article:42']);
      expect(index.all.first.at, latest);

      await index.attach(file);
      await index.flush();
      final reopened = open(file);
      await reopened.load();
      expect(reopened.all.map((e) => e.key), ['thread:42', 'article:42']);
      final thread = reopened.all.first;
      expect(thread.title, '主题 42');
      expect(thread.type, HistoryType.thread);
      expect(thread.fid, 22);
      expect(thread.forumName, '电脑讨论');
      expect(thread.author, '楼主');
      expect(thread.at, latest);
      final article = reopened.all.last;
      expect(article.type, HistoryType.article);
      expect(article.column, '评测');
      expect(article.fid, isNull);
      expect(article.author, '作者');
    },
  );

  test('keeps 1000 entries and evicts the oldest visit', () async {
    final index = open(file);
    for (var tid = 1; tid <= 1000; tid++) {
      recordThread(index, tid);
    }
    recordThread(index, 1);
    recordThread(index, 1001);
    expect(index.all, hasLength(1000));
    expect(index.all.map((e) => e.id), isNot(contains(2)));
    expect(index.all.take(2).map((e) => e.id), [1001, 1]);
    await index.flush();
    final reopened = open(file);
    await reopened.load();
    expect(reopened.all, hasLength(1000));
    expect(reopened.all.last.id, 3);
  });

  test(
    'writes two seconds after the last visit and coalesces visits',
    () async {
      final index = open(file);
      expect(HistoryIndex.writeDelay, const Duration(seconds: 2));
      recordThread(index, 1);
      await Future<void>.delayed(const Duration(seconds: 1));
      recordThread(index, 2);
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      expect(file.existsSync(), isFalse);

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!file.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final stored = jsonDecode(await file.readAsString())['entries'] as Map;
      expect(stored.keys, ['thread:1', 'thread:2']);
    },
  );

  test('delete and clear can restore entries before flush', () async {
    final index = open(file);
    recordThread(index, 1);
    recordThread(index, 2);
    final undoRemove = await index.remove('thread:1');
    expect(index.all.map((e) => e.id), [2]);
    undoRemove!();
    expect(index.all.map((e) => e.id), [2, 1]);

    final undoClear = await index.clear();
    expect(index.all, isEmpty);
    recordThread(index, 1, at: DateTime(2026, 11, 25));
    undoClear!();
    expect(index.all.map((e) => e.id), [1, 2]);
    expect(index.all.first.at, DateTime(2026, 11, 25));
    await index.flush();
    final reopened = open(file);
    await reopened.load();
    expect(reopened.all.map((e) => e.id), [1, 2]);
  });
}
