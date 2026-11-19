/// 主题编辑：独立标题/正文层级，失败与未知结果均保留草稿。
library;

import 'package:flutter/material.dart';
import '../widgets/chhers_loading_transition.dart';
import '../widgets/compact_scaffold.dart';
import '../ui/editor_touch.dart';
import '../ui/picker.dart';
import '../design/typography.dart';
import '../ui/app_button.dart';

import '../attachments/attachment_controller.dart';
import '../design/display_text.dart';
import '../design/editor_tokens.dart';
import '../design/tokens.dart';
import '../design/shapes.dart';
import '../di.dart';
import '../models/models.dart';
import '../widgets/attachment_bar.dart';
import '../widgets/composer_sheet.dart';
import 'web_post_page.dart';
import '../widgets/state_view.dart';
import '../widgets/expressive_controls.dart';

class NewThreadPage extends StatefulWidget {
  final int fid;
  final String forumName;
  final Future<PostForm?> Function()? loadForm;
  final Future<PostResult> Function(
    String subject,
    String message,
    int? typeid,
  )?
  onSubmit;

  const NewThreadPage({
    super.key,
    required this.fid,
    required this.forumName,
    this.loadForm,
    this.onSubmit,
  });

  static final _drafts = <int, ({String title, String body, int? typeid})>{};

  /// 正文里的图片,与文字草稿一样按版块保留,发表成功后清掉
  static final _images = <int, AttachmentController>{};

  @override
  State<NewThreadPage> createState() => _NewThreadPageState();
}

class _NewThreadPageState extends State<NewThreadPage> {
  late final _subject = TextEditingController(
    text: NewThreadPage._drafts[widget.fid]?.title,
  );
  late final _body = TextEditingController(
    text: NewThreadPage._drafts[widget.fid]?.body,
  );
  late Future<PostForm?> _future;
  late int? _typeid = NewThreadPage._drafts[widget.fid]?.typeid;
  late final _images = NewThreadPage._images.putIfAbsent(
    widget.fid,
    () => AttachmentController(
      loadContext: () async =>
          (await postRepo.newThreadForm(widget.fid))?.upload,
      upload: uploaderFor(postRepo),
    ),
  );
  bool _sending = false;
  bool _ready = false;
  PostResult? _failure;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _subject.addListener(_remember);
    _body.addListener(_remember);
    _images.addListener(_imagesChanged);
  }

  void _imagesChanged() {
    if (mounted) setState(() {});
  }

  Future<PostForm?> _load() async {
    final form =
        await (widget.loadForm?.call() ?? postRepo.newThreadForm(widget.fid));
    if (!mounted) return form;
    // 需要人机验证的版块照常编辑,发表时转到站点页面完成验证
    if (form != null) {
      _typeid ??= form.types.where((t) => t.active).firstOrNull?.typeid;
      _ready = true;
    }
    return form;
  }

  /// 有字或有已上传的图都可以发;图片还在处理或有失败未处理时先不发
  bool get _hasContent {
    if (_images.busy || _images.hasFailed) return false;
    return _body.text.trim().isNotEmpty || _images.aids.isNotEmpty;
  }

  void _remember() {
    NewThreadPage._drafts[widget.fid] = (
      title: _subject.text,
      body: _body.text,
      typeid: _typeid,
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _images.removeListener(_imagesChanged);
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _subject.text.trim();
    final body = _body.text.trim();
    if (!_ready ||
        title.isEmpty ||
        !_hasContent ||
        _sending ||
        _failure?.kind == PostResultKind.unknown) {
      return;
    }
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      var result =
          await (widget.onSubmit?.call(title, body, _typeid) ??
              postRepo.createThread(
                fid: widget.fid,
                subject: title,
                message: body,
                typeid: _typeid,
                images: _images.aids,
              ));
      if (!mounted) return;
      // 站点要求人机验证:转到站点页面完成,结果照常处理
      result = await completeOnWeb(context, result);
      if (!mounted) return;
      if (result.isSuccess) {
        NewThreadPage._drafts.remove(widget.fid);
        _images.removeListener(_imagesChanged);
        NewThreadPage._images.remove(widget.fid)?.dispose();
        showPostResult(context, result);
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _failure = result;
          _sending = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failure = const PostResult(PostResultKind.unknown, '发表结果未确认，请返回版块核对');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final enabled =
        _ready &&
        !_sending &&
        _subject.text.trim().isNotEmpty &&
        _hasContent &&
        _failure?.kind != PostResultKind.unknown;
    return PopScope(
      canPop: !_sending,
      child: CompactScaffold(
        title: '发表主题',
        centerTitle: true,
        leading: AppButton(
          label: '取消',
          variant: AppButtonVariant.quiet,
          onPressed: _sending ? null : () => Navigator.maybePop(context),
        ),
        actions: [
          AppButton(
            label: _sending ? '发表中' : '发表',
            small: true,
            state: _sending ? AppButtonState.busy : AppButtonState.idle,
            onPressed: enabled ? _submit : null,
          ),
        ],
        body: FutureBuilder<PostForm?>(
          future: _future,
          builder: (context, snap) => ChhersLoadingTransition(
            child: snap.connectionState != ConnectionState.done
                ? null
                : _loadedBody(context, snap, t),
          ),
        ),
      ),
    );
  }

  Widget _loadedBody(
    BuildContext context,
    AsyncSnapshot<PostForm?> snap,
    AppTokens t,
  ) {
    final error = snap.error;
    if (error is PageMessage) {
      return StateView.forMessage(
        error,
        onLogin: () => Navigator.of(context).pushNamed('/login'),
      );
    }
    if (error != null) {
      return StateView.error(
        error,
        onRetry: () => setState(() => _future = _load()),
      );
    }
    final form = snap.data;
    if (form == null) {
      return const StateView(icon: AppIcons.forbidden, message: '当前版块无法发表主题');
    }
    // 页面随键盘收缩,图片横栏始终停在可视区域底部
    return Column(
      children: [
        Expanded(
          child: ExpressivePageReveal(
            active: true,
            animateOnMount: true,
            child: _editor(form, t),
          ),
        ),
        AttachmentBar(controller: _images, enabled: !_sending),
      ],
    );
  }

  Widget _editor(PostForm form, AppTokens t) => ListView(
    padding: EditorTokens.insets,
    children: [
      Text.rich(
        TextSpan(
          text: '发布到 ',
          children: [
            TextSpan(
              text: formatForumName(widget.forumName),
              style: TextStyle(color: t.text, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        style: EditorTokens.destination.copyWith(color: t.text2),
      ),
      const SizedBox(height: EditorTokens.destinationGap),
      if (form.types.isNotEmpty) ...[
        _typePicker(form.types, t),
        const SizedBox(height: 18),
      ],
      EditorTouchGuard(
        builder: (context, editorFocus, onEditorTap) => TextField(
          focusNode: editorFocus,
          onTapAlwaysCalled: true,
          onTap: onEditorTap,
          controller: _subject,
          enabled: !_sending,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: '标题',
            hintStyle: EditorTokens.title.copyWith(color: t.text3),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          style: EditorTokens.title.copyWith(color: t.text),
        ),
      ),
      const SizedBox(height: AppSpace.section),
      EditorTouchGuard(
        builder: (context, editorFocus, onEditorTap) => TextField(
          focusNode: editorFocus,
          onTapAlwaysCalled: true,
          onTap: onEditorTap,
          controller: _body,
          enabled: !_sending,
          minLines: 12,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: '从这里开始分享',
            hintStyle: EditorTokens.body.copyWith(color: t.text3),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
          style: EditorTokens.body.copyWith(color: t.text),
        ),
      ),
      ExpressiveVisibility(
        visible: _failure != null,
        child: _failure == null
            ? const SizedBox.shrink()
            : Container(
                padding: const EdgeInsets.all(16),
                decoration: ShapeDecoration(
                  color: t.warnBg,
                  shape: appShape(AppRadii.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _failure!.kind == PostResultKind.unknown
                            ? '发表结果未确认，请返回版块核对'
                            : _failure!.message,
                        style: TextStyle(
                          fontSize: AppType.sizeFootnote,
                          color: t.warn,
                          height: 1.6,
                        ),
                      ),
                    ),
                    if (_failure!.kind == PostResultKind.unknown)
                      AppButton(
                        label: '返回版块确认',
                        variant: AppButtonVariant.plain,
                        onPressed: () => Navigator.pop(context),
                      ),
                  ],
                ),
              ),
      ),
    ],
  );

  Widget _typePicker(List<ThreadType> types, AppTokens t) => Align(
    alignment: Alignment.centerLeft,
    child: PickerButton<int?>(
      sheetTitle: '选择分类',
      placeholder: '选择分类',
      options: [
        for (final type in types)
          PickerOption(value: type.typeid, label: type.name),
      ],
      value: _typeid,
      onChanged: (value) {
        if (_sending) return;
        setState(() => _typeid = value);
        _remember();
      },
    ),
  );
}
