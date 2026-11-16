import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import '../core/chh_urls.dart';
import '../models/poll.dart';
import '../models/models.dart' show PageMessage;
import '../network/chh_client.dart';
import '../parser/poll_parser.dart';
import '../parser/post_action_parser.dart';

class PollRepository {
  final ChhClient client;
  final int? Function()? uid;
  final int Function()? sessionRevision;
  final _pending = <int>{};
  final _choices = <String, Map<String, String>>{};
  File? _file;
  Future<void> _writes = Future.value();
  PollRepository(this.client, {this.uid, this.sessionRevision});

  Future<void> attach(File? file) async {
    _file = file;
    if (file == null) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map && raw['version'] == 1 && raw['choices'] is Map) {
        for (final entry in (raw['choices'] as Map).entries) {
          if (entry.key is String &&
              entry.value is Map &&
              (entry.value as Map).entries.every(
                (e) => e.key is String && e.value is String,
              )) {
            _choices.putIfAbsent(
              entry.key,
              () => Map<String, String>.from(entry.value),
            );
          }
        }
      }
    } catch (_) {
      /* Storage failure keeps in-memory choices. */
    }
  }

  Future<void> flush() {
    final file = _file;
    if (file == null) return Future.value();
    final data = jsonEncode({'version': 1, 'choices': _choices});
    return _writes = _writes.then((_) async {
      try {
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(data, flush: true);
        await temp.rename(file.path);
      } catch (_) {
        /* Voting must not be repeated after a disk failure. */
      }
    });
  }

  Future<ThreadPoll> withMyChoices(ThreadPoll poll) async {
    final mine = _choices['${uid?.call()}:${poll.tid}'];
    return poll.withOptions(
      poll.options
          .map(
            (o) => o.withMine(
              mine != null &&
                  (o.id != null
                      ? mine.containsKey(o.id)
                      : mine.values.where((text) => text == o.text).length ==
                                1 &&
                            poll.options
                                    .where((other) => other.text == o.text)
                                    .length ==
                                1),
            ),
          )
          .toList(),
    );
  }

  bool _validAction(Uri uri, int tid, String action) =>
      uri.scheme == 'https' &&
      {'www.chiphell.com', 'chiphell.com'}.contains(uri.host) &&
      uri.userInfo.isEmpty &&
      uri.path == '/forum.php' &&
      uri.queryParameters['mod'] == 'misc' &&
      uri.queryParameters['action'] == action &&
      uri.queryParameters['tid'] == '$tid';

  Future<PollVoteResult> vote(ThreadPoll poll, Set<String> selected) async {
    const failure = '没有投上，请稍后再试';
    final actor = uid?.call();
    if (actor == null) {
      return const PollVoteResult(success: false, message: '请先登录');
    }
    final revision = sessionRevision?.call();
    bool active() =>
        uid?.call() == actor && sessionRevision?.call() == revision;
    if (!_pending.add(poll.tid)) {
      return const PollVoteResult(success: false, message: '投票中');
    }
    try {
      final page = Uri.parse(ChhUrls.absolutize('thread-${poll.tid}-1-1.html'));
      final freshHtml = await client.getHtml(page, refresh: true);
      if (!active()) {
        return const PollVoteResult(success: false, message: '账号已变化，请重试');
      }
      final fresh = parseThreadPoll(freshHtml, tid: poll.tid);
      final hash = html
          .parse(freshHtml)
          .querySelector('form#poll input[name="formhash"]')
          ?.attributes['value'];
      if (fresh == null ||
          !fresh.canVote ||
          hash == null ||
          hash.isEmpty ||
          selected.isEmpty ||
          selected.length > (fresh.maxChoices ?? 1) ||
          !selected.every((id) => fresh.options.any((o) => o.id == id)) ||
          !_validAction(fresh.action!, poll.tid, 'votepoll')) {
        return const PollVoteResult(success: false, message: '投票状态已变化，请刷新帖子');
      }
      final ids = selected.toList();
      final response = await client.postFormFields(fresh.action!, [
        MapEntry('formhash', hash),
        for (final id in ids) MapEntry('pollanswers[]', id),
        const MapEntry('pollsubmit', 'true'),
      ], retryTransportFailures: false);
      if (!active()) {
        return const PollVoteResult(success: false, message: '账号已变化，请重新打开帖子');
      }
      final updated = parseThreadPoll(
        await client.getHtml(page, refresh: true),
        tid: poll.tid,
      );
      if (!active()) {
        return const PollVoteResult(success: false, message: '账号已变化，请重新打开帖子');
      }
      // Aggregate counts can change because another reader voted. Only the
      // active account's server state can confirm this submission.
      final submitError = parseInteractionPageError(response.body);
      if (updated != null &&
          updated.alreadyVoted &&
          submitError == null &&
          !response.rejectedBeforeApp) {
        _choices['$actor:${poll.tid}'] = {
          for (final o in fresh.options)
            if (selected.contains(o.id)) o.id!: o.text,
        };
        await flush();
        return PollVoteResult(
          success: true,
          poll: await withMyChoices(updated),
        );
      }
      return PollVoteResult(
        success: false,
        poll: updated,
        message: submitError?.message ?? failure,
      );
    } on PageMessage catch (error) {
      return PollVoteResult(success: false, message: error.text);
    } catch (_) {
      return const PollVoteResult(success: false, message: failure);
    } finally {
      _pending.remove(poll.tid);
    }
  }

  Future<PollVotersPage> participants(
    ThreadPoll poll, {
    String? optionId,
    int page = 1,
  }) async {
    final url = poll.participantsUrl;
    if (url == null || !_validAction(url, poll.tid, 'viewvote') || page < 1) {
      throw ArgumentError('参与人地址无效');
    }
    final source = await client.getHtml(
      url.replace(
        queryParameters: {
          ...url.queryParameters,
          'polloptionid': ?optionId,
          'page': '$page',
        },
      ),
      refresh: true,
    );
    return parsePollVoters(source, fallbackPage: page, optionId: optionId);
  }
}
