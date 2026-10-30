/// 收藏与删除都沿用站点表单,保留服务端给出的隐藏字段。
library;

import 'package:html/parser.dart' as html_parser;

import '../core/chh_urls.dart';
import '../models/models.dart';
import 'dom_utils.dart';

class FavoriteForm {
  final Uri action;
  final Map<String, String> hidden;
  const FavoriteForm({required this.action, required this.hidden});
}

FavoriteForm? parseFavoriteForm(String html) {
  final doc = html_parser.parse(html);
  final form = doc.querySelector('form[id^="favoriteform_"]');
  final action = form?.attributes['action'];
  if (form == null || action == null || action.isEmpty) return null;
  final hidden = <String, String>{};
  for (final input in form.querySelectorAll('input[type="hidden"][name]')) {
    final name = input.attributes['name']!;
    if (name.isNotEmpty) hidden[name] = input.attributes['value'] ?? '';
  }
  return FavoriteForm(
    action: Uri.parse(ChhUrls.absolutize(action)),
    hidden: hidden,
  );
}

PageMessage? parseFavoriteMessage(String html) =>
    detectPageMessage(html_parser.parse(html));

bool isAlreadyFavorited(String html) {
  final message = parseFavoriteMessage(html);
  return message?.kind == PageMessageKind.message &&
      (message!.text.contains('已收藏') || message.text.contains('重复收藏'));
}
