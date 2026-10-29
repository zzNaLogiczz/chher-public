/// 编辑器底部的图片横栏:左边添加按钮,右边缩略图
///
/// 放在编辑区之外、贴着可视区域底部:键盘弹起时随之上移,写字时随手就能加图。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../attachments/attachment_controller.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/press.dart';

class AttachmentBar extends StatelessWidget {
  final AttachmentController controller;
  final bool enabled;

  const AttachmentBar({
    super.key,
    required this.controller,
    this.enabled = true,
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
        final failed = items
            .where((i) => i.state == AttachmentState.failed)
            .firstOrNull;
        final canAdd = enabled && controller.remaining > 0;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(
              top: BorderSide(color: t.separator, width: AppSpace.hairline),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (failed != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                  height: _height,
                  child: Row(
                    children: [
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
                      Expanded(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          // 移除按钮伸出缩略图一角,不能被裁掉
                          clipBehavior: Clip.none,
                          padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _Thumb(
                              key: ValueKey('attachment-${item.id}'),
                              item: item,
                              enabled: enabled,
                              onRetry: () => controller.retry(item.id),
                              onRemove: () => controller.remove(item.id),
                            );
                          },
                        ),
                      ),
                      if (items.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
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
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const _Thumb({
    super.key,
    required this.item,
    required this.enabled,
    required this.onRetry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final failed = item.state == AttachmentState.failed;
    final path = item.path;
    const size = AttachmentBar._thumb;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: PressScale(
              semanticLabel: failed ? '重试上传这张图片' : '图片',
              onTap: failed && enabled ? onRetry : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.xs),
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
                        child: Center(
                          child: failed
                              ? Icon(
                                  AppIcons.refresh,
                                  size: 18,
                                  color: t.onAccent,
                                )
                              : SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: t.onAccent,
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // 视觉上是角上的小圆点,点击区域放大到 28
          Positioned(
            top: -12,
            right: -12,
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
                      shape: const CircleBorder(),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(AppIcons.dismiss, size: 12, color: t.surface),
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
