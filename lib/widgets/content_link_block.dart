/// 正文里的链接卡片:帖子页、文章页、文章评论共用一个入口
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import 'bilibili_card.dart';
import 'site_link_card.dart';

class ContentLinkBlockView extends StatelessWidget {
  final ContentBlock block;
  const ContentLinkBlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) => switch (block) {
    final SiteLinkBlock site => SiteLinkCard(
      key: ValueKey(site.target.key),
      block: site,
    ),
    final BilibiliBlock video => BilibiliCard(
      key: ValueKey(video.video.key),
      block: video,
    ),
    _ => const SizedBox.shrink(),
  };
}
