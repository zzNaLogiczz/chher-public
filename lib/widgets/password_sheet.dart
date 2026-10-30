/// 密码输入复用弹层与编辑区焦点约定，不改写密码内容。
library;

import 'package:flutter/material.dart';

import '../data/forum_repository.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../di.dart';
import '../ui/app_button.dart';
import '../ui/editor_touch.dart';
import '../ui/feedback.dart';
import '../ui/sheet_scaffold.dart';

Future<String?> showPasswordSheet(
  BuildContext context, {
  required String title,
}) =>
    showAppSheet<String>(context, builder: (_) => _PasswordSheet(title: title));

/// 调用方只在成功后重读内容，取消和失败都保留当前状态。
Future<bool> showForumPasswordUnlock(
  BuildContext context,
  int fid, {
  ForumRepository? repository,
}) async {
  final password = await showPasswordSheet(context, title: '输入版块密码');
  if (password == null || !context.mounted) return false;
  try {
    final success = await (repository ?? forumRepo).verifyForumPassword(
      fid,
      password,
    );
    if (!context.mounted) return false;
    if (!success) AppToast.show(context, '密码不正确');
    return success;
  } catch (_) {
    if (context.mounted) AppToast.show(context, '解锁未完成，请重试');
    return false;
  }
}

class _PasswordSheet extends StatefulWidget {
  final String title;
  const _PasswordSheet({required this.title});

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _controller = TextEditingController();
  bool _submitted = false;

  void _submit() {
    if (_submitted || _controller.text.isEmpty) return;
    _submitted = true;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SheetScaffold(
        title: widget.title,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screen,
            8,
            AppSpace.screen,
            AppSpace.screen,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: t.fill,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: EditorTouchGuard(
                  notifyOnUserEntry: true,
                  builder: (context, focusNode, onTap) => TextField(
                    controller: _controller,
                    focusNode: focusNode,
                    autofocus: true,
                    onTapAlwaysCalled: true,
                    onTap: onTap,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLines: 1,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    cursorColor: t.accent,
                    style: AppType.body.copyWith(color: t.text),
                    decoration: InputDecoration(
                      hintText: '输入密码',
                      hintStyle: AppType.body.copyWith(color: t.text3),
                      contentPadding: const EdgeInsets.all(16),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => AppButton(
                  label: '输入密码',
                  onPressed: value.text.isEmpty ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
