/// Explicit-only offline layout audit; never sends requests or writes to CHH.
/// flutter test test/ui_visual_audit_test.dart --dart-define=CHH_UI_AUDIT=true
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chh_app/data/message_repository.dart';
import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/pages/forum_threads_page.dart';
import 'package:chh_app/pages/articles_view.dart';
import 'package:chh_app/pages/article_page.dart';
import 'package:chh_app/widgets/image_grid.dart';
import 'package:chh_app/parser/thread_list_parser.dart';
import 'package:chh_app/parser/misc_parser.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/di.dart';
import 'package:chh_app/models/article_discussion.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/article_discussion_page.dart';
import 'package:chh_app/pages/forum_index_view.dart';
import 'package:chh_app/pages/me_page.dart';
import 'package:chh_app/pages/favorites_page.dart';
import 'package:chh_app/pages/my_threads_page.dart';
import 'package:chh_app/pages/user_page.dart';
import 'package:chh_app/pages/settings_page.dart';
import 'package:chh_app/pages/credit_log_page.dart';
import 'package:chh_app/pages/medals_page.dart';
import 'package:chh_app/pages/log_page.dart';
import 'package:chh_app/pages/new_thread_page.dart';
import 'support/space_fixtures.dart';
import 'messages_ui_test.dart' show FakeMessages, pmFixture;
import 'package:chh_app/pages/pm_thread_page.dart';
import 'package:chh_app/pages/messages_page.dart';
import 'package:chh_app/pages/search_page.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/parser/article_comments_parser.dart';
import 'package:chh_app/parser/forum_index_parser.dart';
import 'package:chh_app/parser/search_result_parser.dart';
import 'package:chh_app/parser/thread_parser.dart';
import 'package:chh_app/widgets/app_shell.dart';
import 'package:chh_app/widgets/browse_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _enabled = bool.fromEnvironment('CHH_UI_AUDIT');
const _output = '/tmp/chh-ui-audit';
const _font = 'ChhAuditText';

class _Config {
  final String name;
  final double width;
  final Brightness brightness;
  final double textScale;
  const _Config(this.name, this.width, this.brightness, this.textScale);
}

class _AuditMessages extends MessageRepository {
  _AuditMessages() : super(ChhClient(fetchers: []));
  @override
  Future<Paged<Notice>> notices({
    NoticeView view = NoticeView.all,
    String? type,
    int page = 1,
    bool refresh = false,
  }) async => const Paged(
    page: PageInfo(current: 1, hasNext: false),
    items: [
      Notice(
        id: 'audit-1',
        category: 'post',
        actor: '装机爱好者',
        occurredAtText: '10月26日 10:30',
        summary: '回复了你的装机记录，想了解机箱的风道和噪声表现。',
        tid: 900001,
        pid: 60839951,
      ),
      Notice(
        id: 'audit-2',
        category: 'system',
        occurredAtText: '10月25日 18:20',
        summary: '欢迎参与社区讨论，分享与交流用户体验。',
      ),
    ],
  );
}

class _AuditForums extends ForumRepository {
  _AuditForums() : super(ChhClient(fetchers: []));
  @override
  Future<List<ThreadType>> threadTypes(int fid, {bool refresh = false}) async =>
      parseThreadTypes(_fixture('thread_list_synthetic.html'));
  @override
  Future<ThreadListPage> threadList(
    int fid, {
    int page = 1,
    int? typeid,
    String? filter,
    String? orderby,
    bool refresh = false,
  }) async {
    final source = parseThreadList(_fixture('thread_list_synthetic.html'));
    return ThreadListPage(
      threads: source.threads,
      page: const PageInfo(current: 1, hasNext: false),
    );
  }
}

const _articles = [
  PortalArticle(
    aid: 101,
    title: '把桌面留给创作：一台安静的工作站',
    categoryName: '硬件',
    summary: '从日常使用出发，记录这次装机中的取舍与细节。',
    timeRaw: '2026-10-27',
  ),
  PortalArticle(
    aid: 102,
    title: '周末出发，记录城市的另一面',
    categoryName: '摄影',
    timeRaw: '2026-10-26',
  ),
  PortalArticle(
    aid: 103,
    title: '轻量化设备的日常使用体验',
    categoryName: '分享',
    timeRaw: '2026-10-25',
  ),
];

String _fixture(String file) => File('test_data/$file').readAsStringSync();
List<ContentBlock> _textOnly(List<ContentBlock> content) => [
  for (final block in content)
    switch (block) {
      TextBlock() => TextBlock(block.text),
      QuoteBlock(:final children, :final source) => QuoteBlock(
        _textOnly(children),
        source: source,
      ),
      _ => null,
    },
].whereType<ContentBlock>().toList();

ArticleDiscussion _comments() {
  final source = parseArticleDiscussion(
    _fixture('article_comments_synthetic.html'),
    aid: 50001,
  );
  return ArticleDiscussion(
    aid: source.aid,
    title: source.title,
    total: source.total,
    page: const PageInfo(current: 1, hasNext: false),
    items: [
      for (final c in source.items)
        ArticleComment(
          cid: c.cid,
          author: c.author,
          authorUid: c.authorUid,
          time: c.time,
          timeRaw: c.timeRaw,
          content: _textOnly(c.content),
          text: c.text,
        ),
    ],
  );
}

ThreadDetail _thread() {
  final source = parseThread(_fixture('thread_synthetic.html'), tid: 900001);
  return ThreadDetail(
    tid: source.tid,
    fid: source.fid,
    title: source.title,
    page: const PageInfo(current: 1, hasNext: false),
    posts: [
      for (final p in source.posts.take(3))
        Post(
          pid: p.pid,
          floor: p.floor,
          author: p.author,
          authorUid: p.authorUid,
          timeRaw: p.timeRaw,
          content: _textOnly(p.content),
          notes: p.notes,
          rating: p.rating,
        ),
    ],
  );
}

Widget _tab(AppDestination destination, Widget body) => Builder(
  builder: (context) => Material(
    color: AppTokens.of(context).bg,
    child: Column(
      children: [
        Expanded(
          child: AppShell(
            title: destination.label,
            current: destination,
            body: body,
          ),
        ),
        AppBottomNavigation(current: destination, onNavigate: (_) {}),
      ],
    ),
  ),
);

Widget _screen(String name) => switch (name) {
  'comments' || 'reply' => ArticleDiscussionPage(
    aid: 50001,
    title: '示例硬件评测',
    isLoggedIn: () => true,
    loadPage: (_, _) async => _comments(),
    submitReply: (_, _) async =>
        const PostResult(PostResultKind.failed, '离线验收不发送'),
  ),
  'forums' => _tab(
    AppDestination.forums,
    ForumIndexView(
      loadForums: (_) async =>
          parseForumIndex(_fixture('forum_index_synthetic.html')),
    ),
  ),
  'forum_threads' => ForumThreadsPage(
    fid: 290,
    title: '电脑讨论',
    repository: _AuditForums(),
  ),
  'articles' => BrowseScaffold(
    title: '发现文章',
    body: ArticlesView(
      loadCategories: () async => const [
        PortalCategory(catid: 1, name: '硬件'),
        PortalCategory(catid: 2, name: '摄影'),
      ],
      loadArticles: (_, _, _) async => const Paged(
        items: _articles,
        page: PageInfo(current: 1, hasNext: false),
      ),
    ),
  ),
  'article' => ArticlePage(
    aid: 101,
    title: _articles.first.title,
    loadPage: (_, _) async => ArticleContent(
      ArticleDetail(
        aid: 101,
        title: _articles.first.title,
        metaRaw: '2026-10-27 离线样例',
        content: const [
          TextBlock('从日常使用出发，记录这次装机中的取舍与细节。'),
          TextBlock('机箱的空间安排、散热表现和桌面的使用方式，都影响着日常的创作体验。'),
        ],
        page: const PageInfo(current: 1, hasNext: false),
      ),
    ),
  ),
  'images' => const ImageViewerPage(
    urls: ['https://static.chiphell.com/offline-audit.jpeg'],
  ),
  'search' => SearchPage(
    initialQuery: '4090',
    search: (_) async {
      final source = parseSearchResult(_fixture('search_synthetic.html'));
      return SearchResultPage(
        rows: source.rows,
        page: const PageInfo(current: 1, hasNext: false),
      );
    },
  ),
  'pm' => PmThreadPage(conversation: pmFixture, repository: FakeMessages()),
  'favorites' => FavoritesPage(repository: FixtureSpace()),
  'my_threads' => MyThreadsPage(repository: FixtureSpace()),
  'user' => UserPage(uid: '42', repository: FixtureSpace()),
  'settings' => SettingsPage(repository: FixtureSpace()),
  'credit_log' => CreditLogPage(repository: FixtureSpace()),
  'medals' => MedalsPage(repository: FixtureSpace()),
  'log' => const LogPage(),
  'new_thread' => NewThreadPage(
    fid: 4242,
    forumName: '电脑讨论',
    loadForm: () async => const PostForm(action: '', formhash: 'sample'),
  ),
  'guest' => _tab(AppDestination.me, const MeBody()),
  'messages' => _tab(
    AppDestination.messages,
    MessagesBody(repository: _AuditMessages()),
  ),
  'thread' => ThreadDetailPage(
    tid: 900001,
    title: _thread().title,
    loadPage: (_, _, _) async => _thread(),
  ),
  _ => throw ArgumentError(name),
};

ButtonStyle _fontButton(ButtonStyle? original) {
  final style = original ?? const ButtonStyle();
  return style.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) => (style.textStyle?.resolve(states) ?? const TextStyle())
          .copyWith(fontFamily: _font, fontFamilyFallback: [_font]),
    ),
  );
}

Widget _app(Widget screen, _Config config, GlobalKey boundary) {
  final theme = buildAppTheme(config.brightness);
  return RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: _font),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: _font),
        appBarTheme: theme.appBarTheme.copyWith(
          titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
            fontFamily: _font,
            fontFamilyFallback: [_font],
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: _fontButton(theme.textButtonTheme.style),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: _fontButton(theme.outlinedButtonTheme.style),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: _fontButton(theme.filledButtonTheme.style),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: _fontButton(theme.segmentedButtonTheme.style),
        ),
        chipTheme: theme.chipTheme.copyWith(
          labelStyle: theme.chipTheme.labelStyle?.copyWith(fontFamily: _font),
          secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
            fontFamily: _font,
          ),
        ),
      ),
      home: screen,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(config.textScale),
          padding: const EdgeInsets.only(top: 24, bottom: 20),
          viewPadding: const EdgeInsets.only(top: 24, bottom: 20),
          disableAnimations: true,
        ),
        child: child!,
      ),
    ),
  );
}

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final candidates = <String>[
    if (Platform.environment['CHH_CAPTURE_CJK_FONT'] case final String path)
      path,
    '/System/Library/Fonts/STHeiti Medium.ttc',
    '/System/Library/Fonts/PingFang.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansSC-Regular.ttf',
  ];
  final cjk = candidates
      .map(File.new)
      .where((file) => file.existsSync())
      .firstOrNull;
  if (cjk == null) {
    throw StateError(
      'Set CHH_CAPTURE_CJK_FONT to a Chinese font before capturing.',
    );
  }
  await (FontLoader(
    _font,
  )..addFont(cjk.readAsBytes().then(ByteData.sublistView))).load();
  // Controls with an explicit TextStyle but no family use Flutter's default
  // test family. Override that family too, so those labels remain readable.
  await (FontLoader(
    'Ahem',
  )..addFont(cjk.readAsBytes().then(ByteData.sublistView))).load();
  await (FontLoader(
    'Roboto',
  )..addFont(cjk.readAsBytes().then(ByteData.sublistView))).load();

  final configFile = File('.dart_tool/package_config.json');
  final packages =
      (jsonDecode(await configFile.readAsString()) as Map)['packages'] as List;
  Uri packageRoot(String name) {
    final package = packages.cast<Map>().firstWhere((p) => p['name'] == name);
    return Directory.fromUri(
      configFile.absolute.uri.resolve(package['rootUri'] as String),
    ).uri;
  }

  final solar = File.fromUri(
    packageRoot('solar_icons').resolve('fonts/SolarIcons.ttf'),
  );
  await (FontLoader(
    'packages/solar_icons/SolarIcons',
  )..addFont(solar.readAsBytes().then(ByteData.sublistView))).load();

  final material = File.fromUri(
    packageRoot('flutter').resolve(
      '../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ),
  );
  await (FontLoader(
    'MaterialIcons',
  )..addFont(material.readAsBytes().then(ByteData.sublistView))).load();
  {
    final font = File.fromUri(
      packageRoot('cupertino_icons').resolve('assets/CupertinoIcons.ttf'),
    );
    if (font.existsSync()) {
      await (FontLoader(
        'packages/cupertino_icons/CupertinoIcons',
      )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
    }
  }
  _fontsLoaded = true;
}

// Flutter tests otherwise force Ahem on component-owned TextStyles (for example
// a TextButton's explicit style). Replace only the audit render-tree font with
// the locally loaded system face; application source and icon fonts stay intact.
InlineSpan _auditSpan(InlineSpan span) {
  if (span is! TextSpan) return span;
  final style = span.style ?? const TextStyle();
  final isIcon = style.fontFamily?.contains('Icons') ?? false;
  return TextSpan(
    text: span.text,
    children: span.children?.map(_auditSpan).toList(),
    style: isIcon
        ? style
        : style.copyWith(fontFamily: _font, fontFamilyFallback: [_font]),
    recognizer: span.recognizer,
    semanticsLabel: span.semanticsLabel,
    locale: span.locale,
    spellOut: span.spellOut,
  );
}

void _auditTypography(RenderObject object) {
  if (object is RenderParagraph) object.text = _auditSpan(object.text);
  object.visitChildren(_auditTypography);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'explicit offline screenshot and narrow dark large-type audit',
    (tester) async {
      await tester.runAsync(_loadFonts);
      final oldLogged = chhSession.loggedIn;
      chhSession.loggedIn = false;
      addTearDown(() => chhSession.loggedIn = oldLogged);
      final originalErrors = FlutterError.onError;
      final issues = <Map<String, Object?>>[];
      final manifest = <Map<String, Object?>>[];
      String current = '';
      FlutterError.onError = (details) {
        issues.add({'screen': current, 'error': details.exceptionAsString()});
        originalErrors?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalErrors);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const configs = [
        _Config('390-light', 390, Brightness.light, 1),
        _Config('390-dark-large', 390, Brightness.dark, 1.6),
        _Config('320-dark-large', 320, Brightness.dark, 2),
      ];
      for (final config in configs) {
        tester.view.physicalSize = Size(config.width, 844);
        for (final name in [
          'comments',
          'reply',
          'forums',
          'forum_threads',
          'articles',
          'article',
          'images',
          'search',
          'guest',
          'pm',
          'favorites',
          'my_threads',
          'user',
          'settings',
          'credit_log',
          'medals',
          'log',
          'new_thread',
          'messages',
          'thread',
        ]) {
          current = '${config.name}-$name';
          final key = GlobalKey();
          await tester.pumpWidget(_app(_screen(name), config, key));
          await tester.pumpAndSettle();
          if (name == 'reply') {
            await tester.tap(find.text('回复').first);
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byType(TextField),
              '接口配置很实用，想了解日常创作时的使用体验。',
            );
            await tester.pumpAndSettle();
          }
          await tester.pump(const Duration(milliseconds: 30));
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          _auditTypography(boundary);
          await tester.pump();
          final path = '$_output/$current.png';
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(path).parent.create(recursive: true);
            await File(path).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
          manifest.add({
            'screen': name,
            'config': config.name,
            'width': config.width,
            'height': 844,
            'textScale': config.textScale,
            'path': path,
            'mode': 'offline fixture rendering, not a device screenshot',
          });
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
      await tester.runAsync(() async {
        final out = Directory(_output);
        await out.create(recursive: true);
        await File(
          '$_output/manifest.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
        await File(
          '$_output/issues.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(issues));
      });
      FlutterError.onError = originalErrors;
      expect(
        issues,
        isEmpty,
        reason: 'See $_output/issues.json and per-screen PNGs.',
      );
    },
    skip: !_enabled,
  );
}
