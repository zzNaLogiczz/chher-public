/// 其余读页面:标签页、版块分类、积分 / 用户组 / 权限、勋章、设置只读
///
/// 这些页面结构各自独立,但都只做只读展示,所以集中在一个解析器里,
/// 共用 dom_utils 的表格与分页工具。
library;

import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'dom_utils.dart';

/// 标签页(misc.php?mod=tag&id=N)
///
/// 独立结构:裸 table,没有 normalthread_ 容器,所以不能复用版块页解析器。
Paged<ThreadSummary> parseTagThreads(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final items = <ThreadSummary>[];
  for (final tr in doc.querySelectorAll('table tr')) {
    final a = tr.querySelector('a[href*="thread-"], a[href*="tid="]');
    final href = a?.attributes['href'] ?? '';
    final title = cleanText(a?.text);
    final tid = ChhUrls.tidFromUrl(href);
    if (tid == null || title.isEmpty) continue;

    final cells = tr.querySelectorAll('td');
    items.add(
      ThreadSummary(
        tid: tid,
        title: title,
        author: cleanText(findUserLink(tr)?.el.text),
        replies: 0,
        views: 0,
        lastPostTimeRaw: cells.isEmpty ? null : cleanText(cells.last.text),
      ),
    );
  }

  return Paged(items: items, page: parsePager(doc), nextUrl: nextPageUrl(doc));
}

/// 版块内分类筛选:ul#thread_types li,当前选中项带 .xw1.a
List<ThreadType> parseThreadTypes(String html) {
  final doc = html_parser.parse(html);
  final out = <ThreadType>[];

  for (final li in doc.querySelectorAll('ul#thread_types li')) {
    final a = li.querySelector('a');
    final href = a?.attributes['href'] ?? '';
    // The source nests a topic-count badge inside the label (e.g. ITX + 13).
    // Keep digits belonging to the category itself; omit only that badge.
    final name = a == null ? '' : textWithout(a, ['.num']);
    if (name.isEmpty) continue;

    final typeid = int.tryParse(
      RegExp(r'[?&]typeid=(\d+)').firstMatch(href)?.group(1) ?? '',
    );
    // 没有 typeid 的是「全部」入口,用 0 表示
    out.add(
      ThreadType(
        typeid: typeid ?? 0,
        name: name,
        active: li.className.contains('a'),
      ),
    );
  }
  return out;
}

/// 我的积分(spacecp&ac=credit):概览键值对 + 最近记录表
CreditOverview parseCredit(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final summary = <String, String>{};
  for (final li in doc.querySelectorAll('#ct li, .creditl li')) {
    final label = cleanText(li.querySelector('em')?.text).replaceAll(':', '');
    if (label.isEmpty) continue;
    final value = textWithout(li, ['em']);
    if (value.isNotEmpty) summary[label] = value;
  }

  return CreditOverview(
    summary: summary,
    recent: parseTable(doc.querySelector('table.dt')),
  );
}

/// 通用只读表格页:积分记录、用户组对比、社区权限矩阵
///
/// 按实际表头取列。自己的用户组行在 table.tdat.tfx,权限矩阵在 table.tdat.ftb。
SiteTable parseSiteTable(String html, {String selector = 'table.dt'}) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final table = parseTable(
    doc.querySelector(selector) ?? doc.querySelector('table'),
  );
  // 积分记录有几十页,分页信息要带出来
  return SiteTable(
    headers: table.headers,
    rows: table.rows,
    page: parsePager(doc),
    nextUrl: nextPageUrl(doc),
  );
}

/// 勋章中心(home.php?mod=medal)
///
/// 排除带 _menu 的说明节点,否则一个勋章会算两次。
List<MedalItem> parseMedals(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final out = <MedalItem>[];
  for (final el in doc.querySelectorAll('div[id^="medal_"]')) {
    if (el.id.endsWith('_menu')) continue;
    if (!el.className.contains('mg_img')) continue;

    final id = el.id.replaceFirst('medal_', '');
    final img = el.querySelector('img');
    final tip = doc.querySelector('#medal_${id}_menu');

    out.add(
      MedalItem(
        id: id,
        name: cleanText(img?.attributes['alt'] ?? el.text),
        description: cleanText(tip?.text).isEmpty ? null : cleanText(tip?.text),
        imageUrl: img?.attributes['src'] == null
            ? null
            : ChhUrls.absolutize(img!.attributes['src']!),
      ),
    );
  }
  return out;
}

/// 设置页只读展示:按控件实际存在性生成,不能因为 Discuz 有某字段就补造
///
/// select 读 selected,checkbox 读 checked,两者不能只读 value。
SettingsForm parseSettingsForm(String html) {
  final doc = html_parser.parse(html);
  throwIfMessagePage(doc);

  final title = cleanText(doc.querySelector('#ct h1, .ptm h1, h1.mt')?.text);
  final fields = <SettingField>[];
  final root = doc.querySelector('#profilelist') ?? doc.querySelector('#ct');
  if (root == null) return SettingsForm(title: title, fields: fields);

  for (final row in root.querySelectorAll('tr, li, .rfm')) {
    final label = cleanText(
      row.querySelector('th, em, label')?.text,
    ).replaceAll(':', '');

    for (final sel in row.querySelectorAll('select')) {
      final name = sel.attributes['name'] ?? '';
      if (name.isEmpty) continue;
      final options = sel.querySelectorAll('option');
      final selected = options
          .where((o) => o.attributes.containsKey('selected'))
          .firstOrNull;
      fields.add(
        SettingField(
          name: name,
          label: label.isEmpty ? name : label,
          value: cleanText(selected?.text),
          options: options.map((o) => cleanText(o.text)).toList(),
        ),
      );
    }

    for (final input in row.querySelectorAll('input')) {
      final name = input.attributes['name'] ?? '';
      final type = input.attributes['type'] ?? 'text';
      if (name.isEmpty || type == 'hidden' || type == 'submit') continue;
      fields.add(
        SettingField(
          name: name,
          label: label.isEmpty ? name : label,
          value: input.attributes['value'],
          checked: input.attributes.containsKey('checked'),
        ),
      );
    }
  }

  return SettingsForm(title: title.isEmpty ? '设置' : title, fields: fields);
}
