/// 数据模型:解析器的输出、UI 层的输入
library;

import '../core/link_target.dart';

// ---------- 版块 ----------

class Forum {
  final int fid;
  final String name;
  final int? threadCount;
  final int? postCount;
  final String? lastPostTimeRaw;

  const Forum({
    required this.fid,
    required this.name,
    this.threadCount,
    this.postCount,
    this.lastPostTimeRaw,
  });
}

class ForumCategory {
  final String name;
  final List<Forum> forums;

  const ForumCategory({required this.name, required this.forums});
}

// ---------- 帖子列表 ----------

class ThreadSummary {
  final int tid;
  final String title;

  /// 分类标签,如 [ITX]
  final String? typeName;
  final String author;
  final DateTime? createdAt;
  final int replies;
  final int views;
  final String? lastPostUser;
  final String? lastPostTimeRaw;
  final bool hasImages;
  final bool sticky;

  /// guide / 搜索结果里带的所属版块
  final String? forumName;
  final int? forumFid;

  /// 搜索结果摘要
  final String? snippet;

  const ThreadSummary({
    required this.tid,
    required this.title,
    this.typeName,
    required this.author,
    this.createdAt,
    required this.replies,
    required this.views,
    this.lastPostUser,
    this.lastPostTimeRaw,
    this.hasImages = false,
    this.sticky = false,
    this.forumName,
    this.forumFid,
    this.snippet,
  });
}

class PageInfo {
  final int current;
  final bool hasNext;

  const PageInfo({required this.current, required this.hasNext});
}

class ThreadListPage {
  final List<ThreadSummary> threads;
  final PageInfo page;

  const ThreadListPage({required this.threads, required this.page});
}

/// 搜索结果页(结构类似,但带摘要与翻页 URL)
class SearchResultPage {
  final List<ThreadSummary> rows;
  final PageInfo page;

  /// 下一页绝对地址(无则为 null)
  final String? nextUrl;

  const SearchResultPage({
    required this.rows,
    required this.page,
    this.nextUrl,
  });
}

// ---------- 帖子详情(楼层) ----------

/// 正文内容块:纯文本 / 图片 / 引用 / 站内链接卡片 / B 站视频
sealed class ContentBlock {
  const ContentBlock();
}

/// 正文里的内联片段
sealed class InlineNode {
  const InlineNode();
}

class InlineText extends InlineNode {
  final String text;
  const InlineText(this.text);
}

/// 论坛自带表情。站点用 smilieid 属性标记,路径在 static/image/smiley 下。
class InlineSmiley extends InlineNode {
  final String url;
  const InlineSmiley(this.url);
}

/// 留在句子里的可点链接:站外链接与本站的其他页面。
/// 帖子、文章、视频链接不走这里,它们变成段落后的卡片。
class InlineLink extends InlineNode {
  final String text;
  final LinkTarget target;
  const InlineLink(this.text, this.target);
}

class TextBlock extends ContentBlock {
  /// 纯文本形态。表情不计入,便于搜索与摘要。
  final String text;

  /// 含表情或链接时的内联序列。为空表示这段只有文字,直接用 [text] 渲染即可。
  final List<InlineNode> nodes;

  const TextBlock(this.text, {this.nodes = const []});

  bool get hasInline => nodes.isNotEmpty;
}

class ImageBlock extends ContentBlock {
  final String url;
  const ImageBlock(this.url);
}

/// 站内帖子或文章链接,显示成卡片;标题与时间由卡片自己读取
class SiteLinkBlock extends ContentBlock {
  /// [ThreadLink] 或 [ArticleLink]
  final LinkTarget target;

  /// 原链接文字;文字就是网址时为空。卡片取不到标题时用它兜底。
  final String label;

  const SiteLinkBlock(this.target, {this.label = ''});
}

/// B 站视频,显示成可点开播放的卡片
class BilibiliBlock extends ContentBlock {
  final BilibiliVideo video;
  const BilibiliBlock(this.video);
}

/// 正文声称引用的原帖地址；不是服务端认证的父子关系。
class PostReference {
  final int tid;
  final int pid;
  final String url;

  const PostReference({
    required this.tid,
    required this.pid,
    required this.url,
  });
}

class QuoteBlock extends ContentBlock {
  /// 引用者签名,如 "xxx 发表于 2026-10-19 14:41"
  final String? source;
  final List<ContentBlock> children;
  final PostReference? reference;

  /// 站点拦截提示复用引用样式，但不能参与回复关联或随引文折叠。
  final bool isNotice;

  const QuoteBlock(
    this.children, {
    this.source,
    this.reference,
    this.isNotice = false,
  });
}

class PostLock {
  final String text;
  final bool needsPassword;

  const PostLock({required this.text, required this.needsPassword});
}

class Post {
  final int pid;
  final int floor;

  /// false 时 [floor] 只是本页显示序号，不能用来判断首楼或导航。
  final bool floorIsKnown;
  final String author;
  final String? authorUid;
  final String? avatarUrl;
  final String timeRaw;
  final DateTime? time;
  final List<ContentBlock> content;
  final PostLock? lock;

  /// 编辑说明与补充内容,从正文里摘出来单独展示
  final List<PostNote> notes;

  /// 评分汇总,没有评分时为 null
  final PostRating? rating;

  /// 点评
  final List<PostComment> comments;

  const Post({
    required this.pid,
    required this.floor,
    this.floorIsKnown = true,
    required this.author,
    this.authorUid,
    this.avatarUrl,
    required this.timeRaw,
    this.time,
    required this.content,
    this.lock,
    this.notes = const [],
    this.rating,
    this.comments = const [],
  });
}

class ThreadDetail {
  final int tid;
  final String? cookiePrefix;

  /// 详情页自己的回复表单或面包屑给出的所属版块。
  /// 门户、搜索、提醒等入口未必提前知道 fid。
  final int? fid;

  /// 所属版块名,取自面包屑最深的一级;游客或特殊入口读不到时为 null
  final String? forumName;
  final String title;
  final List<Post> posts;
  final PageInfo page;

  const ThreadDetail({
    required this.tid,
    this.cookiePrefix,
    this.fid,
    this.forumName,
    required this.title,
    required this.posts,
    required this.page,
  });
}

// ---------- 通用:站点消息页与分页包装 ----------

/// 站点「提示信息」页的语义分类(PAGE_SPEC §二.3)
///
/// 标题含「提示信息」或存在 #messagetext 只能判定为消息页,不能直接判为掉线,
/// 必须结合正文与 #messagelogin 分流。
enum PageMessageKind {
  forumPassword,
  loginRequired,
  permissionDenied,
  featureUnavailable,
  message,
}

class PageMessage implements Exception {
  final PageMessageKind kind;
  final String text;

  final int? fid;

  const PageMessage(this.kind, this.text, {this.fid});

  bool get isLoginWall => kind == PageMessageKind.loginRequired;

  @override
  String toString() => 'PageMessage(${kind.name}): $text';
}

/// 分页列表的通用包装:列表页、提醒、私信、收藏等共用
class Paged<T> {
  final List<T> items;
  final PageInfo page;

  /// 站点给出的下一页完整地址。个人页与提醒页只给「下一页」链接,
  /// 必须沿用它而不是自己拼参数(PAGE_SPEC §6.1)。
  final String? nextUrl;

  const Paged({required this.items, required this.page, this.nextUrl});

  bool get isEmpty => items.isEmpty;

  static Paged<T> empty<T>() => Paged<T>(
    items: const [],
    page: const PageInfo(current: 1, hasNext: false),
  );
}

// ---------- 版块分类筛选 ----------

class ThreadType {
  final int typeid;
  final String name;
  final bool active;

  const ThreadType({
    required this.typeid,
    required this.name,
    this.active = false,
  });
}

// ---------- 门户 ----------

/// 条目指向的对象类型。收藏页按目标 URL 判定时要用。
enum PortalItemKind { article, thread }

/// 门户条目打开后的实际内容
///
/// 站点上相当一部分「文章」会跳转到论坛帖(article-35544 → thread-2910638),
/// 一律按文章解析就会得到空白页。
sealed class PortalContent {
  const PortalContent();
}

class ArticleContent extends PortalContent {
  final ArticleDetail detail;
  const ArticleContent(this.detail);
}

class ThreadContent extends PortalContent {
  final int tid;
  final String title;
  const ThreadContent(this.tid, this.title);
}

class ArticleDetail {
  final int aid;
  final String title;
  final String? metaRaw;

  /// 所属栏目名,取自面包屑最深的一级
  final String? categoryName;
  final List<ContentBlock> content;
  final PageInfo page;

  const ArticleDetail({
    required this.aid,
    required this.title,
    this.metaRaw,
    this.categoryName,
    required this.content,
    required this.page,
  });
}

// ---------- 用户主页 ----------

class UserProfile {
  final String uid;
  final String name;
  final String? avatarUrl;
  final String? group;
  final int? groupId;
  final int? nextLevelCredits;
  final int? onlineHours;
  final int? credits;
  final int? evil;
  final int? threads;
  final int? replies;
  final int? friends;
  final String? registeredAt;
  final String? lastVisitAt;
  final String? lastPostAt;
  final int? portalArticles;

  /// 资料区的键值对,按页面实际字段保留,不补造
  final Map<String, String> profile;

  /// 积分 / 主题 / 回帖等统计
  final Map<String, String> stats;

  const UserProfile({
    required this.uid,
    required this.name,
    this.avatarUrl,
    this.group,
    this.groupId,
    this.nextLevelCredits,
    this.onlineHours,
    this.credits,
    this.evil,
    this.threads,
    this.replies,
    this.friends,
    this.registeredAt,
    this.lastVisitAt,
    this.lastPostAt,
    this.portalArticles,
    this.profile = const {},
    this.stats = const {},
  });
}

// ---------- 提醒 ----------

/// 提醒分组:对应侧栏 view=mypost / interactive / system / app
enum NoticeView { all, mypost, interactive, system, app }

class Notice {
  /// dl[id^="notice_"] 的后缀;不能用帖子 tid 当提醒主键
  final String id;

  /// 优先用当前筛选参数,取不到时为 unknown
  final String category;
  final String? actor;
  final String? actorUid;
  final String? avatarUrl;
  final String occurredAtText;

  /// 事件描述纯文本,不保证含完整回复正文
  final String summary;
  final String? targetUrl;
  final int? tid;
  final int? pid;

  const Notice({
    required this.id,
    required this.category,
    required this.occurredAtText,
    required this.summary,
    this.actor,
    this.actorUid,
    this.avatarUrl,
    this.targetUrl,
    this.tid,
    this.pid,
  });
}

// ---------- 私信 ----------

enum PmFilter { privatePm, announcePm }

class PmConversation {
  /// 列表 pmlist_{id} 的后缀对应 plid(会话),与详情页的 pmid 不可混用
  final String id;
  final String peer;
  final String? peerUid;
  final String? avatarUrl;

  /// 清理掉操作区后的预览文本
  final String preview;
  final String timeRaw;

  /// 站点给出的详情地址,照用不自拼
  final String viewUrl;

  const PmConversation({
    required this.id,
    required this.peer,
    required this.preview,
    required this.timeRaw,
    required this.viewUrl,
    this.peerUid,
    this.avatarUrl,
  });
}

class PmMessage {
  final String? pmid;
  final String author;
  final String? authorUid;
  final String timeRaw;
  final String text;

  /// 源站把自己发的消息标成"您"(没有作者链接),据此判为自己
  final bool fromSelf;

  const PmMessage({
    required this.author,
    required this.timeRaw,
    required this.text,
    this.pmid,
    this.authorUid,
    this.fromSelf = false,
  });
}

// ---------- 收藏 ----------

enum FavoriteType { all, thread, forum, article }

class FavoriteItem {
  /// fav_{favid} 的后缀,不等于内容 tid / fid / aid
  final String favid;
  final String title;
  final String url;
  final String? timeRaw;

  final FavoriteType? _type;
  final int? _targetId;

  /// 兼容旧条目,缺少类型元数据时按目标 URL 判断。
  FavoriteType get type =>
      _type ??
      (fid != null || url.contains('forum-') || url.contains('fid=')
          ? FavoriteType.forum
          : url.contains('article-') || url.contains('aid=')
          ? FavoriteType.article
          : FavoriteType.thread);

  int? get targetId =>
      _targetId ??
      (type == FavoriteType.thread
          ? tid
          : type == FavoriteType.forum
          ? fid
          : null) ??
      int.tryParse(
        (switch (type) {
                  FavoriteType.thread => RegExp(r'thread-(\d+)-|[?&]tid=(\d+)'),
                  FavoriteType.forum => RegExp(r'forum-(\d+)-|[?&]fid=(\d+)'),
                  _ => RegExp(r'article-(\d+)-|[?&]aid=(\d+)'),
                })
                .firstMatch(url)
                ?.groups([1, 2])
                .whereType<String>()
                .firstOrNull ??
            '',
      );

  final PortalItemKind? portalKind;
  final int? tid;
  final int? fid;

  const FavoriteItem({
    required this.favid,
    required this.title,
    required this.url,
    this.timeRaw,
    this.portalKind,
    this.tid,
    this.fid,
    FavoriteType? type,
    int? targetId,
    // 公开参数名需与私有存储分开,保留旧条目的 URL 回退。
    // ignore: prefer_initializing_formals
  }) : _type = type,
       // ignore: prefer_initializing_formals
       _targetId = targetId;
}

// ---------- 我的帖子 ----------

class MyReplySnippet {
  final int pid;
  final String text;

  /// goto=findpost 地址,定位到具体楼层
  final String targetUrl;

  const MyReplySnippet({
    required this.pid,
    required this.text,
    required this.targetUrl,
  });
}

/// 个人帖子页的行:裸表格结构,不是 tbody#normalthread_*(PAGE_SPEC §6.2)
class MyThread {
  final int tid;
  final String title;
  final String? forumName;
  final int? forumFid;
  final int? replies;
  final int? views;
  final String? lastUser;
  final String? lastTimeRaw;

  /// 一帖可有多条回复摘要
  final List<MyReplySnippet> replySnippets;

  const MyThread({
    required this.tid,
    required this.title,
    this.forumName,
    this.forumFid,
    this.replies,
    this.views,
    this.lastUser,
    this.lastTimeRaw,
    this.replySnippets = const [],
  });
}

// ---------- 积分、用户组、权限、勋章 ----------

/// 通用表格:积分记录、权限矩阵、用户组对比都按实际表头解析,不固定列序
class SiteTable {
  final List<String> headers;
  final List<List<String>> rows;

  /// 表格页的分页信息。积分记录有几十页,必须能往下翻。
  final PageInfo page;
  final String? nextUrl;

  const SiteTable({
    required this.headers,
    required this.rows,
    this.page = const PageInfo(current: 1, hasNext: false),
    this.nextUrl,
  });

  bool get isEmpty => rows.isEmpty;
}

class CreditOverview {
  /// 积分概览的键值对
  final Map<String, String> summary;
  final SiteTable recent;

  const CreditOverview({required this.summary, required this.recent});
}

class MedalItem {
  final String id;
  final String name;
  final String? description;
  final String? imageUrl;

  const MedalItem({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
  });
}

// ---------- 写操作:发帖与回帖 ----------

/// 发帖 / 回帖表单规格
///
/// 按页面实际控件生成。站点禁用的选项不能自行开启,未出现的字段不能补造。
/// formhash 每页刷新,所以提交前必须重新取表单。
class PostForm {
  /// 站点给出的完整 POST 地址,照用不自拼
  final String action;
  final String formhash;

  /// 隐藏字段(posttime / wysiwyg / handlekey / noticeauthor 等),原样回传
  final Map<String, String> hidden;

  /// 引用表单预填的正文，保留 BBCode 与目标楼层链接。
  final String initialMessage;

  /// 发主题时的分类选项。站点是否强制选分类由页面决定,这里只收集。
  final List<ThreadType> types;

  /// 是否需要标题(发主题要,快速回复不要)
  final bool requiresSubject;

  /// 页面是否出现验证码控件
  ///
  /// 站点的验证码(腾讯滑块)由脚本插入,原始页面里只有占位和加载脚本。
  /// 需要验证码时只能在站点真实页面里完成提交,票据离开那个页面就失效。
  final bool hasCaptcha;

  /// 图片上传所需的上下文;页面没有给出上传参数时为 null
  final UploadContext? upload;

  const PostForm({
    required this.action,
    required this.formhash,
    this.hidden = const {},
    this.initialMessage = '',
    this.types = const [],
    this.requiresSubject = false,
    this.hasCaptcha = false,
    this.upload,
  });
}

/// 发帖/回帖页给出的图片上传参数
///
/// uid 与 hash 都来自同一账号打开的表单页,不自行生成;hash 与提交正文用的 formhash 不是一回事。
class UploadContext {
  final String uid;
  final String hash;

  /// 单张图片的字节上限;页面没给出时为 null,交给服务器判断
  final int? maxBytes;

  /// 站点允许的图片扩展名(小写);为空表示页面没有给出
  final Set<String> extensions;

  const UploadContext({
    required this.uid,
    required this.hash,
    this.maxBytes,
    this.extensions = const {},
  });

  bool allows(String ext) => extensions.isEmpty || extensions.contains(ext);
}

/// 需要在站点真实页面里完成的提交:页面地址 + 要填进表单的字段
class WebSubmission {
  final Uri page;
  final Map<String, String> fields;

  const WebSubmission(this.page, this.fields);
}

/// 提交结果的语义分类
///
/// 站点的成功与失败响应形态未做过受控验证,所以只在能确证时判成功,
/// 其余一律保留原文让用户自己看,不编造结果。
enum PostResultKind {
  success,
  needCaptcha,
  loginRequired,
  permissionDenied,

  /// 发帖间隔限制、重复内容等站点节流
  throttled,

  /// 能确认失败但原因不在已知分类里
  failed,

  /// 响应形态无法判定,保留原文
  unknown,
}

class PostResult {
  final PostResultKind kind;

  /// 站点原文,不改写
  final String message;
  final int? tid;
  final int? pid;

  /// 需要验证码时,可以改在站点真实页面里完成的那次提交
  final WebSubmission? web;

  const PostResult(this.kind, this.message, {this.tid, this.pid, this.web});

  bool get isSuccess => kind == PostResultKind.success;
}

// ---------- 楼层附属内容:说明、评分、点评 ----------

/// 楼层里的说明块(i.pstatus)
///
/// 同一个标记承载两种语义,按文案区分:
///   本帖最后由 xxx 于 … 编辑   → 编辑说明
///   补充内容 (…):…            → 楼主后补的内容
enum PostNoteKind { edited, supplement }

class PostNote {
  final PostNoteKind kind;
  final String text;

  const PostNote(this.kind, this.text);
}

/// 一条评分记录
class RatingEntry {
  final String user;
  final String? uid;

  /// 站点原样给出的分值文本,如「+ 100」。不自行解析正负与单位。
  final String score;
  final String? reason;

  const RatingEntry({
    required this.user,
    required this.score,
    this.uid,
    this.reason,
  });
}

/// 楼层评分汇总(dl#ratelog_{pid}.rate)
class PostRating {
  /// 表头给出的汇总项,如「参与人数 2」「邪恶指数 +120」
  final List<String> summary;
  final List<RatingEntry> entries;

  const PostRating({required this.summary, required this.entries});

  bool get isEmpty => summary.isEmpty && entries.isEmpty;
}

/// 一条点评(div#comment_{pid}.cm 里的条目)
class PostComment {
  final String author;
  final String? uid;
  final String text;
  final String? timeRaw;

  const PostComment({
    required this.author,
    required this.text,
    this.uid,
    this.timeRaw,
  });
}

// ---------- 门户文章列表 ----------

/// 门户栏目
class PortalCategory {
  final int catid;
  final String name;

  const PortalCategory({required this.catid, required this.name});

  /// 「全部」入口,不带 catid
  static const all = PortalCategory(catid: 0, name: '全部');
}

/// 文章列表条目
///
/// 封面是 static.chiphell.com 的直链,无懒加载。
class PortalArticle {
  final int aid;
  final String title;
  final String? coverUrl;
  final String? summary;
  final String? categoryName;
  final int? catid;
  final String? timeRaw;

  const PortalArticle({
    required this.aid,
    required this.title,
    this.coverUrl,
    this.summary,
    this.categoryName,
    this.catid,
    this.timeRaw,
  });
}

// ---------- 门户首页精选 ----------

/// 快讯条目。实测指向的是论坛帖,不是门户文章。
class NewsItem {
  final int tid;
  final String title;

  const NewsItem({required this.tid, required this.title});
}

/// 首页上半部分的编辑内容
class PortalHighlights {
  /// 幻灯片头条
  final List<PortalArticle> banners;

  /// 快讯,纯文字
  final List<NewsItem> news;

  /// 评测图卡
  final List<PortalArticle> reviews;

  const PortalHighlights({
    required this.banners,
    required this.news,
    required this.reviews,
  });

  bool get isEmpty => banners.isEmpty && news.isEmpty && reviews.isEmpty;

  static const empty = PortalHighlights(banners: [], news: [], reviews: []);
}
