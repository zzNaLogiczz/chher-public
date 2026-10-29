/// 图片上传的回包判定
///
/// 上传接口 misc.php?mod=swfupload&operation=upload&simple=1 成功时回
/// `DISCUZUPLOAD|0|{aid}|…`,状态位非 0 即失败。正文只能用附件编号引用图片
/// ([attachimg]aid[/attachimg]),所以只接受数字 aid;回地址或其他形态都算失败,
/// 不把一段看不懂的文本当成功。
library;

import 'package:html/parser.dart' as html_parser;

import 'dom_utils.dart';

sealed class UploadOutcome {
  const UploadOutcome();
}

class UploadSucceeded extends UploadOutcome {
  final String aid;
  const UploadSucceeded(this.aid);
}

class UploadFailed extends UploadOutcome {
  final String message;
  const UploadFailed(this.message);
}

UploadOutcome parseUploadResponse(String body, {int status = 200}) {
  if (status == 413) return const UploadFailed('图片超过站点允许的大小');
  if (status < 200 || status >= 300) {
    return UploadFailed('图片上传失败（HTTP $status）');
  }
  final text = body.trim();
  final simple = RegExp(
    r'DISCUZ_?UPLOAD\|(\d+)\|(\d+)\|',
    caseSensitive: false,
  ).firstMatch(text);
  if (simple != null) {
    final aid = simple.group(2)!;
    if (simple.group(1) != '0') {
      return UploadFailed('图片上传失败（站点返回 ${simple.group(1)}）');
    }
    return aid == '0'
        ? const UploadFailed('图片上传失败，站点没有返回附件编号')
        : UploadSucceeded(aid);
  }
  final json = RegExp(
    r'''["']?aid["']?\s*:\s*["']?(\d+)["']?''',
  ).firstMatch(text)?.group(1);
  if (json != null && json != '0') return UploadSucceeded(json);
  if (text.isEmpty) return const UploadFailed('图片上传失败，站点没有返回结果');
  // 其余形态多是站点提示页;只取可读文字,不把脚本和标签带给用户
  final doc = html_parser.parse(text);
  for (final e in doc.querySelectorAll('script, style')) {
    e.remove();
  }
  final readable = cleanText(
    doc.querySelector('#messagetext')?.text ?? doc.body?.text ?? '',
  );
  return UploadFailed(
    readable.isEmpty
        ? '图片上传失败'
        : '图片上传失败：${readable.length > 60 ? '${readable.substring(0, 60)}…' : readable}',
  );
}
