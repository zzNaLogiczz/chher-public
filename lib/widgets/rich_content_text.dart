/// 带表情或链接的正文段落
///
/// 论坛表情是穿插在文字里的小图,必须内联渲染;站外链接留在句子里可点。
/// 只有文字时退回 SelectableText,长文仍然可以选中复制。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/link_target.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../models/models.dart';
import 'link_opener.dart';
import 'net_image.dart';

class RichContentText extends StatefulWidget {
  final TextBlock block;
  final TextStyle? style;

  const RichContentText({super.key, required this.block, this.style});

  @override
  State<RichContentText> createState() => _RichContentTextState();
}

class _RichContentTextState extends State<RichContentText> {
  /// 表情按文字高度走,稍大一点才看得清
  static const double _smileySize = 20;

  /// 每次构建重新生成,旧的要释放,否则识别器泄漏
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _releaseRecognizers();
    super.dispose();
  }

  void _releaseRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final style = widget.style;
    _releaseRecognizers();
    if (!block.hasInline) {
      return SelectableText(block.text, style: style);
    }

    final t = AppTokens.of(context);
    return Text.rich(
      TextSpan(
        children: [
          for (final node in block.nodes)
            ...switch (node) {
              InlineText(:final text) => [TextSpan(text: text)],
              InlineSmiley(:final url) => [_smiley(url)],
              InlineLink(:final text, :final target) => _link(
                context,
                t,
                text,
                target,
              ),
            },
        ],
      ),
      style: style,
    );
  }

  InlineSpan _smiley(String url) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: NetImage(
        url: url,
        width: _smileySize,
        height: _smileySize,
        fit: BoxFit.contain,
      ),
    ),
  );

  /// 链接文字用强调色;后面的小箭头说明点开会离开 App
  List<InlineSpan> _link(
    BuildContext context,
    AppTokens t,
    String text,
    LinkTarget target,
  ) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => openLinkTarget(context, target);
    _recognizers.add(recognizer);
    final size = (widget.style?.fontSize ?? 17) * .75;
    return [
      TextSpan(
        text: text,
        recognizer: recognizer,
        style: TextStyle(color: t.accent, fontWeight: FontWeight.w500),
      ),
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(left: 2),
          child: ExcludeSemantics(
            child: Icon(AppIcons.externalLink, size: size, color: t.accent),
          ),
        ),
      ),
    ];
  }
}
