/// Explicit, offline review surface. No source repository is invoked here.
library;

import 'package:flutter/material.dart';
import '../ui/press.dart';
import '../ui/app_button.dart';
import '../design/typography.dart';
import '../ui/feedback.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoThemeData, CupertinoTextThemeData;
import 'package:solar_icons/solar_icons.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../models/article_discussion.dart';
import '../models/models.dart';
import '../widgets/article_reply_sheet.dart';
import '../widgets/composer_sheet.dart';
import 'article_discussion_page.dart';
import 'search_page.dart';

class InteractionReviewApp extends StatefulWidget {
  final bool initialDark;
  final double? textScale;

  /// Screenshot-only font substitution; device review uses the normal system font.
  final String? fontFamilyOverride;
  const InteractionReviewApp({
    super.key,
    this.initialDark = false,
    this.textScale,
    this.fontFamilyOverride,
  });

  @override
  State<InteractionReviewApp> createState() => _InteractionReviewAppState();
}

class _InteractionReviewAppState extends State<InteractionReviewApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late bool _dark = widget.initialDark;
  bool _longList = false;
  String _keyword = '装机';
  final _sentComments = <ArticleComment>[];

  ThemeData _theme(Brightness brightness) {
    final base = buildAppTheme(brightness);
    final family = widget.fontFamilyOverride;
    if (family == null) return base;
    ButtonStyle buttons(ButtonStyle? style) =>
        (style ?? const ButtonStyle()).copyWith(
          textStyle: WidgetStateProperty.resolveWith(
            (states) =>
                (style?.textStyle?.resolve(states) ??
                        const TextStyle(fontSize: AppType.sizeFootnote))
                    .copyWith(fontFamily: family),
          ),
        );
    return base.copyWith(
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        textTheme: CupertinoTextThemeData(
          textStyle: TextStyle(fontFamily: family, fontSize: AppType.sizeBody),
          actionTextStyle: TextStyle(
            fontFamily: family,
            fontSize: AppType.sizeBody,
          ),
          navActionTextStyle: TextStyle(
            fontFamily: family,
            fontSize: AppType.sizeBody,
          ),
        ),
      ),
      textTheme: base.textTheme.apply(fontFamily: family),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: family,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: buttons(base.textButtonTheme.style),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: buttons(base.filledButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttons(base.outlinedButtonTheme.style),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: buttons(base.elevatedButtonTheme.style),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: base.inputDecorationTheme.hintStyle?.copyWith(
          fontFamily: family,
        ),
        labelStyle: base.inputDecorationTheme.labelStyle?.copyWith(
          fontFamily: family,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    title: 'CHH 交互样板',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) {
      final media = MediaQuery.of(context);
      final t = AppTokens.of(context);
      return MediaQuery(
        data: media.copyWith(
          textScaler: widget.textScale == null
              ? media.textScaler
              : TextScaler.linear(widget.textScale!),
        ),
        child: Column(
          children: [
            Material(
              color: t.accentFill,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 3, 8, 3),
                  child: Row(
                    children: [
                      Icon(
                        SolarIconsBold.shieldCheck,
                        size: 18,
                        color: t.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '交互样板，示例数据',
                          style: TextStyle(
                            fontSize: AppType.sizeFootnote,
                            fontWeight: FontWeight.w600,
                            color: t.accent,
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: _dark ? '切换浅色样板' : '切换深色样板',
                        child: IconButton(
                          key: const ValueKey('review-theme'),
                          onPressed: () => setState(() => _dark = !_dark),
                          icon: Icon(
                            _dark ? SolarIconsBold.sun : SolarIconsBold.moon,
                            size: 23,
                            color: t.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    padding: media.padding.copyWith(top: 0),
                    viewPadding: media.viewPadding.copyWith(top: 0),
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      );
    },
    home: _ReviewHome(
      longList: _longList,
      onLongList: (value) => setState(() => _longList = value),
      onSearch: () => _navigator.currentState!.push(
        MaterialPageRoute(
          builder: (context) => SearchPage(
            search: (keyword) async {
              _keyword = keyword;
              await Future<void>.delayed(const Duration(milliseconds: 450));
              return _searchPage(1);
            },
            searchNext: (previous) async {
              await Future<void>.delayed(const Duration(milliseconds: 450));
              return _searchPage(previous.page.current + 1);
            },
            onOpenThread: (thread) => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _ReviewResultPreview(thread: thread),
              ),
            ),
          ),
        ),
      ),
      onDiscussion: () => ArticleDiscussionPage.show(
        _navigator.currentContext!,
        aid: 70001,
        title: '示例文章：安静桌面的散热与布局',
        isLoggedIn: () => true,
        onLogin: (_) async {},
        loadPage: (page, refresh) async {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          return _commentsPage(page);
        },
        submitReply: (message, target) async {
          await Future<void>.delayed(const Duration(milliseconds: 1100));
          _sentComments.insert(
            0,
            ArticleComment(
              cid: 70900 + _sentComments.length,
              author: '示例用户（你）',
              timeRaw: '刚刚',
              text: message,
              content: [
                if (target != null)
                  QuoteBlock([TextBlock(target.text)], source: target.author),
                TextBlock(message),
              ],
            ),
          );
          return const PostResult(PostResultKind.success, '示例评论已发送');
        },
      ),
      onReply: () => _navigator.currentState!.push(
        MaterialPageRoute(builder: (_) => const _ReplyReviewPage()),
      ),
    ),
  );

  SearchResultPage _searchPage(int page) {
    final count = _longList ? 20 : 4;
    final start = (page - 1) * 4;
    final end = (start + 4).clamp(0, count);
    final rows = <ThreadSummary>[];
    for (var i = start; i < end; i++) {
      final titles = ['的安静桌面方案', '与散热，整理几条使用感受', '搭配清单与空间利用', '记录：从想法到完成'];
      rows.add(
        ThreadSummary(
          tid: 70100 + i,
          title:
              '示例：$_keyword${titles[i % titles.length]}${i >= 4 ? ' ${i + 1}' : ''}',
          author: '示例用户${String.fromCharCode(65 + i % 4)}',
          replies: 6 + i * 3,
          views: 120 + i * 37,
          forumName: i.isEven ? '示例装机版块' : '示例桌面版块',
          forumFid: 700,
          createdAt: DateTime(2026, 10, 26, 10, 30),
          snippet: '这是一段$_keyword搜索结果的示例摘要，用于检查关键词、信息层级和长标题的排版。',
        ),
      );
    }
    return SearchResultPage(
      rows: rows,
      page: PageInfo(current: page, hasNext: end < count),
      nextUrl: end < count ? 'review://search?page=${page + 1}' : null,
    );
  }

  ArticleDiscussion _commentsPage(int page) {
    final count = _longList ? 20 : 4;
    final all = <ArticleComment>[
      ..._sentComments,
      for (var i = 0; i < count; i++)
        ArticleComment(
          cid: 70200 + i,
          author: '示例用户${String.fromCharCode(65 + i % 4)}',
          timeRaw: '${10 + i ~/ 4}:${(24 + i).toString().padLeft(2, '0')}',
          text: const [
            '把散热器和进风路径一起考虑，这样的桌面布局看起来更完整。',
            '我比较关心低负载时的噪声，期待看到风扇策略的更多细节。',
            '引用上下文放在回复旁边，继续阅读时更容易知道大家在讨论什么。',
            '感谢分享。小空间里保留走线余量，也是值得关注的细节。',
          ][i % 4],
          content: [
            if (i == 0)
              const QuoteBlock([
                TextBlock(
                  '示例引用：在桌面空间有限的情况下，先确认机箱的进风方向、风扇转速与显示器位置，再决定配件的摆放。完整上下文会帮助读者理解这一条回复。',
                ),
              ], source: '示例用户A'),
            TextBlock(
              const [
                '把散热器和进风路径一起考虑，这样的桌面布局看起来更完整。',
                '我比较关心低负载时的噪声，期待看到风扇策略的更多细节。',
                '引用上下文放在回复旁边，继续阅读时更容易知道大家在讨论什么。',
                '感谢分享。小空间里保留走线余量，也是值得关注的细节。',
              ][i % 4],
            ),
          ],
        ),
    ];
    final start = (page - 1) * 4;
    final end = (start + 4).clamp(0, all.length);
    return ArticleDiscussion(
      aid: 70001,
      title: '示例文章：安静桌面的散热与布局',
      items: start >= all.length ? const [] : all.sublist(start, end),
      page: PageInfo(current: page, hasNext: end < all.length),
      total: all.length,
    );
  }
}

class _ReviewHome extends StatelessWidget {
  final bool longList;
  final ValueChanged<bool> onLongList;
  final VoidCallback onSearch;
  final VoidCallback onDiscussion;
  final VoidCallback onReply;
  const _ReviewHome({
    required this.longList,
    required this.onLongList,
    required this.onSearch,
    required this.onDiscussion,
    required this.onReply,
  });
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('交互预览')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            '从触碰，到回应',
            style: TextStyle(
              fontSize: AppType.sizeLargeTitle,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: t.text,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '选择一组，体验真实控件的布局与反馈。',
            style: TextStyle(
              fontSize: AppType.sizeBody,
              height: 1.6,
              color: t.text2,
            ),
          ),
          const SizedBox(height: 26),
          _ReviewEntry(
            key: const ValueKey('review-search'),
            icon: SolarIconsBold.magnifier,
            title: '搜索',
            detail: '建议词、结果列表与继续加载',
            onTap: onSearch,
          ),
          _ReviewEntry(
            key: const ValueKey('review-discussion'),
            icon: SolarIconsBold.chatRoundDots,
            title: '文章评论',
            detail: '上下文、引用展开与就地回复',
            onTap: onDiscussion,
          ),
          _ReviewEntry(
            key: const ValueKey('review-reply'),
            icon: SolarIconsBold.penNewRound,
            title: '回复编辑',
            detail: '拖拽面板、引用与发送反馈',
            onTap: onReply,
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            key: const ValueKey('review-long-list'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text(
              '长列表样本',
              style: TextStyle(fontSize: AppType.sizeBody),
            ),
            subtitle: Text(
              longList ? '20 条示例数据' : '4 条示例数据',
              style: const TextStyle(fontSize: AppType.sizeFootnote),
            ),
            value: longList,
            onChanged: onLongList,
          ),
        ],
      ),
    );
  }
}

class _ReviewEntry extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  const _ReviewEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(color: t.separator, width: AppSpace.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: PressHighlight(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: t.accent, size: 27),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: AppType.sizeTitle2,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: AppType.sizeFootnote,
                          height: 1.6,
                          color: t.text2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Icon(SolarIconsBold.altArrowRight, color: t.text3, size: 19),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewResultPreview extends StatelessWidget {
  final ThreadSummary thread;
  const _ReviewResultPreview({required this.thread});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('结果预览')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            thread.title,
            style: const TextStyle(
              fontSize: AppType.sizeTitle2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '此处展示本地示例，未连接帖子正文。',
            style: TextStyle(fontSize: AppType.sizeBody, height: 1.6),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: '返回搜索',
            variant: AppButtonVariant.plain,
            icon: SolarIconsBold.altArrowLeft,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    ),
  );
}

class _ReplyReviewPage extends StatefulWidget {
  const _ReplyReviewPage();
  @override
  State<_ReplyReviewPage> createState() => _ReplyReviewPageState();
}

class _ReplyReviewPageState extends State<_ReplyReviewPage> {
  bool _fail = false;
  String _draft = '这是一条示例回复。修改文字，再体验发送反馈。';
  Future<PostResult> _submit(String _) async {
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    return _fail
        ? const PostResult(PostResultKind.failed, '示例发送失败，输入内容已保留')
        : const PostResult(PostResultKind.success, '示例回复已发送');
  }

  Future<void> _postReply() async {
    final result = await ComposerSheet.show(
      context,
      initialText: _draft,
      quoteOf: '示例用户A #12',
      onDraftChanged: (value) => _draft = value,
      onSubmit: _submit,
    );
    if (mounted && result?.isSuccess == true) {
      AppToast.show(context, '示例回复已发送');
    }
  }

  Future<void> _articleReply() async {
    await ArticleReplySheet.show(
      context,
      initialText: '示例评论：这个散热布局很有启发。',
      quoteAuthor: '示例用户B',
      quoteText: '示例引用：我比较关心低负载时的噪声，以及风扇策略。',
      onSubmit: _submit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('回复编辑')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _ReviewEntry(
            key: const ValueKey('review-open-post-reply'),
            icon: SolarIconsBold.penNewRound,
            title: '帖子回复',
            detail: '编辑画布与引用上下文',
            onTap: _postReply,
          ),
          _ReviewEntry(
            key: const ValueKey('review-open-article-reply'),
            icon: SolarIconsBold.chatRoundDots,
            title: '评论回复',
            detail: '相同的编辑与发送手感',
            onTap: _articleReply,
          ),
          SwitchListTile.adaptive(
            key: const ValueKey('review-failure'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(
              '模拟发送失败',
              style: TextStyle(fontSize: AppType.sizeBody, color: t.text),
            ),
            value: _fail,
            onChanged: (value) => setState(() => _fail = value),
          ),
        ],
      ),
    );
  }
}
