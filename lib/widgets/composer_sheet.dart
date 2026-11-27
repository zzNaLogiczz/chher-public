/// 论坛回复使用统一的贴边写作面板，草稿按目标隔离。
library;

import 'package:flutter/material.dart';
import '../ui/feedback.dart';
import '../models/models.dart';
import '../attachments/attachment_controller.dart';
import 'expressive_composer.dart';

class ComposerSheet extends StatefulWidget {
  final String? quoteOf;
  final String? quoteText;
  final String? threadTitle;
  final String hintText;
  final Future<PostResult> Function(String message) onSubmit;
  final String initialText;
  final String? draftKey;
  final ValueChanged<String>? onDraftChanged;
  final AttachmentController? attachments;

  const ComposerSheet({
    super.key,
    required this.onSubmit,
    this.quoteOf,
    this.quoteText,
    this.threadTitle,
    this.hintText = '回复内容',
    this.initialText = '',
    this.draftKey,
    this.onDraftChanged,
    this.attachments,
  });

  static final _drafts = <String, String>{};

  static Future<PostResult?> show(
    BuildContext context, {
    required Future<PostResult> Function(String message) onSubmit,
    String? quoteOf,
    String? quoteText,
    String? threadTitle,
    String hintText = '回复内容',
    String initialText = '',
    String? draftKey,
    ValueChanged<String>? onDraftChanged,
    AttachmentController? attachments,
  }) => showExpressiveComposerRoute(
    context,
    docked: true,
    builder: (_) => ComposerSheet(
      onSubmit: onSubmit,
      quoteOf: quoteOf,
      quoteText: quoteText,
      threadTitle: threadTitle,
      hintText: hintText,
      initialText: draftKey == null
          ? initialText
          : (_drafts[draftKey] ?? initialText),
      draftKey: draftKey,
      onDraftChanged: onDraftChanged,
      attachments: attachments,
    ),
  );

  @override
  State<ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<ComposerSheet> {
  @override
  Widget build(BuildContext context) => ExpressiveComposer(
    title: widget.quoteOf == null ? '写回复' : '回复 ${widget.quoteOf}',
    showReplyIcon: true,
    hintText: widget.hintText,
    initialText: widget.initialText,
    contextLine: widget.quoteText ?? widget.threadTitle,
    onSubmit: widget.onSubmit,
    attachments: widget.attachments,
    onDraftChanged: (text) {
      final key = widget.draftKey;
      if (key != null) {
        if (text.isEmpty) {
          ComposerSheet._drafts.remove(key);
        } else {
          ComposerSheet._drafts[key] = text;
        }
      }
      widget.onDraftChanged?.call(text);
    },
  );
}

void showPostResult(BuildContext context, PostResult result) {
  final text = switch (result.kind) {
    PostResultKind.success => '已发布',
    PostResultKind.needCaptcha => result.message,
    PostResultKind.loginRequired => '需登录',
    PostResultKind.permissionDenied => '没有发布权限',
    PostResultKind.selfRating ||
    PostResultKind.ratingQuotaExhausted ||
    PostResultKind.throttled => result.message,
    PostResultKind.failed => result.message,
    PostResultKind.unknown => '提交状态未知，请刷新确认',
  };
  AppToast.show(context, text);
}
