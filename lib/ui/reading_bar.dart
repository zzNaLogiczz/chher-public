/// 帖子页与文章页共用的阅读工具栏:"写回复…"输入胶囊 + 一个圆钮(规格 §6.9)
///
/// 圆钮在正文里显示评论数(点击去评论区),进入评论区后原地变成"回到顶部"。
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'chrome_button.dart';
import 'press.dart';

class ReadingBar extends StatelessWidget {
  static const actionKey = ValueKey('reading-bar-action');
  static const favoriteKey = ValueKey('reading-bar-favorite');

  final String placeholder;
  final VoidCallback onCompose;
  final int? count;
  final bool inComments;
  final VoidCallback onShowComments;
  final VoidCallback onBackToTop;
  final bool? favorited;
  final bool favoriteBusy;
  final VoidCallback? onToggleFavorite;

  const ReadingBar({
    super.key,
    required this.placeholder,
    required this.onCompose,
    this.count,
    required this.inComments,
    required this.onShowComments,
    required this.onBackToTop,
    this.favorited,
    this.favoriteBusy = false,
    this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final surface = BoxDecoration(
      color: t.glass,
      borderRadius: BorderRadius.circular(22),
      boxShadow: t.shadowE1,
    );
    return DecoratedBox(
      // 栏下垫一段页面底色渐变,滚动内容在这里自然淡出
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .4],
          colors: [t.bg.withValues(alpha: 0), t.bg],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 22, 14, bottom + 10),
        child: Row(
          children: [
            if (favorited != null) ...[
              Tooltip(
                message: favorited! ? '取消收藏' : '收藏',
                child: PressScale(
                  key: favoriteKey,
                  onTap: favoriteBusy ? null : onToggleFavorite,
                  semanticLabel: favorited! ? '取消收藏' : '收藏',
                  child: DecoratedBox(
                    decoration: surface,
                    child: SizedBox.square(
                      dimension: 44,
                      child: Center(
                        child: SingleMotionBuilder(
                          value: favorited! ? 1.0 : 0.0,
                          motion: AppMotion.select,
                          active: !reduced,
                          builder: (_, v, _) {
                            final p = v.clamp(0.0, 1.0);
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                Opacity(
                                  opacity: 1 - p,
                                  child: Transform.scale(
                                    scale: 1 - .3 * p,
                                    child: Icon(
                                      AppIcons.bookmark,
                                      size: 20,
                                      color: t.text,
                                    ),
                                  ),
                                ),
                                Opacity(
                                  opacity: p,
                                  child: Transform.scale(
                                    scale: .7 + .3 * p,
                                    child: Icon(
                                      AppIcons.bookmarkFilled,
                                      size: 20,
                                      color: t.accent,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: ComposeCapsule(
                placeholder: placeholder,
                onTap: onCompose,
                color: t.glass,
                shadows: t.shadowE1,
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: inComments ? '回到顶部' : '查看评论',
              child: PressScale(
                key: actionKey,
                onTap: inComments ? onBackToTop : onShowComments,
                semanticLabel: inComments ? '回到顶部' : '查看评论',
                child: SizedBox.square(
                  dimension: 44,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: surface.copyWith(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                      ),
                      // 两个图标同一位置交替:评论 ↔ 回到顶部
                      Center(
                        child: SingleMotionBuilder(
                          value: inComments ? 1.0 : 0.0,
                          motion: AppMotion.select,
                          active: !reduced,
                          builder: (_, v, _) {
                            final p = v.clamp(0.0, 1.0);
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                Opacity(
                                  opacity: 1 - p,
                                  child: Transform.scale(
                                    scale: 1 - .3 * p,
                                    child: Icon(
                                      AppIcons.comments,
                                      size: 20,
                                      color: t.text,
                                    ),
                                  ),
                                ),
                                Opacity(
                                  opacity: p,
                                  child: Transform.scale(
                                    scale: .7 + .3 * p,
                                    child: Icon(
                                      AppIcons.up,
                                      size: 20,
                                      color: t.text,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      Positioned(
                        top: -4,
                        right: -6,
                        child: CountBadge(
                          count: inComments ? 0 : (count ?? 0),
                          tone: BadgeTone.neutral,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "写回复…/写评论…"输入胶囊,点击打开编辑器。
/// 阅读工具栏用玻璃底加 e1,弹层底部用 fill 底(规格 §6.9、§7)。
class ComposeCapsule extends StatelessWidget {
  final String placeholder;
  final VoidCallback? onTap;
  final Color? color;
  final List<BoxShadow>? shadows;

  const ComposeCapsule({
    super.key,
    required this.placeholder,
    this.onTap,
    this.color,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PressScale(
      onTap: onTap,
      semanticLabel: placeholder,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? t.fill,
          borderRadius: BorderRadius.circular(22),
          boxShadow: shadows,
        ),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(AppIcons.compose, size: 18, color: t.text3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  placeholder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.subhead.copyWith(color: t.text3),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}
