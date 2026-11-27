/// Images below the editor. Standalone editors also show the add control here.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../attachments/attachment_controller.dart';
import '../design/composer_tokens.dart';
import '../design/loading_tokens.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/press.dart';
import 'chhers_loader.dart';

class AttachmentBar extends StatelessWidget {
  final AttachmentController controller;
  final bool enabled;
  final bool showAdd;

  const AttachmentBar({
    super.key,
    required this.controller,
    this.enabled = true,
    this.showAdd = true,
  });

  static const _thumb = 44.0;
  static const _height = 60.0;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.items;
        if (!showAdd && items.isEmpty) return const SizedBox.shrink();
        final size = showAdd ? _thumb : ComposerTokens.thumbnailSize;
        const trayPadding = ComposerTokens.trayPadding;
        final failed = items
            .where((i) => i.state == AttachmentState.failed)
            .firstOrNull;
        final canAdd = enabled && controller.remaining > 0;
        return DecoratedBox(
          decoration: BoxDecoration(color: t.surface),
          child: SafeArea(
            left: showAdd,
            top: false,
            right: showAdd,
            bottom: showAdd,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (failed != null)
                  Padding(
                    padding: showAdd
                        ? const EdgeInsets.fromLTRB(16, 8, 16, 0)
                        : const EdgeInsets.fromLTRB(
                            ComposerTokens.editorInset,
                            ComposerTokens.stripInset,
                            ComposerTokens.editorInset,
                            0,
                          ),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        '${failed.error ?? '图片上传失败'}。点图片重试，或移除后再发送',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.footnote.copyWith(color: t.red),
                      ),
                    ),
                  ),
                SizedBox(
                  height: showAdd ? _height : size + trayPadding.vertical,
                  child: Row(
                    children: [
                      if (showAdd) ...[
                        const SizedBox(width: 12),
                        PressScale(
                          key: const ValueKey('attachment-add'),
                          semanticLabel: controller.remaining > 0
                              ? '添加图片'
                              : '最多 ${controller.limit} 张图片',
                          onTap: canAdd ? controller.pick : null,
                          child: Container(
                            width: _thumb,
                            height: _thumb,
                            decoration: BoxDecoration(
                              color: t.fill,
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                            ),
                            child: Icon(
                              AppIcons.image,
                              size: 22,
                              color: canAdd ? t.text2 : t.text3,
                            ),
                          ),
                        ),
                      ],
                      Expanded(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          // 移除按钮伸出缩略图一角,不能被裁掉
                          clipBehavior: Clip.none,
                          padding: showAdd
                              ? const EdgeInsets.fromLTRB(12, 8, 16, 8)
                              : trayPadding.copyWith(
                                  top: 0,
                                  right:
                                      trayPadding.right -
                                      ComposerTokens.thumbnailGap,
                                ),
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(width: showAdd ? 10 : 0),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _Thumb(
                              key: ValueKey('attachment-${item.id}'),
                              item: item,
                              enabled: enabled,
                              docked: !showAdd,
                              onRetry: () => controller.retry(item.id),
                              onRemove: () => controller.remove(item.id),
                            );
                          },
                        ),
                      ),
                      if (items.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(
                            right: showAdd ? 16 : ComposerTokens.editorInset,
                          ),
                          child: Text(
                            '${items.length}/${controller.limit}',
                            style: AppType.caption.copyWith(color: t.text3),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  final ComposeImage item;
  final bool enabled;
  final bool docked;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const _Thumb({
    super.key,
    required this.item,
    required this.enabled,
    required this.docked,
    required this.onRetry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final failed = item.state == AttachmentState.failed;
    final path = item.path;
    final size = docked ? ComposerTokens.thumbnailSize : AttachmentBar._thumb;
    return SizedBox(
      // Include the badge's overhang in the hit-test bounds of the item.
      width: size + (docked ? ComposerTokens.thumbnailGap : 0),
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            top: docked ? ComposerTokens.trayPadding.top : 0,
            right: docked ? ComposerTokens.thumbnailGap : 0,
            child: PressScale(
              semanticLabel: failed ? '重试上传这张图片' : '图片',
              onTap: failed && enabled ? onRetry : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  docked ? ComposerTokens.thumbnailRadius : AppRadii.xs,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (path == null)
                      ColoredBox(color: t.fill)
                    else
                      Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        cacheWidth: (size * dpr).round(),
                        gaplessPlayback: true,
                      ),
                    if (item.pending || failed)
                      ColoredBox(
                        color: t.glassOnImage,
                        child: failed
                            ? Center(
                                child: Icon(
                                  AppIcons.refresh,
                                  size: 18,
                                  color: t.onAccent,
                                ),
                              )
                            : null,
                      ),
                    if (!failed)
                      Center(
                        child: ChhersSpinner(
                          active: item.pending,
                          size: LoadingTokens.input,
                          color: t.onAccent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // 视觉上是角上的小圆点,点击区域放大到 28
          Positioned(
            top: docked ? 0 : -12,
            right: docked ? 1 : -12,
            child: PressScale(
              semanticLabel: '移除图片',
              onTap: enabled ? onRemove : null,
              child: SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: t.text,
                      shape: CircleBorder(
                        side: docked
                            ? BorderSide(
                                color: t.surface,
                                width: ComposerTokens.thumbnailRemoveBorder,
                              )
                            : BorderSide.none,
                      ),
                    ),
                    child: SizedBox.square(
                      dimension: docked
                          ? ComposerTokens.thumbnailRemoveSize
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          AppIcons.dismiss,
                          size: 12,
                          color: t.surface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
