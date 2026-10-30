/// A searchable directory of the site's real categories and forums.
library;

import 'package:flutter/material.dart';
import '../ui/picker.dart';
import '../design/typography.dart';
import '../ui/grouped.dart';

import '../di.dart';
import '../design/tokens.dart';
import '../models/models.dart';
import '../widgets/browse_controls.dart';
import '../widgets/state_view.dart';
import '../widgets/expressive_controls.dart';
import 'forum_threads_page.dart';

class ForumIndexView extends StatefulWidget {
  final Future<List<ForumCategory>> Function(bool refresh)? loadForums;
  const ForumIndexView({super.key, this.loadForums});

  @override
  State<ForumIndexView> createState() => _ForumIndexViewState();
}

class _ForumIndexViewState extends State<ForumIndexView> {
  final _search = TextEditingController();
  int _category = -1;
  late Future<List<ForumCategory>> _future = _load(false);

  Future<List<ForumCategory>> _load(bool refresh) =>
      widget.loadForums?.call(refresh) ??
      forumRepo.forumIndex(refresh: refresh);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load(true);
    });
    await _future;
  }

  String _navigationLabel(List<ForumCategory> categories, int index) {
    final name = categories[index].name;
    final short = _categoryName(name).title;
    return categories
                .where((c) => _categoryName(c.name).title == short)
                .length ==
            1
        ? short
        : name;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([favoriteIndex, chhSession]),
    builder: (context, _) => _directory(context),
  );

  Widget _directory(BuildContext context) {
    final t = AppTokens.of(context);
    return FutureBuilder<List<ForumCategory>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState != ConnectionState.done) {
          return StateView.loading();
        }
        if (snapshot.hasError && !snapshot.hasData) {
          return StateView.error(snapshot.error!, onRetry: _refresh);
        }
        final categories = snapshot.data ?? const <ForumCategory>[];
        final keyword = _search.text.trim().toLowerCase();
        final visible = <ForumCategory>[];
        if (_category == -1 && chhSession.loggedIn) {
          final favorites = favoriteIndex.items
              .where(
                (item) =>
                    item.type == FavoriteType.forum &&
                    item.targetId != null &&
                    (keyword.isEmpty ||
                        '收藏 ${item.title}'.toLowerCase().contains(keyword)),
              )
              .map((item) => Forum(fid: item.targetId!, name: item.title))
              .toList();
          if (favorites.isNotEmpty) {
            visible.add(ForumCategory(name: '收藏', forums: favorites));
          }
        }
        for (var i = 0; i < categories.length; i++) {
          if (_category != -1 && i != _category) continue;
          final c = categories[i];
          final forums = c.forums
              .where(
                (f) =>
                    keyword.isEmpty ||
                    '${c.name} ${f.name}'.toLowerCase().contains(keyword),
              )
              .toList();
          if (forums.isNotEmpty) {
            visible.add(ForumCategory(name: c.name, forums: forums));
          }
        }
        return ExpressivePageReveal(
          active: true,
          animateOnMount: true,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: BrowseSearchField(
                  controller: _search,
                  hint: '查找版块',
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  onClear: () => setState(() => _search.clear()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.screen - 4,
                  0,
                  AppSpace.screen,
                  4,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PickerButton<int>(
                    sheetTitle: '选择分区',
                    options: [
                      PickerOption(
                        value: -1,
                        label: '全部分区',
                        detail:
                            '${categories.fold<int>(0, (n, c) => n + c.forums.length)} 个版块',
                        wide: true,
                      ),
                      for (var i = 0; i < categories.length; i++)
                        PickerOption(
                          value: i,
                          label: _navigationLabel(categories, i),
                          detail: '${categories[i].forums.length} 个版块',
                        ),
                    ],
                    value: _category,
                    onChanged: (value) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      if (value != _category) {
                        setState(() => _category = value);
                      }
                    },
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    primary: true,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (visible.isEmpty)
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 300,
                            child: StateView.empty(
                              message: keyword.isEmpty ? '这里还没有版块' : '没有找到相关版块',
                            ),
                          ),
                        ),
                      for (final category in visible) ...[
                        SliverPadding(
                          // 分组标题:分区短名 + 版块数;源站长说明只在这里出现一次
                          padding: const EdgeInsets.fromLTRB(32, 20, 32, 7),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _categoryName(category.name).title,
                                        style: AppType.footnote.copyWith(
                                          color: t.text3,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${category.forums.length}',
                                      semanticsLabel:
                                          '${category.forums.length}个版块',
                                      style: AppType.footnote.copyWith(
                                        color: t.text3,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_categoryName(category.name).description
                                    case final String description)
                                  Text(
                                    description,
                                    style: AppType.footnote.copyWith(
                                      color: t.text3,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.groupInset,
                          ),
                          sliver: SliverList.builder(
                            itemCount: category.forums.length,
                            itemBuilder: (context, i) => _ForumRow(
                              forum: category.forums[i],
                              first: i == 0,
                              last: i == category.forums.length - 1,
                            ),
                          ),
                        ),
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

({String title, String? description}) _categoryName(String name) {
  final separator = RegExp(r'[-－—]').firstMatch(name);
  if (separator == null || separator.start == 0) {
    return (title: name, description: null);
  }
  final description = name.substring(separator.end).trim();
  return (
    title: name.substring(0, separator.start).trim(),
    description: description.isEmpty ? null : description,
  );
}

/// 版块行:分组面里的一行,逐行惰性构建,首尾两行负责圆角
class _ForumRow extends StatelessWidget {
  final Forum forum;
  final bool first;
  final bool last;
  const _ForumRow({
    required this.forum,
    required this.first,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final count = forum.threadCount != null
        ? '${forum.threadCount} 个主题'
        : forum.postCount != null
        ? '${forum.postCount} 个帖子'
        : null;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: first ? const Radius.circular(AppRadii.md) : Radius.zero,
        bottom: last ? const Radius.circular(AppRadii.md) : Radius.zero,
      ),
      child: ColoredBox(
        color: t.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GroupedRow(
              title: forum.name,
              subtitle: count,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ForumThreadsPage(fid: forum.fid, title: forum.name),
                ),
              ),
            ),
            if (!last)
              Padding(
                padding: const EdgeInsets.only(left: AppSpace.rowInset),
                child: Divider(
                  height: AppSpace.hairline,
                  thickness: AppSpace.hairline,
                  color: t.separator,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
