import 'dart:io';
import 'package:chh_app/data/post_interaction_drafts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unknown outcome and draft survive restart and remain account scoped',
    () async {
      final dir = await Directory.systemTemp.createTemp('interaction-draft-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/draft.json');
      final key = PostInteractionDraftStore.key('alice', 7, 9, 'rating');
      final first = PostInteractionDraftStore(
        file: file,
        requireDurability: true,
      );
      expect(
        await first.put(
          key,
          const PostInteractionDraft(
            scores: {'score1': 2},
            reason: '测试',
            uncertain: true,
          ),
        ),
        isTrue,
      );
      final restarted = PostInteractionDraftStore(
        file: file,
        requireDurability: true,
      );
      await restarted.load();
      expect(restarted.get(key)!.uncertain, isTrue);
      expect(restarted.get(key)!.scores, {'score1': 2});
      expect(
        restarted.get(PostInteractionDraftStore.key('bob', 7, 9, 'rating')),
        isNull,
      );
      expect(await restarted.remove(key), isTrue);
      final last = PostInteractionDraftStore(file: file);
      await last.load();
      expect(last.get(key), isNull);
    },
  );
  test(
    'failed durable write is reported and in-memory guard is retained',
    () async {
      final dir = await Directory.systemTemp.createTemp('interaction-failed-');
      addTearDown(() => dir.delete(recursive: true));
      final parent = File('${dir.path}/not-directory');
      await parent.writeAsString('x');
      final store = PostInteractionDraftStore(
        file: File('${parent.path}/draft.json'),
        requireDurability: true,
      );
      expect(
        await store.put('key', const PostInteractionDraft(uncertain: true)),
        isFalse,
      );
      expect(store.get('key')!.uncertain, isTrue);
    },
  );
  test('writes during load are not replaced with older disk data', () async {
    final dir = await Directory.systemTemp.createTemp('interaction-merge-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/draft.json');
    final a = PostInteractionDraftStore(file: file);
    await a.put('key', const PostInteractionDraft(text: '旧'));
    final b = PostInteractionDraftStore(file: file);
    await b.put('key', const PostInteractionDraft(text: '新', uncertain: true));
    expect(b.get('key')!.text, '新');
    expect(b.get('key')!.uncertain, isTrue);
  });
}
