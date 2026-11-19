import 'dart:io';

import 'package:chh_app/core/display_time.dart';
import 'package:chh_app/design/content_element_tokens.dart';
import 'package:chh_app/design/reading.dart';
import 'package:chh_app/core/reading_prefs.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/parser/post_note_parser.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:chh_app/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final posts = parseThread(
    File('test_data/reply_supplement_synthetic.html').readAsStringSync(),
    tid: 9800,
  ).posts;
  testWidgets('light notes keep body, paragraph and consecutive note spacing', (
    tester,
  ) async {
    const post = Post(
      pid: 9910,
      floor: 1,
      author: '合成作者',
      timeRaw: '',
      content: [TextBlock('主楼正文')],
      notes: [
        PostNote(
          PostNoteKind.supplement,
          '补充内容 (2026-11-15 11:30):\n\n第一段\n \n\n第二段\n\n',
        ),
        PostNote(PostNoteKind.supplement, '补充内容 (2026-11-15 11:31): 下一条补充'),
      ],
    );
    final prefs = ReadingPrefsController(directory: () async => null);
    addTearDown(prefs.dispose);
    for (final layout in ReadingLayout.values) {
      await prefs.set(ReadingPrefs(layout: layout));
      for (final split in [false, true]) {
        await tester.pumpWidget(
          ReadingScope(
            controller: prefs,
            child: MaterialApp(
              theme: buildAppTheme(Brightness.light),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: split
                      ? const Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PostCard.header(post: post, isOpening: true),
                            PostCard.block(
                              post: post,
                              isOpening: true,
                              contentBlock: TextBlock('主楼正文'),
                            ),
                            PostCard.footer(post: post, isOpening: true),
                          ],
                        )
                      : const PostCard(post: post, isOpening: true),
                ),
              ),
            ),
          ),
        );
        final headings = find.text('楼主补充');
        expect(headings, findsNWidgets(2));
        expect(
          tester.getTopLeft(headings.first).dy -
              tester.getBottomLeft(find.text('主楼正文')).dy,
          closeTo(24, .1),
        );
        expect(
          tester.getTopLeft(find.text('第二段')).dy -
              tester.getBottomLeft(find.text('第一段')).dy,
          closeTo(14, .1),
        );
        expect(
          tester.getTopLeft(headings.last).dy -
              tester.getBottomLeft(find.text('第二段')).dy,
          closeTo(18, .1),
        );
        expect(
          tester.getTopLeft(find.text('第一段')).dx,
          tester.getTopLeft(find.text('主楼正文')).dx,
        );
        expect(find.text('展开'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
  });

  for (final style in AppearanceStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'reply supplements use light notes and preserve role in $style $brightness',
        (tester) async {
          for (final scenario in [
            (post: posts[0], opening: true, author: false, footer: false),
            (post: posts[1], opening: false, author: false, footer: false),
            (post: posts[2], opening: false, author: false, footer: true),
            (post: posts[3], opening: false, author: true, footer: true),
          ]) {
            final theme = buildAppTheme(brightness, style);
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: scenario.footer
                        ? PostCard.footer(
                            post: scenario.post,
                            isOpening: scenario.opening,
                            isAuthor: scenario.author,
                            commentStyle: true,
                          )
                        : PostCard(
                            post: scenario.post,
                            isOpening: scenario.opening,
                            isAuthor: scenario.author,
                            commentStyle: true,
                          ),
                  ),
                ),
              ),
            );
            final title = scenario.opening ? '楼主补充' : '补充';
            expect(find.text(title), findsNWidgets(scenario.post.notes.length));
            expect(find.text(scenario.opening ? '补充' : '楼主补充'), findsNothing);
            for (final note in scenario.post.notes) {
              final supplement = parseSupplement(note.text)!;
              expect(
                find.text(formatDisplayTime(raw: supplement.timeRaw)),
                findsOneWidget,
              );
              final body = find.text(supplement.text);
              expect(body, findsOneWidget);
              expect(
                find.ancestor(of: body, matching: find.byType(SelectableText)),
                findsOneWidget,
              );
              final tokens = theme.extension<AppTokens>()!;
              final bodyWidget = tester.widget<SelectableText>(
                find.ancestor(of: body, matching: find.byType(SelectableText)),
              );
              expect(bodyWidget.style!.color, tokens.text2);
              expect(
                bodyWidget.style!.fontSize,
                scenario.opening ? 15.5 : 14.5,
              );
              expect(bodyWidget.style!.height, scenario.opening ? 1.7 : 1.65);
              final heading = tester.widget<Text>(find.text(title).first);
              expect(heading.style!.color, tokens.accent);
              expect(heading.style!.fontSize, 13);
              expect(
                heading.style!.fontVariations,
                ContentElementTokens.supplementHeading.fontVariations,
              );
              final date = tester.widget<Text>(
                find.text(formatDisplayTime(raw: supplement.timeRaw)),
              );
              expect(date.style!.color, tokens.text3);
              expect(date.style!.fontWeight, FontWeight.w500);
              final lightNote = find.byKey(
                ValueKey(
                  'supplement-${scenario.post.pid}-${scenario.post.notes.indexOf(note)}',
                ),
              );
              expect(
                find.descendant(
                  of: lightNote,
                  matching: find.byType(Container),
                ),
                findsNothing,
              );
              expect(find.text(note.text), findsNothing);
            }
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}
