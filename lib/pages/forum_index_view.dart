/// A lazy directory of the site's real categories and forums.
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/forum_icons.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/shapes.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../di.dart';
import '../models/models.dart';
import '../ui/nav_bar.dart';
import '../ui/picker.dart';
import '../ui/press.dart';
import '../widgets/lacquer_tab_scaffold.dart';
import '../widgets/state_view.dart';
import 'forum_threads_page.dart';

class ForumIndexView extends StatefulWidget {
  final Future<List<ForumCategory>> Function(bool refresh)? loadForums;
  const ForumIndexView({super.key, this.loadForums});

  @override
  State<ForumIndexView> createState() => _ForumIndexViewState();
}

class _ForumIndexViewState extends State<ForumIndexView> {
  late Future<List<ForumCategory>> _future = _load(false);
  List<ForumCategory>? _categories;
  final _scroll = ScrollController();
  final _current = ValueNotifier<int>(0);
  final _sectionOffsets = <int, double>{};
  Set<int>? _favoriteIds;
  bool _measurePending = false;
  bool _pickerOpen = false;
  int _jumpGeneration = 0;

  Future<List<ForumCategory>> _load(bool refresh) =>
      widget.loadForums?.call(refresh) ??
      forumRepo.forumIndex(refresh: refresh);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateCurrent);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _current.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load(true);
    });
    await _future;
  }

  void _updateCurrent() {
    if (!_scroll.hasClients) return;
    final edge =
        _scroll.offset +
        MediaQuery.paddingOf(context).top +
        NavOverlay.barHeight;
    var current = 0;
    for (final entry in _sectionOffsets.entries) {
      if (entry.value <= edge + 1) current = entry.key;
    }
    _current.value = current;
  }

  void _recordOffset(int index, double offset) {
    _sectionOffsets[index] = offset;
    if (_measurePending) return;
    _measurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurePending = false;
      if (mounted) _updateCurrent();
    });
  }

  Future<void> _pickCategory(List<ForumCategory> categories) async {
    if (_pickerOpen || categories.isEmpty) return;
    _pickerOpen = true;
    final picked = await showPickerSheet<int>(
      context,
      title: '跳到分区',
      options: [
        for (final (index, category) in categories.indexed)
          PickerOption(
            value: index,
            label: _navigationLabel(categories, index),
            detail: '${category.forums.length} 个版块',
          ),
      ],
      value: _current.value,
      columns: 1,
      immediateSelection: true,
    );
    _pickerOpen = false;
    if (!mounted || picked == null || !_scroll.hasClients) return;
    // SliverList estimates distant row heights; correct once after that viewport
    // has laid out, without eagerly building the intervening categories.
    final generation = ++_jumpGeneration;
    final barBottom = MediaQuery.paddingOf(context).top + NavOverlay.barHeight;
    final reduced = MediaQuery.disableAnimationsOf(context);
    for (
      var pass = 0;
      pass < 2 && mounted && generation == _jumpGeneration;
      pass++
    ) {
      final offset = _sectionOffsets[picked.value];
      if (offset == null) return;
      final target = offset - barBottom;
      await AppMotion.scrollTo(_scroll.position, target, reduced: reduced);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  String _navigationLabel(List<ForumCategory> categories, int index) {
    final name = categories[index].name;
    final short = forumCategoryName(name).title;
    return categories
                .where((c) => forumCategoryName(c.name).title == short)
                .length ==
            1
        ? short
        : name;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([favoriteIndex, chhSession]),
    builder: (context, _) => FutureBuilder<List<ForumCategory>>(
      future: _future,
      builder: (context, snapshot) {
        final t = AppTokens.of(context);
        if (snapshot.hasData) _categories = snapshot.data;
        final hasData = _categories != null;
        final categories = _categories ?? const <ForumCategory>[];
        final byId = {
          for (final c in categories)
            for (final f in c.forums) f.fid: f,
        };
        final categoryById = {
          for (final c in categories)
            for (final f in c.forums) f.fid: c.name,
        };
        final favorites = chhSession.loggedIn
            ? favoriteIndex.items
                  .where(
                    (item) =>
                        item.type == FavoriteType.forum &&
                        item.targetId != null,
                  )
                  .map(
                    (item) =>
                        byId[item.targetId] ??
                        Forum(fid: item.targetId!, name: item.title),
                  )
                  .toList()
            : <Forum>[];
        final ids = favorites.map((f) => f.fid).toSet();
        final added =
            (_favoriteIds == null ? <int>{} : ids.difference(_favoriteIds!))
                .take(24)
                .toSet();
        _favoriteIds = ids;
        final visible = [
          if (favorites.isNotEmpty)
            ForumCategory(name: '收藏', forums: favorites),
          ...categories.where((c) => c.forums.isNotEmpty),
        ];
        _sectionOffsets.removeWhere((index, _) => index >= visible.length);
        return NotificationListener<ScrollStartNotification>(
          onNotification: (notification) {
            if (notification.dragDetails != null) _jumpGeneration++;
            return false;
          },
          child: LacquerTabScaffold(
            mistyCompact: true,
            contentOnPaper: true,
            title: '版块',
            eyebrow: hasData ? '${byId.length} 个版块' : null,
            controller: _scroll,
            onRefresh: _refresh,
            compactTitle: ValueListenableBuilder<int>(
              valueListenable: _current,
              builder: (context, index, _) => _DirectoryTitle(
                labels: [
                  for (var i = 0; i < visible.length; i++)
                    _navigationLabel(visible, i),
                ],
                index: index.clamp(0, visible.isEmpty ? 0 : visible.length - 1),
                onTap: visible.isEmpty ? null : () => _pickCategory(visible),
              ),
            ),
            slivers: [
              if (!hasData)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 300,
                    child: snapshot.hasError
                        ? StateView.error(snapshot.error!, onRetry: _refresh)
                        : snapshot.connectionState != ConnectionState.done
                        ? StateView.loading()
                        : StateView.empty(message: '这里还没有版块'),
                  ),
                ),
              if (hasData && visible.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 300,
                    child: StateView.empty(message: '这里还没有版块'),
                  ),
                ),
              for (final (index, category) in visible.indexed) ...[
                SliverLayoutBuilder(
                  builder: (_, constraints) {
                    _recordOffset(index, constraints.precedingScrollExtent);
                    final name = forumCategoryName(category.name);
                    return SliverPadding(
                      padding: index == 0 && t.style == AppearanceStyle.misty
                          ? ForumDirectoryTokens.sectionPadding.copyWith(top: 0)
                          : ForumDirectoryTokens.sectionPadding,
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.title,
                              key: ValueKey('forum-section-$index'),
                              style: ForumDirectoryTokens.heading.copyWith(
                                color: t.text,
                              ),
                            ),
                            if (name.description != null)
                              Text(
                                name.description!,
                                style: AppType.footnote.copyWith(
                                  color: t.text3,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.groupInset,
                  ),
                  sliver: DecoratedSliver(
                    decoration: ShapeDecoration(
                      color: t.surface,
                      shape: appShape(ForumDirectoryTokens.cardRadius),
                      shadows: t.shadowE1,
                    ),
                    sliver: SliverPadding(
                      padding: const EdgeInsets.all(
                        ForumDirectoryTokens.cardInset,
                      ),
                      sliver: SliverList.builder(
                        key: ValueKey('forum-category-${category.name}'),
                        itemCount: category.forums.length,
                        findChildIndexCallback: (key) {
                          final i = category.forums.indexWhere(
                            (f) => ValueKey(f.fid) == key,
                          );
                          return i < 0 ? null : i;
                        },
                        itemBuilder: (context, i) {
                          final forum = category.forums[i];
                          final isFavorite = index == 0 && favorites.isNotEmpty;
                          final insert =
                              isFavorite && added.contains(forum.fid);
                          return SingleMotionBuilder(
                            key: ValueKey(forum.fid),
                            from: insert ? 0 : 1,
                            value: 1,
                            motion: AppMotion.reveal,
                            active: !MediaQuery.disableAnimationsOf(context),
                            child: _ForumRow(
                              forum: forum,
                              categoryName: isFavorite
                                  ? categoryById[forum.fid] ?? ''
                                  : category.name,
                            ),
                            builder: (_, progress, child) => ClipRect(
                              child: Align(
                                alignment: Alignment.topCenter,
                                heightFactor: progress.clamp(0.0, 1.0),
                                child: child,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    ),
  );
}

class _DirectoryTitle extends StatefulWidget {
  const _DirectoryTitle({
    required this.labels,
    required this.index,
    this.onTap,
  });
  final List<String> labels;
  final int index;
  final VoidCallback? onTap;
  @override
  State<_DirectoryTitle> createState() => _DirectoryTitleState();
}

class _DirectoryTitleState extends State<_DirectoryTitle>
    with SingleTickerProviderStateMixin {
  late final _position = SingleMotionController(
    motion: AppMotion.select,
    vsync: this,
    initialValue: widget.index.toDouble(),
  );
  @override
  void didUpdateWidget(_DirectoryTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (MediaQuery.disableAnimationsOf(context)) {
      _position.value = widget.index.toDouble();
    } else if (widget.index != oldWidget.index) {
      _position.animateTo(widget.index.toDouble());
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final color = t.style == AppearanceStyle.cinnabar ? t.onLac : t.text;
    final labels = widget.labels.isEmpty ? ['版块'] : widget.labels;
    final height =
        MediaQuery.textScalerOf(context).scale(AppType.sizeBody) * 1.4;
    return PressScale(
      key: const ValueKey('forum-directory-jump'),
      semanticLabel: '跳到分区 ${labels[widget.index]}',
      onTap: widget.onTap,
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: ClipRect(
                child: SizedBox(
                  height: height,
                  child: AnimatedBuilder(
                    animation: _position,
                    builder: (_, _) => Stack(
                      alignment: Alignment.center,
                      children: [
                        for (var i = 0; i < labels.length; i++)
                          if ((i - _position.value).abs() < 1)
                            Transform.translate(
                              offset: Offset(0, (i - _position.value) * height),
                              child: Text(
                                labels[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.headline.copyWith(
                                  color: color.withValues(
                                    alpha: (1 - (i - _position.value).abs())
                                        .clamp(0.0, 1.0),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Icon(AppIcons.down, size: AppType.sizeSubhead, color: color),
          ],
        ),
      ),
    );
  }
}

class _ForumRow extends StatelessWidget {
  const _ForumRow({required this.forum, required this.categoryName});
  final Forum forum;
  final String categoryName;
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final tint = forumCategoryTint(categoryName, t);
    final raw = forum.lastPostTimeRaw?.trim();
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ';
    final activity = raw?.replaceFirst(today, '今天 ');
    final active = activity?.startsWith('今天 ') ?? false;
    final count = forum.threadCount;
    final countLabel = count == null
        ? null
        : count < 10000
        ? '$count'
        : '${(count / 10000).toStringAsFixed(count % 10000 == 0 ? 0 : 1)}万';
    return PressHighlight(
      key: ValueKey('forum-row-${forum.fid}'),
      borderRadius: BorderRadius.circular(ForumDirectoryTokens.rowRadius),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ForumThreadsPage(fid: forum.fid, title: forum.name),
        ),
      ),
      child: Padding(
        padding: ForumDirectoryTokens.rowPadding,
        child: Row(
          children: [
            Container(
              width: ForumDirectoryTokens.markerSize,
              height: ForumDirectoryTokens.markerSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  tint.withValues(
                    alpha: t.isDark
                        ? ForumDirectoryTokens.markerDarkTintAlpha
                        : ForumDirectoryTokens.markerLightTintAlpha,
                  ),
                  t.surface,
                ),
                borderRadius: BorderRadius.circular(
                  ForumDirectoryTokens.markerRadius,
                ),
              ),
              child: ExcludeSemantics(
                child: Icon(
                  forumIconForName(forum.name),
                  size: ForumDirectoryTokens.markerIconSize,
                  color: t.isDark
                      ? Color.lerp(
                          tint,
                          t.text,
                          ForumDirectoryTokens.markerDarkIconBlend,
                        )
                      : tint,
                ),
              ),
            ),
            const SizedBox(width: ForumDirectoryTokens.rowGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    forum.name,
                    style: ForumDirectoryTokens.name.copyWith(color: t.text),
                  ),
                  if (activity != null && activity.isNotEmpty)
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            activity,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ForumDirectoryTokens.metadata.copyWith(
                              color: active ? t.text2 : t.text3,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (countLabel != null) ...[
              const SizedBox(width: 10),
              Flexible(
                fit: FlexFit.tight,
                child: Text.rich(
                  TextSpan(
                    text: countLabel,
                    style: ForumDirectoryTokens.count.copyWith(color: t.text2),
                    children: [
                      TextSpan(
                        text: ' 主题',
                        style: ForumDirectoryTokens.metadata.copyWith(
                          color: t.text3,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  key: ValueKey('forum-count-${forum.fid}'),
                  textAlign: TextAlign.end,
                  semanticsLabel: '$count 个主题',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
