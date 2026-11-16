import 'dart:io';

import 'package:chh_app/parser/thread_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sample = File('test_data/thread_synthetic.html').readAsStringSync();
  String sidebar(String link) => sample.replaceFirst(
    '<div class="avatar">',
    '<div class="favatar"><p><em>$link</em></p></div>'
        '<div class="avatar">',
  );
  const link =
      '<a href="home.php?mod=spacecp&amp;ac=usergroup&amp;gid=41">'
      '<font> 能天使 </font></a>';

  test(
    'author sidebar supplies group identity and retains existing fields',
    () {
      final before = parseThread(sample, tid: 900001).posts;
      final after = parseThread(sidebar(link), tid: 900001).posts;
      expect(after.length, before.length);
      final first = after.first;
      expect(first.authorGroupId, 41);
      expect(first.authorGroupName, '能天使');
      expect(first.pid, before.first.pid);
      expect(first.floor, before.first.floor);
      expect(first.author, before.first.author);
      expect(first.authorUid, before.first.authorUid);
      expect(first.avatarUrl, before.first.avatarUrl);
      expect(first.time, before.first.time);
      expect(first.content.length, before.first.content.length);
      expect(first.notes.length, before.first.notes.length);
      expect(first.rating?.summary, before.first.rating?.summary);
      expect(first.comments.length, before.first.comments.length);
      expect(after[1].authorGroupId, isNull);
      expect(after[1].authorGroupName, isNull);
      final copied = first.copyWith(content: first.content);
      expect(copied.authorGroupId, 41);
      expect(copied.authorGroupName, '能天使');
    },
  );

  test('missing link leaves both fields null without guessing from text', () {
    final first = parseThread(sidebar('能天使'), tid: 900001).posts.first;
    expect(first.authorGroupId, isNull);
    expect(first.authorGroupName, isNull);
  });

  test('invalid or missing gid is never inferred from group name', () {
    for (final gid in ['', 'oops', '-1', '0']) {
      final first = parseThread(
        sidebar(link.replaceFirst('gid=41', 'gid=$gid')),
        tid: 900001,
      ).posts.first;
      expect(first.authorGroupId, isNull);
      expect(first.authorGroupName, '能天使');
    }
  });

  test('unlisted gid stays real data for presentation to filter', () {
    final first = parseThread(
      sidebar(link.replaceFirst('gid=41', 'gid=54')),
      tid: 900001,
    ).posts.first;
    expect(first.authorGroupId, 54);
  });

  test('links in body or other sidebar positions are ignored', () {
    final html = sample.replaceFirst(
      '<td id="postmessage_90000101">',
      '<td id="postmessage_90000101">'
          '<div class="favatar"><p><em>$link</em></p></div>',
    );
    expect(parseThread(html, tid: 900001).posts.first.authorGroupId, isNull);
    final wrong = sample.replaceFirst(
      '<div class="avatar">',
      '<div class="favatar"><p>$link</p></div><div class="avatar">',
    );
    expect(parseThread(wrong, tid: 900001).posts.first.authorGroupId, isNull);
  });
}
