/// 收藏:全部 / 帖子 / 版块 / 文章
///
/// 条目 id 是 favid,不等于内容 tid / fid / aid,对象类型按目标 URL 判定。
library;

import 'package:flutter/material.dart';
import '../ui/segmented.dart';
import '../ui/picker.dart';
import '../core/display_time.dart';
import '../design/display_text.dart';
import '../design/typography.dart';
import '../ui/plain_rows.dart';

import '../di.dart';
import '../data/space_repository.dart';
import '../widgets/large_title_scaffold.dart';
import '../design/tokens.dart';
import '../design/thread_row_tokens.dart';
import '../models/models.dart';
import '../widgets/paged_list.dart';
import 'article_page.dart';
import 'thread_detail_page.dart';
import 'forum_threads_page.dart';

class FavoritesPage extends StatelessWidget {
  final SpaceRepository? repository;
  const FavoritesPage({super.key, this.repository});

  @override
  Widget build(BuildContext context) {
    return LargeTitleScaffold(
      title: '收藏',
      body: FavoritesBody(repository: repository),
    );
  }
}

class FavoritesBody extends StatefulWidget {
  final SpaceRepository? repository;
  const FavoritesBody({super.key, this.repository});

  @override
  State<FavoritesBody> createState() => _FavoritesBodyState();
}

class _FavoritesBodyState extends State<FavoritesBody> {
  static const _labels = ['全部', '帖子', '版块', '文章'];
  static const _types = [
    FavoriteType.all,
    FavoriteType.thread,
    FavoriteType.forum,
    FavoriteType.article,
  ];
  int _seg = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screen,
            0,
            AppSpace.screen,
            8,
          ),
          child: AppSegmented<int>(
            fallbackTitle: '收藏',
            options: [
              for (var i = 0; i < _labels.length; i++)
                PickerOption(value: i, label: _labels[i]),
            ],
            value: _seg,
            onChanged: (i) => setState(() => _seg = i),
          ),
        ),
        Expanded(
          child: PagedList<FavoriteItem>(
            key: ValueKey(_seg),
            emptyMessage: '还没有收藏',
            padding: const EdgeInsets.only(top: 4),
            precedingBottomPadding: (item) =>
                item.type == FavoriteType.thread && item.targetId != null
                ? ThreadRowTokens.verticalPadding
                : AppRowTokens.plainVerticalPadding,
            loader: (page, {bool refresh = false}) async {
              final epoch = favoriteIndex.epoch;
              final result = await (widget.repository ?? spaceRepo).favorites(
                type: _types[_seg],
                page: page,
                refresh: refresh,
              );
              // 换号后返回的旧页面不能写入新账号的索引。
              if (chhSession.loggedIn && favoriteIndex.epoch == epoch) {
                favoriteIndex.merge(result.items, prepend: page == 1);
              }
              return result;
            },
            itemBuilder: _row,
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, FavoriteItem f) {
    if (f.targetId case final tid? when f.type == FavoriteType.thread) {
      return ReadStateBuilder(
        tid: tid,
        replies: null,
        builder: (context, state) => ThreadRow.entry(
          tid: tid,
          title: f.title,
          category: '帖子',
          timeRaw: f.timeRaw,
          readState: state,
          onTap: () => _open(context, f),
        ),
      );
    }
    final t = AppTokens.of(context);
    final kind = f.type == FavoriteType.forum ? '版块' : '文章';
    final time = formatDisplayTime(
      raw: f.timeRaw,
      style: DisplayTimeStyle.list,
    );
    return PlainRow(
      onTap: () => _open(context, f),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kind, style: AppType.caption.copyWith(color: t.accent)),
          const SizedBox(height: 4),
          Text(
            f.type == FavoriteType.forum
                ? formatForumName(f.title)
                : normalizeDisplayText(f.title),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppType.headline.copyWith(color: t.text),
          ),
          if (time.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              time,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.footnote.copyWith(color: t.text3),
            ),
          ],
        ],
      ),
    );
  }

  /// 按目标类型分流:帖子、版块、门户文章各进各自页面
  void _open(BuildContext context, FavoriteItem f) {
    final nav = Navigator.of(context);
    if (f.targetId case final tid? when f.type == FavoriteType.thread) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => ThreadDetailPage(tid: tid, title: f.title),
        ),
      );
      return;
    }
    if (f.fid != null) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => ForumThreadsPage(fid: f.fid!, title: f.title),
        ),
      );
      return;
    }
    final aid = int.tryParse(
      RegExp(r'article-(\d+)-').firstMatch(f.url)?.group(1) ?? '',
    );
    if (aid != null) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => ArticlePage(aid: aid, title: f.title),
        ),
      );
    }
  }
}
