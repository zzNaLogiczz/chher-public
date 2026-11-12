/// 大正文的纯解析放到 isolate；小页避免启动与传递开销。
library;

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'portal_parser.dart';
import 'thread_parser.dart';

const backgroundParseThreshold = 128 * 1024;

Future<PortalContent> parsePortalContentAsync(
  String html, {
  required int aid,
}) async {
  final request = (html: html, aid: aid);
  if (html.length < backgroundParseThreshold) return _portal(request);
  return compute(_portal, request);
}

PortalContent _portal(({String html, int aid}) request) =>
    parsePortalContent(request.html, aid: request.aid);

Future<ThreadDetail> parseThreadAsync(
  String html, {
  required int tid,
  int fallbackPage = 1,
}) async {
  final request = (html: html, tid: tid, page: fallbackPage);
  if (html.length < backgroundParseThreshold) return _thread(request);
  return compute(_thread, request);
}

ThreadDetail _thread(({String html, int tid, int page}) request) =>
    parseThread(request.html, tid: request.tid, fallbackPage: request.page);
