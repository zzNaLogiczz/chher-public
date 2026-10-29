/// 门户域读操作:首页信息流与门户文章
///
/// 门户与论坛是两套体系。门户图是直链 src 无懒加载,是全站唯一可做图像化编排的面。
library;

import '../core/chh_urls.dart';
import '../models/models.dart';
import '../network/chh_client.dart';
import '../parser/portal_home_parser.dart';
import '../parser/portal_list_parser.dart';
import '../parser/portal_parser.dart';

class PortalRepository {
  final ChhClient client;
  const PortalRepository(this.client);

  /// 首页上半部分的编辑内容
  ///
  /// 与全部文章流共用同一张门户页,命中 90 秒缓存时不额外请求。
  Future<PortalHighlights> highlights({bool refresh = false}) async {
    return parsePortalHighlights(
      await client.getHtml(ChhUrls.portalFeed(), refresh: refresh),
    );
  }

  /// 文章列表。catid 为 0 取全部文章流,否则取该栏目。
  ///
  /// 两种页面的条目结构不同,所以分开解析。
  Future<Paged<PortalArticle>> articles({
    int catid = 0,
    int page = 1,
    bool refresh = false,
  }) async {
    if (catid == 0) {
      final html = await client.getHtml(
        ChhUrls.portalFeed(page: page),
        refresh: refresh,
      );
      return parsePortalFeed(html);
    }
    final html = await client.getHtml(
      ChhUrls.portalCategory(catid, page: page),
      refresh: refresh,
    );
    return parsePortalCategoryList(html);
  }

  /// 栏目清单。随便取一张门户页就能解析出来,不额外设计接口。
  Future<List<PortalCategory>> categories({bool refresh = false}) async {
    return parsePortalCategories(
      await client.getHtml(ChhUrls.portalFeed(), refresh: refresh),
    );
  }

  /// 打开门户条目
  ///
  /// 站点上不少「文章」会跳到论坛帖,所以按落地页的实际形态分流,
  /// 不能一律当文章解析 —— 那样只会得到空白页。
  Future<PortalContent> openArticle(
    int aid, {
    int page = 1,
    bool refresh = false,
    bool fallback = true,
  }) async {
    final html = await client.getHtml(
      ChhUrls.article(aid, page: page),
      refresh: refresh,
      fallback: fallback,
    );

    final tid = threadBehindArticle(html);
    if (tid != null) return ThreadContent(tid, titleOfPage(html));

    return ArticleContent(parseArticle(html, aid: aid));
  }
}
