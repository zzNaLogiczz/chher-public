import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/smiley_store.dart';
import '../../design/composer_tokens.dart';
import '../../design/icons.dart';
import '../../design/loading_tokens.dart';
import '../../design/tokens.dart';
import '../../ui/app_button.dart';
import '../../ui/press.dart';
import '../chhers_loader.dart';
import '../net_image.dart';

class EmojiPanel extends StatelessWidget {
  final SmileyCatalog? catalog;
  final ValueChanged<SmileyEntry>? onInsert;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;
  final bool failed;

  const EmojiPanel({
    super.key,
    required this.catalog,
    required this.onInsert,
    required this.onDelete,
    required this.onRetry,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final colors = ComposerTokens.emojiColors(t);
    final radius = BorderRadius.circular(ComposerTokens.emojiRadius);
    return Material(
      color: colors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth - ComposerTokens.emojiPadding.horizontal;
          final gap = ComposerTokens.emojiCellGap;
          final columns = math.max(
            1,
            ((width + gap) / (ComposerTokens.emojiCell + gap)).floor(),
          );
          final bottom = ComposerTokens.emojiDeleteBottom
              .clamp(
                0.0,
                math.max(
                  0.0,
                  constraints.maxHeight - ComposerTokens.emojiDeleteHeight,
                ),
              )
              .toDouble();
          final data = catalog;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (data != null)
                CustomScrollView(
                  primary: false,
                  slivers: [
                    SliverPadding(
                      padding: ComposerTokens.emojiPadding.copyWith(
                        bottom: ComposerTokens.emojiGridBottom,
                      ),
                      sliver: SliverMainAxisGroup(
                        slivers: [
                          for (final group in data.groups) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: ComposerTokens.emojiCategoryPadding,
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    group.name,
                                    style: ComposerTokens.emojiCategory
                                        .copyWith(color: t.text3),
                                  ),
                                ),
                              ),
                            ),
                            SliverGrid.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    mainAxisExtent: ComposerTokens.emojiCell,
                                    mainAxisSpacing: gap,
                                    crossAxisSpacing: gap,
                                  ),
                              itemCount: group.entries.length,
                              itemBuilder: (context, index) {
                                final entry = group.entries[index];
                                return PressHighlight(
                                  semanticLabel: entry.code,
                                  onTap: onInsert == null
                                      ? null
                                      : () => onInsert!(entry),
                                  color: t.fill,
                                  borderRadius: radius,
                                  child: Center(
                                    child: NetImage(
                                      url: entry.url,
                                      width: ComposerTokens.emojiImage,
                                      height: ComposerTokens.emojiImage,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) => Center(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            entry.code,
                                            style: ComposerTokens.emojiCategory
                                                .copyWith(color: t.text2),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                )
              else
                Center(
                  child: failed
                      ? AppButton(
                          label: '表情加载失败，轻点重试',
                          variant: AppButtonVariant.plain,
                          onPressed: onRetry,
                        )
                      : Semantics(
                          liveRegion: true,
                          label: '正在加载表情',
                          child: const ChhersSpinner(
                            size: LoadingTokens.standalone,
                            delayed: true,
                          ),
                        ),
                ),
              Positioned(
                right: ComposerTokens.emojiDeleteRight,
                bottom: bottom,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.key,
                    borderRadius: radius,
                    boxShadow: ComposerTokens.emojiKeyShadow(colors.keyShadow),
                  ),
                  child: PressHighlight(
                    semanticLabel: '删除',
                    onTap: onDelete,
                    color: t.fill,
                    borderRadius: radius,
                    child: SizedBox(
                      width: ComposerTokens.emojiDeleteWidth,
                      height: ComposerTokens.emojiDeleteHeight,
                      child: Icon(
                        AppIcons.backspace,
                        size: ComposerTokens.emojiDeleteIcon,
                        color: onDelete == null ? t.text3 : t.text,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
