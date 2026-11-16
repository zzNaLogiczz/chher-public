/// 正文里的链接卡片:帖子页、文章页、文章评论共用一个入口
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import 'bilibili_card.dart';
import 'site_link_card.dart';

class ContentLinkBlockView extends StatelessWidget {
  final ContentBlock block;
  final bool compact;
  const ContentLinkBlockView({
    super.key,
    required this.block,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => switch (block) {
    final SiteLinkBlock site => SiteLinkCard(
      key: ValueKey(site.target.key),
      block: site,
      compact: compact,
    ),
    final BilibiliBlock video => BilibiliCard(
      key: ValueKey(video.video.key),
      block: video,
      compact: compact,
    ),
    _ => const SizedBox.shrink(),
  };
}
