/// 论坛回复使用统一的半屏/全屏写作画布，草稿按目标隔离。
library;

import 'package:flutter/material.dart';
import '../ui/feedback.dart';
import '../models/models.dart';
import '../attachments/attachment_controller.dart';
import 'expressive_composer.dart';

class ComposerSheet extends StatefulWidget {
  final String? quoteOf;
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
    String hintText = '回复内容',
    String initialText = '',
    String? draftKey,
    ValueChanged<String>? onDraftChanged,
    AttachmentController? attachments,
  }) => showExpressiveComposerRoute(
    context,
    builder: (_) => ComposerSheet(
      onSubmit: onSubmit,
      quoteOf: quoteOf,
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
    title: '写回复',
    modeLabel: widget.quoteOf == null ? '社区讨论' : '楼层回复',
    hintText: widget.hintText,
    initialText: widget.initialText,
    quoteLabel: widget.quoteOf == null ? null : '引用 ${widget.quoteOf}',
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
    PostResultKind.throttled => result.message,
    PostResultKind.failed => result.message,
    PostResultKind.unknown => '提交状态未知，请刷新确认',
  };
  AppToast.show(context, text);
}
