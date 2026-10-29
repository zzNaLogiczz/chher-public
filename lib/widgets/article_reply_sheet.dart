/// 门户评论与论坛回复共享顺滑、保稿的写作画布。
library;

import 'package:flutter/material.dart';
import '../models/models.dart';
import 'expressive_composer.dart';

class ArticleReplySheet extends StatefulWidget {
  final Future<PostResult> Function(String message) onSubmit;
  final String initialText;
  final ValueChanged<String>? onDraftChanged;
  final String? quoteAuthor;
  final String? quoteText;
  final Future<void> Function()? onLogin;

  const ArticleReplySheet({
    super.key,
    required this.onSubmit,
    this.initialText = '',
    this.onDraftChanged,
    this.quoteAuthor,
    this.quoteText,
    this.onLogin,
  });

  static Future<PostResult?> show(
    BuildContext context, {
    required Future<PostResult> Function(String message) onSubmit,
    String initialText = '',
    ValueChanged<String>? onDraftChanged,
    String? quoteAuthor,
    String? quoteText,
    Future<void> Function()? onLogin,
  }) => showExpressiveComposerRoute(
    context,
    builder: (_) => ArticleReplySheet(
      onSubmit: onSubmit,
      initialText: initialText,
      onDraftChanged: onDraftChanged,
      quoteAuthor: quoteAuthor,
      quoteText: quoteText,
      onLogin: onLogin,
    ),
  );

  @override
  State<ArticleReplySheet> createState() => _ArticleReplySheetState();
}

class _ArticleReplySheetState extends State<ArticleReplySheet> {
  @override
  Widget build(BuildContext context) => ExpressiveComposer(
    title: widget.quoteAuthor == null ? '写评论' : '写回复',
    modeLabel: widget.quoteAuthor == null
        ? '文章评论'
        : '回复给 ${widget.quoteAuthor}',
    hintText: widget.quoteAuthor == null ? '分享你的看法' : '回复内容',
    initialText: widget.initialText,
    quoteLabel: widget.quoteText?.isNotEmpty == true ? '引用评论' : null,
    quoteText: widget.quoteText,
    unknownActionLabel: '返回评论确认',
    onSubmit: widget.onSubmit,
    onDraftChanged: widget.onDraftChanged,
    onLogin: widget.onLogin,
  );
}
