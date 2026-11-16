import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import '../core/chh_urls.dart';
import '../models/poll.dart';
import 'dom_utils.dart';

ThreadPoll? parsePollElement(dom.Element? form, {required int tid}) {
  if (form == null) return null;
  final info = cleanText(form.querySelector('.pinf')?.text);
  final type = cleanText(form.querySelector('.pinf strong')?.text);
  final text = cleanText(form.text);
  final options = <PollOption>[];
  for (final label in form.querySelectorAll('td.pvt label')) {
    final row = label.parent?.parent;
    final next = row?.nextElementSibling;
    final result = next?.querySelector('.pbr') != null ? next : null;
    final percentage = RegExp(r'([\d.]+)%').firstMatch(result?.text ?? '');
    final votes = RegExp(
      r'\((\d+)\)',
    ).firstMatch(result?.querySelector('em')?.text ?? '');
    options.add(
      PollOption(
        text: cleanText(label.text).replaceFirst(RegExp(r'^\d+\.\s*'), ''),
        id: row
            ?.querySelector('input[name="pollanswers[]"]')
            ?.attributes['value'],
        votes: int.tryParse(votes?.group(1) ?? ''),
        percentage: double.tryParse(percentage?.group(1) ?? ''),
      ),
    );
  }
  Uri? url(String? raw) =>
      raw == null || raw.isEmpty ? null : Uri.tryParse(ChhUrls.absolutize(raw));
  final deadline = cleanText(form.querySelector('p.ptmr')?.text);
  return ThreadPoll(
    tid: tid,
    multiple: type.contains('多选')
        ? true
        : type.contains('单选')
        ? false
        : null,
    maxChoices: type.contains('单选')
        ? 1
        : int.tryParse(
            RegExp(r'最多可选\s*(\d+)\s*项').firstMatch(info)?.group(1) ?? '',
          ),
    participantCount: int.tryParse(
      RegExp(r'共有\s*(\d+)\s*人').firstMatch(info)?.group(1) ?? '',
    ),
    deadline: deadline.isEmpty ? null : deadline,
    resultsAfterVote: text.contains('投票后结果可见'),
    alreadyVoted: text.contains('您已经投过票'),
    closed: text.contains('该投票已经关闭或者过期'),
    ended: deadline.contains('投票已经结束'),
    action: url(form.attributes['action']),
    participantsUrl: url(
      form
          .querySelector('.pinf a[href*="action=viewvote"]')
          ?.attributes['href'],
    ),
    options: List.unmodifiable(options),
  );
}

ThreadPoll? parseThreadPoll(String source, {required int tid}) {
  final doc = html.parse(source);
  throwIfMessagePage(doc);
  return parseThreadPollDocument(doc, tid: tid);
}

ThreadPoll? parseThreadPollDocument(dom.Document doc, {required int tid}) {
  final page = parsePager(doc);
  if (page.current != 1) return null;
  // The poll belongs to the opening floor, never a quoted form in its body.
  final first = doc.querySelector('table[id^="pid"]');
  if (first == null) return null;
  final floor = cleanText(first.querySelector('a[id^="postnum"]')?.text);
  if (floor.isNotEmpty && !{'1#', '1', '楼主'}.contains(floor)) return null;
  final form = first.querySelector('.pcbs form#poll');
  if (form == null) return null;
  for (var node = form.parent; node != null; node = node.parent) {
    if (node.id.startsWith('postmessage_')) return null;
  }
  return parsePollElement(form, tid: tid);
}

PollVotersPage parsePollVoters(
  String source, {
  int fallbackPage = 1,
  String? optionId,
}) {
  final doc = html.parse(source);
  throwIfMessagePage(doc);
  final options = doc
      .querySelectorAll('select.ps option')
      .where((o) => (o.attributes['value'] ?? '').isNotEmpty)
      .map(
        (o) => PollVoterOption(
          id: o.attributes['value']!,
          text: cleanText(o.text),
        ),
      )
      .toList();
  final voters = <PollVoter>[];
  for (final li in doc.querySelectorAll('ul.voterl > li')) {
    final link = li.querySelector('p > a[href*="space-uid-"]');
    final uid = int.tryParse(
      ChhUrls.uidFromUrl(link?.attributes['href'] ?? '') ?? '',
    );
    final name = cleanText(link?.text);
    if (uid == null || name.isEmpty) continue;
    final avatar = li.querySelector('img')?.attributes['src'];
    voters.add(
      PollVoter(
        uid: uid,
        name: name,
        avatarUrl: avatar == null ? null : ChhUrls.absolutize(avatar),
      ),
    );
  }
  return PollVotersPage(
    options: options,
    voters: voters,
    selectedOptionId:
        optionId ??
        doc.querySelector('select.ps option[selected]')?.attributes['value'] ??
        options.firstOrNull?.id,
    page: parsePager(doc, fallbackPage: fallbackPage),
  );
}
