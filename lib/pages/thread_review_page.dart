/// Offline review of the actual threaded forum reader and reply sheets.
library;

import 'package:flutter/material.dart';
import '../design/typography.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoThemeData, CupertinoTextThemeData;
import 'package:solar_icons/solar_icons.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../models/models.dart';
import 'thread_detail_page.dart';

class ThreadReviewApp extends StatefulWidget {
  final bool initialDark;
  final double? textScale;
  final String? fontFamilyOverride;

  /// Optional local fixture access for explicit offline interaction checks.
  final ThreadReviewData? data;
  const ThreadReviewApp({
    super.key,
    this.initialDark = false,
    this.textScale,
    this.fontFamilyOverride,
    this.data,
  });
  @override
  State<ThreadReviewApp> createState() => _ThreadReviewAppState();
}

class _ThreadReviewAppState extends State<ThreadReviewApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late bool _dark = widget.initialDark;
  late final _data = widget.data ?? ThreadReviewData();
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
      snackBarTheme: base.snackBarTheme.copyWith(
        contentTextStyle:
            (base.snackBarTheme.contentTextStyle ?? base.textTheme.bodyMedium)
                ?.copyWith(fontFamily: family),
      ),
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
    title: 'CHH 论坛交互样板',
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
                          key: const ValueKey('thread-review-theme'),
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
    home: ThreadDetailPage(
      tid: ThreadReviewData.tid,
      fid: ThreadReviewData.fid,
      title: ThreadReviewData.title,
      initialThreaded: true,
      loadPage: _data.loadPage,
      loadGoto: _data.loadGoto,
      submitReply: _data.submitReply,
    ),
  );
}

class ThreadReviewSubmission {
  final int tid;
  final int fid;
  final String message;
  final int? quotePid;
  final int page;
  const ThreadReviewSubmission({
    required this.tid,
    required this.fid,
    required this.message,
    this.quotePid,
    required this.page,
  });
}

/// Two deterministic pages. Every ID, author, body and response is an example.
/// Reads are immediate local futures; only the default submit simulates latency.
class ThreadReviewData {
  static const tid = 99001;
  static const fid = 990;
  static const title = '示例：一张安静桌面的搭建记录';
  static const missingPid = 99999;
  final reads = <({int page, String? author, bool refresh})>[];
  final gotos = <int>[];
  final submissions = <ThreadReviewSubmission>[];
  final Future<PostResult> Function(ThreadReviewSubmission submission)?
  submitResponse;
  ThreadReviewData({this.submitResponse});

  static String referenceUrl(int pid) => 'review://thread/$tid?pid=$pid';
  static PostReference reference(int pid) =>
      PostReference(tid: tid, pid: pid, url: referenceUrl(pid));

  static Post _post(
    int floor,
    String author,
    String uid,
    List<ContentBlock> content,
  ) => Post(
    pid: 99000 + floor,
    floor: floor,
    author: author,
    authorUid: uid,
    timeRaw: '10:${(20 + floor).toString().padLeft(2, '0')}',
    content: content,
  );

  List<Post> get _first => [
    _post(1, '示例楼主', 'review-owner', const [
      TextBlock('从桌面空间开始，慢慢搭一套适合自己的日常配置。'),
      TextBlock('这份示例围绕空间、走线和使用感受展开。先让最常用的物品留在顺手的位置，再给进风与维护留出余量。'),
      TextBlock('正文和下面的讨论都使用本地数据。你可以展开回复、回到原楼层，或打开编辑器体验发送反馈。'),
    ]),
    _post(2, '示例楼主', 'review-owner', const [
      TextBlock('楼主续篇：补充一点桌面走线的考虑。电源与数据线分开整理，方便之后移动配件和清洁。'),
    ]),
    _post(3, '示例用户A', 'review-a', const [TextBlock('我会先确认进风方向，再决定桌面配件的位置。')]),
    _post(4, '示例用户B', 'review-b', [
      QuoteBlock(
        const [TextBlock('A 的示例历史引用。')],
        source: '示例用户A',
        reference: reference(99003),
      ),
      const TextBlock('赞同，也可以把低负载时的风扇转速一起考虑。'),
    ]),
    _post(5, '示例用户C', 'review-c', [
      QuoteBlock(
        const [TextBlock('B 的示例历史引用。')],
        source: '示例用户B',
        reference: reference(99004),
      ),
      const TextBlock('如果把风扇曲线一并记录下来，之后调整会更容易比较。'),
    ]),
    _post(6, '示例用户D', 'review-d', const [
      QuoteBlock([TextBlock('这段引用只有文字，没有可定位的 PID。')], source: '无定位信息的示例引用'),
      TextBlock('这一条保持为独立评论，不根据文字猜测回复对象。'),
    ]),
    _post(7, '示例用户E', 'review-e', [
      QuoteBlock(
        const [TextBlock('首楼的示例历史引用。')],
        source: '示例楼主',
        reference: reference(99001),
      ),
      const TextBlock('引用首楼讨论桌面布局，这仍是一条一级评论。'),
    ]),
    _post(8, '示例用户F', 'review-f', const [TextBlock('预留一点维护空间，比把桌面塞满更方便日常使用。')]),
    _post(9, '示例用户G', 'review-g', [
      QuoteBlock(
        const [TextBlock('这个目标没有提供在本地样本中。')],
        source: '缺失楼层的示例引用',
        reference: reference(missingPid),
      ),
      const TextBlock('缺失引用会明确提示，不会用历史文字冒充当前楼层。'),
    ]),
  ];

  List<Post> get _second => [
    _post(10, '示例用户H', 'review-h', [
      QuoteBlock(
        const [TextBlock('跨页引用 A。')],
        source: '示例用户A',
        reference: reference(99003),
      ),
      const TextBlock('后续页也补充一条：机箱侧面的空间最好一起检查。'),
    ]),
    _post(11, '示例用户I', 'review-i', [
      QuoteBlock(
        const [TextBlock('跨页引用 C。')],
        source: '示例用户C',
        reference: reference(99005),
      ),
      const TextBlock('同一组里继续回应 C，保持原来的讨论上下文。'),
    ]),
    _post(12, '示例用户J', 'review-j', const [
      TextBlock('另一条独立建议：先确定显示器位置，再安排其他配件。'),
    ]),
    _post(13, '示例用户K', 'review-k', [
      QuoteBlock(
        const [TextBlock('引用新根评论 J。')],
        source: '示例用户J',
        reference: reference(99012),
      ),
      const TextBlock('这一点对双屏桌面也很有帮助。'),
    ]),
    _post(14, '示例楼主', 'review-owner', const [
      TextBlock('楼主续篇：补上后续调整的思路。示例记录到这里，感谢参与讨论。'),
    ]),
  ];

  Future<ThreadDetail> loadPage(
    int page,
    String? authorUid,
    bool refresh,
  ) async {
    reads.add((page: page, author: authorUid, refresh: refresh));
    return _page(page, authorUid);
  }

  ThreadDetail _page(int page, String? authorUid) {
    if (page != 1 && page != 2) {
      throw const PageMessage(PageMessageKind.message, '示例数据只提供两页');
    }
    final posts = page == 1 ? _first : _second;
    return ThreadDetail(
      tid: tid,
      fid: fid,
      title: title,
      posts: authorUid == null
          ? posts
          : posts.where((p) => p.authorUid == authorUid).toList(),
      page: PageInfo(current: page, hasNext: page == 1),
    );
  }

  Future<ThreadDetail> loadGoto(String url) async {
    final uri = Uri.parse(url);
    final pid =
        int.tryParse(uri.queryParameters['pid'] ?? '') ??
        int.tryParse(
          RegExp(r'pid(\d+)').firstMatch(uri.fragment)?.group(1) ?? '',
        );
    if (pid == null) {
      throw const PageMessage(PageMessageKind.message, '示例引用没有可定位的 PID');
    }
    gotos.add(pid);
    if (pid == missingPid) {
      throw const PageMessage(PageMessageKind.message, '此引用楼层未提供在示例数据中');
    }
    if (_first.any((p) => p.pid == pid)) return _page(1, null);
    if (_second.any((p) => p.pid == pid)) return _page(2, null);
    throw const PageMessage(PageMessageKind.message, '此引用楼层未提供在示例数据中');
  }

  Future<PostResult> submitReply({
    required int tid,
    required int fid,
    required String message,
    int? quotePid,
    int page = 1,
  }) async {
    final submission = ThreadReviewSubmission(
      tid: tid,
      fid: fid,
      message: message,
      quotePid: quotePid,
      page: page,
    );
    submissions.add(submission);
    if (submitResponse != null) return submitResponse!(submission);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return const PostResult(PostResultKind.success, '示例发送完成');
  }
}
