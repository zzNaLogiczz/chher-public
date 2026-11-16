import 'package:flutter/material.dart';
import '../design/icons.dart';
import '../design/image_stack_tokens.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/press.dart';

/// The caption action becomes a dark floating collapse pill in the list.
class ImageStackModeToggle extends StatelessWidget {
  static const surfaceKey = ValueKey('image-stack-mode-surface');
  static const glyphKey = ValueKey('image-stack-mode-glyph');
  static const touchSize = 44.0;
  final bool expanded;
  final VoidCallback onPressed;
  final int total;
  final double? progress;
  const ImageStackModeToggle({
    super.key,
    required this.expanded,
    required this.onPressed,
    required this.total,
    this.progress,
  });
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final color = expanded ? Radix.whiteA12 : t.text2;
    return Semantics(
      toggled: expanded,
      child: PressScale(
        onTap: onPressed,
        semanticLabel: expanded ? '收起为堆叠卡片' : '展开全部 $total 张',
        child: Container(
          key: surfaceKey,
          height: touchSize,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 18 : 0),
          decoration: expanded
              ? BoxDecoration(
                  color: ImageStackTokens.collapseFill,
                  borderRadius: BorderRadius.circular(
                    ImageStackTokens.paperRadius,
                  ),
                )
              : null,
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  expanded ? '收起' : '展开全部',
                  style: AppType.footnote.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                RotatedBox(
                  quarterTurns: expanded ? 2 : 0,
                  child: Icon(
                    AppIcons.down,
                    key: glyphKey,
                    size: 16,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
