/// 当前楼层的操作；在菜单内预检评分权限，服务器最终裁决。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/follow_index.dart';
import '../data/post_interaction_repository.dart';
import '../data/user_block_index.dart';
import '../design/loading_tokens.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../models/models.dart';
import '../models/post_interaction.dart';
import '../ui/press.dart';
import '../ui/feedback.dart';
import '../ui/sheet_scaffold.dart';
import '../ui/user_follow_action.dart';
import 'chhers_loader.dart';

enum PostMenuAction {
  reply,
  comment,
  rating,
  supplement,
  login,
  blockUser,
  toggleFollow,
}

enum _RatingState { checking, allowed, login, self, denied, exhausted, failed }

Future<PostMenuAction?> showPostActionMenu(
  BuildContext context, {
  required Post post,
  required bool opening,
  required bool loggedIn,
  required bool blocked,
  required bool isSelf,
  Future<PostRateForm> Function()? checkRating,
  Listenable? sessionChanges,
  String? Function()? sessionIdentity,
  int Function()? sessionRevision,
  FollowIndex? follows,
}) async {
  final index = follows ?? followIndex;
  final epoch = index.epoch;
  final revision = sessionRevision?.call();
  bool isCurrent() =>
      epoch == index.epoch && revision == sessionRevision?.call();
  if (!index.accountReady) await index.load();
  if (!context.mounted || !isCurrent()) return null;
  final action = await showAppSheet<PostMenuAction>(
    context,
    builder: (context) => _PostActionMenu(
      post: post,
      opening: opening,
      loggedIn: loggedIn,
      blocked: blocked,
      isSelf: isSelf,
      checkRating: checkRating,
      sessionChanges: sessionChanges,
      sessionIdentity: sessionIdentity,
      sessionRevision: sessionRevision,
      follows: index,
    ),
  );
  if (!isCurrent()) return null;
  if (action != PostMenuAction.toggleFollow) return action;
  final uid = UserBlockIndex.normalizeUid(post.authorUid);
  if (context.mounted && uid != null) {
    await toggleUserFollow(
      context,
      uid: uid,
      name: post.author,
      avatarUrl: post.avatarUrl,
      index: index,
    );
  }
  return null;
}

class _PostActionMenu extends StatefulWidget {
  final Post post;
  final bool opening, loggedIn, blocked, isSelf;
  final FollowIndex follows;
  final Future<PostRateForm> Function()? checkRating;
  final Listenable? sessionChanges;
  final String? Function()? sessionIdentity;
  final int Function()? sessionRevision;
  const _PostActionMenu({
    required this.post,
    required this.opening,
    required this.loggedIn,
    required this.blocked,
    required this.isSelf,
    required this.follows,
    this.checkRating,
    this.sessionChanges,
    this.sessionIdentity,
    this.sessionRevision,
  });

  @override
  State<_PostActionMenu> createState() => _PostActionMenuState();
}

class _PostActionMenuState extends State<_PostActionMenu> {
  late _RatingState _rating;
  String? _identity;
  int? _revision;
  late final int _followEpoch;
  bool _invalidated = false;
  String? _ratingDescription;

  @override
  void initState() {
    super.initState();
    _identity = widget.sessionIdentity?.call();
    _revision = widget.sessionRevision?.call();
    _followEpoch = widget.follows.epoch;
    widget.sessionChanges?.addListener(_sessionChanged);
    widget.follows.addListener(_sessionChanged);
    _rating = !widget.loggedIn
        ? _RatingState.login
        : widget.isSelf
        ? _RatingState.self
        : _RatingState.checking;
    if (_rating == _RatingState.checking) _checkRating();
  }

  void _sessionChanged() {
    if (_invalidated) return;
    if (_identity == widget.sessionIdentity?.call() &&
        _revision == widget.sessionRevision?.call() &&
        _followEpoch == widget.follows.epoch) {
      return;
    }
    _invalidated = true;
    if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    widget.sessionChanges?.removeListener(_sessionChanged);
    widget.follows.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<void> _checkRating() async {
    setState(() => _rating = _RatingState.checking);
    var next = _RatingState.failed;
    try {
      final check = widget.checkRating;
      if (check != null) {
        final form = await check();
        final evil = form.scoreTypes.where((type) => type.isEvil).firstOrNull;
        _ratingDescription = evil == null
            ? null
            : '${evil.label}，今日可用 ${evil.remaining}';
        next =
            form.scoreTypes.any(
              (t) =>
                  t.isEvil &&
                  ((t.min <= -1 && t.remaining > 0) ||
                      (t.max >= 1 && t.remaining > 0)),
            )
            ? _RatingState.allowed
            : _RatingState.exhausted;
      }
    } on PostInteractionException catch (error) {
      next = switch (error.result.kind) {
        PostResultKind.loginRequired => _RatingState.login,
        PostResultKind.permissionDenied => _RatingState.denied,
        PostResultKind.selfRating => _RatingState.self,
        PostResultKind.ratingQuotaExhausted => _RatingState.exhausted,
        _ => _RatingState.failed,
      };
    } catch (_) {
      next = _RatingState.failed;
    }
    if (!mounted || _invalidated) return;
    setState(() => _rating = next);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    String? hint(PostActionPermission permission, String action) =>
        !widget.loggedIn
        ? '登录后可$action'
        : permission == PostActionPermission.denied
        ? '此楼层无法$action'
        : null;
    Widget action(
      String title,
      IconData icon,
      PostMenuAction value, {
      String? subtitle,
      bool enabled = true,
      bool destructive = false,
      bool accent = false,
      Widget? trailing,
    }) => _ActionRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      destructive: destructive,
      accent: accent,
      trailing: trailing,
      onTap: enabled ? () => Navigator.of(context).pop(value) : null,
    );
    final ratingHint = switch (_rating) {
      _RatingState.checking => '正在检查评分权限',
      _RatingState.allowed => _ratingDescription ?? '可评分',
      _RatingState.login => '登录后可评分',
      _RatingState.self => '不能给自己的帖子评分',
      _RatingState.denied => '此楼层无评分权限',
      _RatingState.exhausted => '暂无可用评分额度',
      _RatingState.failed => '暂未确认评分权限',
    };
    final t = AppTokens.of(context);
    return SheetScaffold(
      title: '更多操作',
      contextLine:
          '${post.author}，${widget.opening
              ? '主帖'
              : post.floorIsKnown
              ? '#${post.floor}'
              : '原楼层'}',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            action('回复', AppIcons.reply, PostMenuAction.reply),
            if (widget.loggedIn && widget.isSelf)
              action('补充', AppIcons.compose, PostMenuAction.supplement),
            action(
              '点评',
              AppIcons.comments,
              PostMenuAction.comment,
              subtitle: hint(post.actions.comment, '点评'),
              enabled:
                  !widget.loggedIn ||
                  post.actions.comment != PostActionPermission.denied,
            ),
            action(
              '评分',
              AppIcons.crownStar,
              _rating == _RatingState.login
                  ? PostMenuAction.login
                  : PostMenuAction.rating,
              subtitle: ratingHint,
              trailing: _rating == _RatingState.checking
                  ? ChhersSpinner(size: LoadingTokens.input, color: t.accent)
                  : _rating == _RatingState.login
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '去登录',
                          style: AppType.footnote.copyWith(
                            color: t.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(AppIcons.forward, size: 14, color: t.accent),
                      ],
                    )
                  : null,
              enabled:
                  _rating == _RatingState.allowed ||
                  _rating == _RatingState.login,
            ),
            _ActionRow(
              title: '复制文字',
              icon: AppIcons.copy,
              onTap: () async {
                final text = post.content
                    .whereType<TextBlock>()
                    .map((block) => block.text)
                    .join('\n\n')
                    .trim();
                if (text.isEmpty) {
                  AppToast.show(context, '没有可复制的文字');
                  return;
                }
                try {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!context.mounted) return;
                  AppToast.show(context, '已复制');
                  Navigator.of(context).pop();
                } catch (_) {
                  if (context.mounted) AppToast.show(context, '复制失败，请重试');
                }
              },
            ),
            if (!widget.isSelf &&
                !widget.blocked &&
                UserBlockIndex.normalizeUid(post.authorUid) != null)
              ListenableBuilder(
                listenable: widget.follows,
                builder: (context, _) {
                  final followed = widget.follows.isFollowed(post.authorUid);
                  return Semantics(
                    selected: followed,
                    child: action(
                      followed ? '取消关注' : '关注',
                      followed ? AppIcons.userCheck : AppIcons.userPlus,
                      PostMenuAction.toggleFollow,
                      accent: followed,
                    ),
                  );
                },
              ),
            if (!widget.isSelf && post.authorUid?.isNotEmpty == true)
              action(
                widget.blocked ? '解除黑名单' : '加入黑名单',
                AppIcons.forbidden,
                PostMenuAction.blockUser,
                destructive: !widget.blocked,
                accent: widget.blocked,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool destructive;
  final bool accent;
  final Widget? trailing;
  const _ActionRow({
    required this.title,
    this.subtitle,
    required this.icon,
    this.onTap,
    this.destructive = false,
    this.accent = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final color = onTap == null
        ? t.text3
        : destructive
        ? (t.isDark ? Radix.red11Dark : Radix.red11Light)
        : accent
        ? t.accent
        : t.text;
    return Semantics(
      enabled: onTap != null,
      child: PressHighlight(
        onTap: onTap,
        semanticLabel: subtitle == null ? title : '$title，$subtitle',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 34),
            child: Row(
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppType.body.copyWith(
                          color: color,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null)
                        AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? AppMotion.reducedFade
                              : AppMotion.fade,
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [...previous, ?current],
                          ),
                          child: Text(
                            subtitle!,
                            key: ValueKey(subtitle),
                            style: AppType.footnote.copyWith(color: t.text2),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
