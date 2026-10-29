/// 我的帖子:主题 / 回复 / 点评,以及状态筛选
///
/// 个人帖子页是 #delform 下的裸表格,不是 tbody#normalthread_*。
/// 回复视图里一帖可有多条回复摘要,定位楼层必须用摘要行的非空 pid。
library;

import 'package:flutter/material.dart';
import '../ui/segmented.dart';
import '../ui/picker.dart';
import '../design/typography.dart';
import '../ui/press.dart';
import '../ui/plain_rows.dart';

import '../data/thread_read_index.dart';
import '../di.dart';
import '../data/space_repository.dart';
import '../widgets/large_title_scaffold.dart';
import '../design/tokens.dart';
import '../models/models.dart';
import '../widgets/paged_list.dart';
import 'thread_detail_page.dart';

class MyThreadsPage extends StatefulWidget {
  final SpaceRepository? repository;

  /// 为空即当前账号;传 uid 则看他人的主题与回复
  final String? uid;
  final String title;

  const MyThreadsPage({
    super.key,
    this.repository,
    this.uid,
    this.title = '我的帖子',
  });

  @override
  State<MyThreadsPage> createState() => _MyThreadsPageState();
}

class _MyThreadsPageState extends State<MyThreadsPage> {
  static const _labels = ['主题', '回复', '点评'];
  static const _types = ['thread', 'reply', 'postcomment'];
  int _seg = 0;

  @override
  Widget build(BuildContext context) {
    return LargeTitleScaffold(
      title: widget.title,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screen,
              0,
              AppSpace.screen,
              8,
            ),
            child: AppSegmented<int>(
              fallbackTitle: '我的帖子',
              options: [
                for (var i = 0; i < _labels.length; i++)
                  PickerOption(value: i, label: _labels[i]),
              ],
              value: _seg,
              onChanged: (i) => setState(() => _seg = i),
            ),
          ),
          Expanded(
            child: PagedList<MyThread>(
              key: ValueKey(_seg),
              emptyMessage: '还没有相关的帖子',
              padding: const EdgeInsets.only(top: 4, bottom: 40),
              loader: (page, {bool refresh = false}) =>
                  (widget.repository ?? spaceRepo).threads(
                    uid: widget.uid,
                    type: _types[_seg],
                    page: page,
                    refresh: refresh,
                  ),
              // 行级监听:一次 markRead 只重建对应一行;replies 为空时只分已看/未看
              itemBuilder: (context, item) => ReadStateBuilder(
                tid: item.tid,
                replies: item.replies,
                builder: (context, state) => _Row(item: item, readState: state),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final MyThread item;
  final ThreadReadState readState;
  const _Row({required this.item, required this.readState});

  void _openThread(BuildContext context, {MyReplySnippet? snippet}) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ThreadDetailPage(
            tid: item.tid,
            fid: item.forumFid,
            title: item.title,
            gotoUrl: snippet?.targetUrl,
            focusPid: snippet?.pid,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PlainRow(
      onTap: () => _openThread(context),
      child: Semantics(
        label: readSemanticsLabel(readState),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.forumName != null) ...[
              Text(
                item.forumName!,
                style: AppType.caption.copyWith(color: t.accent),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              item.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.headline.copyWith(
                color: readTitleColor(t, readState),
              ),
            ),
            const SizedBox(height: 6),
            // 新回复并入元信息行,不另起一行
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(_meta(), style: AppType.footnote.copyWith(color: t.text3)),
                if (readState case final ThreadReadNewReplies fresh)
                  newRepliesText(t, fresh),
              ],
            ),
            // 可定位的回复摘要:左侧细线,点按直接跳到那一楼
            for (final snippet in item.replySnippets)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: PressHighlight(
                  onTap: () => _openThread(context, snippet: snippet),
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: t.fill2, width: 3),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
                      child: Text(
                        snippet.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.subhead.copyWith(color: t.text2),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 元信息不使用间隔号,用全角空格分隔
  String _meta() {
    final parts = <String>[
      if (item.replies != null) '回复 ${item.replies}',
      if (item.views != null) '查看 ${item.views}',
      if (item.lastTimeRaw != null && item.lastTimeRaw!.isNotEmpty)
        item.lastTimeRaw!,
    ];
    return parts.join('  ');
  }
}
