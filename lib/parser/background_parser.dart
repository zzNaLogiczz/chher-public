/// 论坛读页在后台解析。门户文章保留自己的大小分流。
library;

import 'package:flutter/foundation.dart';

import '../data/thread_page_reading.dart';
import '../models/models.dart';
import 'get_page_parser.dart';
import 'parser_worker.dart';
import 'portal_parser.dart';
import 'thread_parser.dart';

const backgroundParseThreshold = 128 * 1024;

typedef ParserDispatch =
    Future<R> Function<M, R>(ComputeCallback<M, R> callback, M message);

Future<InspectedPage> inspectGetPageAsync(
  GetPageInput input, {
  ParserDispatch dispatch = dispatchParserInWorker,
}) => dispatch(inspectGetPage, input);

Future<PortalContent> parsePortalContentAsync(
  String html, {
  required int aid,
  ParserDispatch dispatch = dispatchParserInWorker,
}) async {
  if (html.length < backgroundParseThreshold) {
    final content = parsePortalContent(html, aid: aid);
    if (content case ThreadContent(detail: final detail?)) {
      parsedThreadReading[detail] = await dispatch(
        ThreadPageReading.new,
        detail,
      );
    }
    return content;
  }
  final (content, reading) = await compute(_portal, (html: html, aid: aid));
  if (content is ThreadContent && reading != null) {
    parsedThreadReading[content.detail!] = reading;
  }
  return content;
}

(PortalContent, ThreadPageReading?) _portal(({String html, int aid}) request) {
  final content = parsePortalContent(request.html, aid: request.aid);
  final detail = content is ThreadContent ? content.detail : null;
  return (content, detail == null ? null : ThreadPageReading(detail));
}

Future<ThreadDetail> parseThreadAsync(
  String html, {
  required int tid,
  int fallbackPage = 1,
  ParserDispatch dispatch = dispatchParserInWorker,
}) async {
  final request = (html: html, tid: tid, page: fallbackPage);
  final (detail, reading) = await dispatch(_thread, request);
  parsedThreadReading[detail] = reading;
  return detail;
}

(ThreadDetail, ThreadPageReading) _thread(
  ({String html, int tid, int page}) request,
) {
  final detail = parseThread(
    request.html,
    tid: request.tid,
    fallbackPage: request.page,
  );
  return (detail, ThreadPageReading(detail));
}
