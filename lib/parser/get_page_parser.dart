import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/models.dart';
import '../network/account_header.dart';
import '../network/chh_fetcher.dart';
import 'dom_utils.dart';
import 'header_parser.dart';
import 'misc_parser.dart';
import 'thread_list_parser.dart';

typedef GetPageInput = ({
  String html,
  int status,
  Uri url,
  bool ajax,
  int? forumFid,
  bool observeHeader,
});

class ParsedForumList {
  const ParsedForumList(
    this.types,
    this._list,
    this._message,
    this.passwordForm,
  );

  final List<ThreadType> types;
  final ThreadListPage? _list;
  final PageMessage? _message;
  final ForumPasswordForm? passwordForm;

  ThreadListPage get list {
    if (_message case final message?) throw message;
    return _list!;
  }
}

typedef ForumPasswordForm = ({
  String action,
  String formHash,
  String? cookiePrefix,
});

typedef InspectedPage = ({
  String? rejection,
  bool blocked,
  bool waf,
  String title,
  HeaderObservation? header,
  ParsedForumList? forumList,
});

InspectedPage inspectGetPage(
  GetPageInput input, {
  dom.Document Function(String source, {required bool generateSpans})?
  parseDocument,
}) {
  final source = input.html;
  final response = ChhResponse(input.status, source);
  dom.Document? doc;
  // Validation, account observation, and list extraction can all use this DOM.
  dom.Document document() => doc ??= (parseDocument ?? html_parser.parse)(
    source,
    generateSpans: input.observeHeader,
  );
  final rejection = response.getPageRejection(
    input.url,
    ajax: input.ajax,
    document: document,
  );
  final blocked = response.isBlocked;
  HeaderObservation? header;
  ParsedForumList? forumList;
  if (!blocked && rejection == null) {
    if (input.observeHeader) {
      final badges = parseHeaderDocument(document());
      header = (
        badges: badges,
        guest:
            badges == null &&
            isGuestAccountDocument(source, document: document),
      );
    }
    if (input.forumFid case final fid?) {
      final page = document();
      final message = detectPageMessage(page);
      // Categories used to be read even when the list was a site message.
      forumList = ParsedForumList(
        parseThreadTypesDocument(page),
        message == null ? parseThreadListDocument(page, forumFid: fid) : null,
        message,
        _forumPasswordForm(page, source),
      );
    }
  }
  return (
    rejection: rejection,
    blocked: blocked,
    waf: (blocked && response.hasWafFeatures) || rejection == 'challenge',
    title: response.titleSummary,
    header: header,
    forumList: forumList,
  );
}

ForumPasswordForm? _forumPasswordForm(dom.Document doc, String source) {
  final form = doc.querySelector('form[action*="action=pwverify"]');
  if (form == null) return null;
  return (
    action: form.attributes['action'] ?? '',
    formHash:
        form.querySelector('input[name="formhash"]')?.attributes['value'] ?? '',
    cookiePrefix: RegExp(
      r"cookiepre\s*=\s*'([^']*)'",
    ).firstMatch(source)?.group(1),
  );
}
