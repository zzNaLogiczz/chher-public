/// 正文链接的打开方式:站内帖子、文章进 App 页面,其余交给系统默认浏览器
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/link_target.dart';
import '../pages/article_page.dart';
import '../pages/thread_detail_page.dart';
import '../ui/feedback.dart';

/// 交给系统浏览器;返回是否成功拉起。测试里替换成 fake,不真的打开浏览器。
typedef ExternalLauncher = Future<bool> Function(Uri uri);

ExternalLauncher externalLauncher = (uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// 用系统浏览器打开;没有可用浏览器或被系统拒绝时只提示,不重试
Future<void> openExternal(BuildContext context, Uri uri) async {
  bool ok;
  try {
    ok = await externalLauncher(uri);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) AppToast.show(context, '无法打开链接');
}

/// 卡片与行内链接共用的入口;[title] 是进入页面前顶栏先显示的标题
Future<void> openLinkTarget(
  BuildContext context,
  LinkTarget target, {
  String title = '',
}) async {
  switch (target) {
    case ThreadLink(:final tid, :final pid):
      // 带楼层的 findpost 链接沿用通知的定位方式:原地址交给帖子页去跳转
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ThreadDetailPage(
            tid: tid,
            title: title,
            gotoUrl: pid == null ? null : target.uri.toString(),
            focusPid: pid,
          ),
        ),
      );
    case ArticleLink(:final aid):
      // 文章其实是论坛帖时,文章页自己会转交帖子页
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ArticlePage(aid: aid, title: title),
        ),
      );
    case BilibiliVideo() || OtherSiteLink() || ExternalLink():
      await openExternal(context, target.uri);
  }
}
